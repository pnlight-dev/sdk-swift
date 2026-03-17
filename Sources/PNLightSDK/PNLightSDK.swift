import Foundation
@_exported import PNLight

public class PNLightSDK {
    public static let shared = PNLightSDK()

    public typealias AttributionProvider = PNLight.PNLightSDK.AttributionProvider

    private init() {}

    /// Initialize the PNLight SDK with your API key
    /// - Parameters:
    ///   - apiKey: Your PNLight API key
    ///   - config: Optional configuration object to customize SDK behavior
    public func initialize(apiKey: String, config: PNLight.PNLightConfig? = nil) async {
        await PNLight.PNLightSDK.shared.initialize(apiKey: apiKey, config: config)
    }

    /// Validate a purchase with anti-bot protection
    /// - Parameter captcha: Whether to show a math CAPTCHA challenge if the purchase is blocked (default: true)
    /// - Returns: True if purchase is allowed, false if blocked
    public func validatePurchase(captcha: Bool = true) async -> Bool {
        return await PNLight.PNLightSDK.shared.validatePurchase(captcha: captcha)
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
        return await PNLight.PNLightSDK.shared.addAttribution(provider: provider, data: data, identifier: identifier)
    }

    /// Prefetches UI config for a specific placement (background fetch, in-memory cache).
    /// - Parameter placement: The placement identifier
    public func prefetchUIConfig(placement: String) {
        PNLight.PNLightSDK.shared.prefetchUIConfig(placement: placement)
    }

    /// Gets UI config for a specific placement (uses cache when available).
    /// - Parameter placement: The placement identifier
    /// - Returns: UIConfig if available, nil otherwise
    public func getUIConfig(placement: String) async -> PNLight.UIConfig? {
        return await PNLight.PNLightSDK.shared.getUIConfig(placement: placement)
    }

    /// Clears the in-memory UI config cache, forcing subsequent calls to fetch fresh configs.
    public func clearUIConfigCache() {
        PNLight.PNLightSDK.shared.clearUIConfigCache()
    }

    /// Returns the IDFA string when ATT is already authorized, otherwise nil.
    /// Does not prompt for ATT permission — only uses existing authorization status.
    public func getIdfa() -> String? {
        return PNLight.PNLightSDK.shared.getIdfa()
    }
}
