import Foundation
import PNLight

public class PNLightSDK {
    public static let shared = PNLightSDK()

    public enum AttributionProvider {
        case appsFlyer
        case adjust
        case firebase
        case appleAdsAttribution
        case custom
        case facebook

        fileprivate var underlying: PNLight.PNLightSDK.AttributionProvider {
            switch self {
            case .appsFlyer: return .appsFlyer
            case .adjust: return .adjust
            case .firebase: return .firebase
            case .appleAdsAttribution: return .appleAdsAttribution
            case .custom: return .custom
            case .facebook: return .facebook
            }
        }
    }

    private init() {}

    /// Initialize the PNLight SDK with your API key
    /// - Parameters:
    ///   - apiKey: Your PNLight API key
    ///   - config: Optional configuration object to customize SDK behavior
    public func initialize(apiKey: String, config: PNLightConfig? = nil) async {
        var nextConfig = config ?? PNLightConfig()
        if nextConfig.sdkPlatform == nil {
            nextConfig.sdkPlatform = "spm"
        }
        await PNLight.PNLightSDK.shared.initialize(apiKey: apiKey, config: nextConfig)
    }

    /// Log a custom event to PNLight
    /// - Parameters:
    ///   - eventName: Name of the event
    ///   - eventArgs: Optional dictionary of event arguments
    public func logEvent(_ eventName: String, eventArgs: [String: Any]? = nil) async {
        await PNLight.PNLightSDK.shared.logEvent(eventName, eventArgs: eventArgs)
    }

    /// Get or create a stable user identifier
    /// - Returns: The user ID as a String
    public func getUserId() -> String {
        return PNLight.PNLightSDK.shared.getOrCreateUserId().id
    }

    /// Reset the user identifier
    public func resetUserId() {
        PNLight.PNLightSDK.shared.resetUserId()
    }

    /// Adds attribution data from various providers
    /// - Parameters:
    ///   - provider: The attribution provider (appsFlyer, adjust, firebase, etc.)
    ///   - data: Custom attribution data object (optional)
    ///   - identifier: Additional identifier string (optional)
    /// - Returns: True if attribution was successfully added
    @discardableResult
    public func addAttribution(provider: AttributionProvider, data: [String: Any]? = nil, identifier: String? = nil) async -> Bool {
        return await PNLight.PNLightSDK.shared.addAttribution(provider: provider.underlying, data: data, identifier: identifier)
    }

    /// Fetches and activates the Remote Config resolved for this SDK installation.
    ///
    /// When `waitAttribution` is true (the default), this waits briefly for
    /// AppsFlyer attribution so the backend can return campaign-specific
    /// overrides. Pass `false` for an immediate base-only fetch.
    public func fetchAndActivate(
        minimumFetchInterval: TimeInterval = 15 * 60,
        waitAttribution: Bool = true
    ) async -> RemoteConfigFetchResult {
        await PNLight.PNLightSDK.shared.fetchAndActivate(
            minimumFetchInterval: minimumFetchInterval,
            waitAttribution: waitAttribution
        )
    }

    public func remoteConfigBoolean(forKey key: String, fallback: Bool) -> Bool {
        PNLight.PNLightSDK.shared.remoteConfigBoolean(forKey: key, fallback: fallback)
    }

    public func remoteConfigString(forKey key: String, fallback: String) -> String {
        PNLight.PNLightSDK.shared.remoteConfigString(forKey: key, fallback: fallback)
    }

    public func remoteConfigNumber(forKey key: String, fallback: Double) -> Double {
        PNLight.PNLightSDK.shared.remoteConfigNumber(forKey: key, fallback: fallback)
    }

    public func remoteConfigStringArray(forKey key: String, fallback: [String]) -> [String] {
        PNLight.PNLightSDK.shared.remoteConfigStringArray(forKey: key, fallback: fallback)
    }

    public func remoteConfigJSONObject(
        forKey key: String,
        fallback: [String: RemoteConfigJSONValue]
    ) -> [String: RemoteConfigJSONValue] {
        PNLight.PNLightSDK.shared.remoteConfigJSONObject(forKey: key, fallback: fallback)
    }

    /// Prefetches UI config for a specific placement (background fetch, in-memory cache).
    /// - Parameter placement: The placement identifier
    public func prefetchUIConfig(placement: String) {
        PNLight.PNLightSDK.shared.prefetchUIConfig(placement: placement)
    }

    /// Gets UI config for a specific placement.
    /// - Parameters:
    ///   - placement: The placement identifier
    ///   - attributionRequired: Whether to wait for attribution before fetching
    ///   - ignoreCache: When true, bypasses the cache and waits for the server
    /// - Returns: UIConfig if available, nil otherwise
    public func getUIConfig(placement: String, attributionRequired: Bool = true, ignoreCache: Bool = false) async -> PNLight.UIConfig? {
        return await PNLight.PNLightSDK.shared.getUIConfig(placement: placement, attributionRequired: attributionRequired, ignoreCache: ignoreCache)
    }

