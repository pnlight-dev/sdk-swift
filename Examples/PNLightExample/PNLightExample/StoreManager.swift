import Foundation
import PNLightSDK

@MainActor
final class StoreManager: ObservableObject {

    @Published var isPremium: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var errorMessage: String? = nil

    func purchase(_ productId: String) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil

        defer { isPurchasing = false }

        // Validate purchase through PNLight (shows CAPTCHA if flagged)
        let isAllowed = await PNLightSDK.shared.validatePurchase()
        guard isAllowed else {
            errorMessage = "Purchase was blocked. Please try again."
            return
        }

        // TODO: Trigger your StoreKit purchase flow here using productId
        // On success, log the event:
        await PNLightSDK.shared.logEvent("purchase_completed", eventArgs: [
            "product_id": productId
        ])

        isPremium = true
    }
}
