import Foundation
import StoreKit
import PNLightSDK

/// The product ids declared in `Products.storekit`. Used only by the debug probe
/// in `diagnoseEmptyCatalog()` to detect whether StoreKit Testing is active on a
/// simulator run. Keep these in sync with `Products.storekit`.
private let localStoreKitTestIds = [
    "com.example.pnlight.premium.monthly",
    "com.example.pnlight.premium.yearly",
    "com.example.pnlight.premium.lifetime",
]

/// Thin observable layer over the PNLight StoreKit 2 IAP API. Every published
/// property is driven by a real SDK call, so the example screens double as a
/// manual test harness for `fetchProducts`, `purchase`, `restorePurchases`,
/// `isPremium`, `isPurchased`, `isEligibleForTrial`, and `getAppleReceipt`.
@MainActor
final class StoreManager: ObservableObject {

    // Catalog + entitlement state
    @Published var products: [PNLightProduct] = []
    @Published var purchasedProductIds: Set<String> = []
    @Published var trialEligibleProductIds: Set<String> = []
    @Published var isPremium: Bool = false

    // Debug: how many ids from Products.storekit resolve directly via StoreKit.
    // nil = not probed yet; 0 = StoreKit Testing inactive; >0 = active.
    @Published var storeKitProbeCount: Int? = nil

    // In-flight flags (drive spinners / disabled buttons)
    @Published var isLoadingProducts: Bool = false
    @Published var purchasingProductId: String? = nil
    @Published var isRestoring: Bool = false

    // Receipt + user-facing messages
    @Published var receipt: String? = nil
    @Published var statusMessage: String? = nil
    @Published var errorMessage: String? = nil

    var isBusy: Bool { isLoadingProducts || purchasingProductId != nil || isRestoring }

    // MARK: - Products

    /// `fetchProducts()` — resolves the backend-configured product ids against
    /// the App Store and refreshes entitlements for the loaded products.
    func loadProducts() async {
        isLoadingProducts = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoadingProducts = false }

        do {
            products = try await PNLightSDK.shared.fetchProducts()
            if products.isEmpty {
                statusMessage = await diagnoseEmptyCatalog()
            }
            await refreshEntitlements()
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
        }
    }

    /// `fetchProducts()` returned nothing. On the simulator this is almost always
    /// one of two things — probe StoreKit directly with the ids from
    /// `Products.storekit` to tell them apart:
    /// - probe empty  → StoreKit Testing isn't active for this run (scheme/config).
    /// - probe non-empty → the backend's product ids don't match `Products.storekit`.
    private func diagnoseEmptyCatalog() async -> String {
        await probeStoreKitConfiguration()
        if storeKitProbeCount == 0 {
            return "No products. StoreKit Testing isn't active for this run — set "
                + "Products.storekit in Scheme ▸ Run ▸ Options ▸ StoreKit Configuration "
                + "(after `xcodegen generate`, reopen the project)."
        }
        return "StoreKit Testing is active (\(storeKitProbeCount ?? 0) local products), but "
            + "the backend returned no matching ids. Make the product ids in "
            + "Products.storekit match your backend's configured ids."
    }

    /// Resolves the ids from `Products.storekit` directly via StoreKit, recording
    /// the count. A non-zero count means StoreKit Testing is active for this run;
    /// zero usually means the scheme's StoreKit Configuration isn't set (or the
    /// project wasn't reopened after regenerating).
    func probeStoreKitConfiguration() async {
        let local = (try? await Product.products(for: localStoreKitTestIds)) ?? []
        storeKitProbeCount = local.count
    }

    // MARK: - Purchase

    /// `purchase(_:)` — runs the StoreKit 2 purchase, then refreshes
    /// entitlements and the on-device receipt on success.
    func purchase(_ productId: String) async {
        guard purchasingProductId == nil else { return }
        purchasingProductId = productId
        errorMessage = nil
        statusMessage = nil
        defer { purchasingProductId = nil }

        do {
            let result = try await PNLightSDK.shared.purchase(productId)
            switch result {
            case .success:
                statusMessage = "Purchase successful."
                await PNLightSDK.shared.logEvent("purchase_completed", eventArgs: [
                    "product_id": productId
                ])
                await refreshEntitlements()
                await loadReceipt()
            case .userCancelled:
                statusMessage = "Purchase cancelled."
            case .pending:
                statusMessage = "Purchase pending approval."
            @unknown default:
                statusMessage = "Purchase finished with an unknown state."
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Restore

    /// `restorePurchases()` — syncs with the App Store, then re-reads entitlements.
    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        statusMessage = nil
        defer { isRestoring = false }

        do {
            try await PNLightSDK.shared.restorePurchases()
            await refreshEntitlements()
            statusMessage = isPremium ? "Purchases restored." : "Nothing to restore."
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlements

    /// `isPremium()` + per-product `isPurchased(_:)` / `isEligibleForTrial(productId:)`.
    /// Works offline against local StoreKit entitlements.
    func refreshEntitlements() async {
        isPremium = await PNLightSDK.shared.isPremium()

        var owned: Set<String> = []
        var trialEligible: Set<String> = []
        for product in products {
            if await PNLightSDK.shared.isPurchased(product.id) {
                owned.insert(product.id)
            }
            if await PNLightSDK.shared.isEligibleForTrial(productId: product.id) {
                trialEligible.insert(product.id)
            }
        }
        purchasedProductIds = owned
        trialEligibleProductIds = trialEligible
    }

    // MARK: - Receipt

    /// `getAppleReceipt()` — base64 App Store receipt for server-side validation,
    /// or `nil` when no receipt is present on device yet.
    func loadReceipt() async {
        receipt = await PNLightSDK.shared.getAppleReceipt()
        if receipt == nil {
            statusMessage = "No receipt on device yet — make a purchase first."
        }
    }
}