    /// Like ``getUIConfig(placement:attributionRequired:ignoreCache:)`` but distinguishes
    /// the three outcomes so callers can show a loader / error state:
    /// - `.success(config)` — a usable config was loaded (from cache or server)
    /// - `.success(nil)` — the server has no UI for this placement
    /// - `.failure(error)` — the config could not be loaded and there was no cached fallback
    /// - Parameters:
    ///   - placement: The placement identifier
    ///   - attributionRequired: Whether to wait for attribution before fetching
    ///   - ignoreCache: When true, bypasses the cache and waits for the server
    public func getUIConfigResult(placement: String, attributionRequired: Bool = true, ignoreCache: Bool = false) async -> Result<PNLight.UIConfig?, Error> {
        return await PNLight.PNLightSDK.shared.getUIConfigResult(placement: placement, attributionRequired: attributionRequired, ignoreCache: ignoreCache)
    }

    /// Clears the in-memory UI config cache, forcing subsequent calls to fetch fresh configs.
    public func clearUIConfigCache() {
        PNLight.PNLightSDK.shared.clearUIConfigCache()
    }

    /// Reports a Remote UI capture event to PNLight.
    public func reportRemoteUiCapture() {
        PNLight.PNLightSDK.shared.reportRemoteUiCapture()
    }

    /// Returns the IDFA string when ATT is already authorized, otherwise nil.
    /// Does not prompt for ATT permission — only uses existing authorization status.
    public func getIdfa() -> String? {
        return PNLight.PNLightSDK.shared.getIdfa()
    }

    /// Sends the current IDFA to PNLight.
    /// Call it after the ATT prompt completes when the SDK was initialized before ATT authorization.
    /// - Returns: True if the IDFA was successfully sent.
    @discardableResult
    public func updateIdfa() async -> Bool {
        return await PNLight.PNLightSDK.shared.updateIdfa()
    }

    // MARK: - In-App Purchases (StoreKit 2, iOS 15+)

    /// Fetches the configured products with their App Store price/offer/trial info.
    /// - Returns: The resolved products, or an empty array if none are configured.
    public func fetchProducts() async throws -> [PNLightProduct] {
        return try await PNLight.PNLightSDK.shared.fetchProducts()
    }

    /// Purchases the product with the given id: runs the StoreKit 2 purchase,
    /// verifies the transaction, reports the receipt, and finishes it.
    public func purchase(_ productId: String) async throws -> PNLightPurchaseResult {
        return try await PNLight.PNLightSDK.shared.purchase(productId)
    }

    /// Restores previous purchases by syncing with the App Store.
    public func restorePurchases() async throws {
        try await PNLight.PNLightSDK.shared.restorePurchases()
    }

    /// Whether the user currently has an active entitlement to any configured
    /// product. Uses local StoreKit entitlements — works offline.
    public func isPremium() async -> Bool {
        return await PNLight.PNLightSDK.shared.isPremium()
    }

    /// Whether the user currently has an active entitlement to a specific product.
    public func isPurchased(_ productId: String) async -> Bool {
        return await PNLight.PNLightSDK.shared.isPurchased(productId)
    }

    /// Whether the user is eligible for a product's introductory offer (e.g. trial).
    public func isEligibleForTrial(productId: String) async -> Bool {
        return await PNLight.PNLightSDK.shared.isEligibleForTrial(productId: productId)
    }

    /// Returns the base64-encoded App Store receipt, or `nil` if none is present
    /// on device. Useful for server-side receipt validation.
    public func getAppleReceipt() async -> String? {
        return await PNLight.PNLightSDK.shared.getAppleReceipt()
    }

}

// MARK: - In-App Purchase types (re-exported from PNLight)

public typealias PNLightConfig = PNLight.PNLightConfig
public typealias RemoteConfigValue = PNLight.RemoteConfigValue
public typealias RemoteConfigJSONValue = PNLight.RemoteConfigJSONValue
public typealias RemoteConfigFetchResult = PNLight.RemoteConfigFetchResult
public typealias PNLightProduct = PNLight.PNLightProduct
public typealias PNLightSubscriptionInfo = PNLight.PNLightSubscriptionInfo
public typealias PNLightSubscriptionPeriod = PNLight.PNLightSubscriptionPeriod
public typealias PNLightSubscriptionOffer = PNLight.PNLightSubscriptionOffer
public typealias PNLightProductType = PNLight.PNLightProductType
public typealias PNLightPurchaseResult = PNLight.PNLightPurchaseResult
