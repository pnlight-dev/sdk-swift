import Foundation
import PNLight

public class PNLightSDK {
    public static let shared = PNLightSDK()

    private init() {}

    /// Initialize the PNLight SDK with your API key
    /// - Parameter apiKey: Your PNLight API key
    public func initialize(apiKey: String) async {
        await PNLight.PNLightSDK.shared.initialize(apiKey: apiKey)
    }

    /// Validate a purchase with anti-bot protection
    /// - Parameter captcha: Whether to show captcha challenge if purchase is blocked (default: true)
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
}
