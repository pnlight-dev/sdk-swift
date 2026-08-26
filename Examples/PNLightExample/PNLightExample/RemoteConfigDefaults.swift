import Foundation
import PNLightSDK

/// Application-owned fallbacks for Remote Config, registered at `initialize()`.
///
/// One key per supported type. Each default is declared with the **same type the
/// dashboard publishes**: the SDK's accessors match on the case and never coerce,
/// so a `.string("true")` default paired with a Boolean remote value means neither
/// the remote value nor the default is returned by `remoteConfigBoolean` — the
/// caller's fallback wins and published changes appear to do nothing.
///
/// Values stay on the device and are never sent to PNLight.
enum RemoteConfigDefaults {

    static let values: [String: RemoteConfigValue] = [
        "example_string": .string("hello"),
        "example_number": .number(42),
        "example_boolean": .boolean(true),
        "example_json": .jsonObject([
            "title": .string("Example"),
            "count": .number(3),
            "enabled": .boolean(false),
            "tags": .array([.string("alpha"), .string("beta")]),
        ]),
    ]

    /// The declared keys, for display in the example UI.
    static var keys: [String] {
        values.keys.sorted()
    }
}

/// Reads the Remote Config keys used by this example.
///
/// The SDK's accessors match on the stored case and never coerce, and a registered
/// default is consulted before the caller's fallback — so **the dashboard type and
/// the type declared in `RemoteConfigDefaults` must agree**. If a key is published
/// as Boolean while its default is `.string("true")`, `remoteConfigBoolean` skips
/// both the remote value and the default and returns the caller's fallback; the
/// published change looks like it did nothing. Retyping a key on the dashboard
/// means retyping its default here too.
enum RemoteConfigStore {

    private static var sdk: PNLightSDK { .shared }

    static func string(_ key: String, _ fallback: String = "") -> String {
        sdk.remoteConfigString(forKey: key, fallback: fallback)
    }

    static func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        sdk.remoteConfigBoolean(forKey: key, fallback: fallback)
    }

    static func number(_ key: String, _ fallback: Double = 0) -> Double {
        sdk.remoteConfigNumber(forKey: key, fallback: fallback)
    }

    static func jsonObject(
        _ key: String,
        _ fallback: [String: RemoteConfigJSONValue] = [:]
    ) -> [String: RemoteConfigJSONValue] {
        sdk.remoteConfigJSONObject(forKey: key, fallback: fallback)
    }

    /// Pretty-prints a JSON object value for display.
    static func prettyPrinted(_ object: [String: RemoteConfigJSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(object),
              let text = String(data: data, encoding: .utf8) else {
            return "—"
        }
        return text
    }
}
