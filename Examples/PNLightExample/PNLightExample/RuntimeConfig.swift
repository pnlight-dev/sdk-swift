import Foundation

/// The API key, server and Remote UI placement the example runs with.
///
/// `PNLightConfig.swift` holds the compiled-in defaults. Two layers override them
/// without editing that file:
/// - launch arguments (`-PNLightAPIKey … -PNLightPlacement … -PNLightBaseDomain …`),
///   which `run.sh` passes and which win when the app starts;
/// - Apply in the Remote UI test bench, which takes effect immediately and is
///   saved for later launches that don't pass launch arguments.
struct RuntimeConfig: Equatable {
    static let productionDomain = "https://console.pnlight.app"
    static let localDomain = "http://localhost:3000"

    private enum Key {
        static let apiKey = "PNLightAPIKey"
        static let placement = "PNLightPlacement"
        static let baseDomain = "PNLightBaseDomain"
        static let remoteUiCacheScope = "PNLightRemoteUiCacheScope"
        static let all = [apiKey, placement, baseDomain]
    }

    var apiKey: String
    var placement: String
    var baseDomain: String

    /// What `PNLightConfig.swift` alone gives.
    static var compiledDefault: RuntimeConfig {
        RuntimeConfig(
            apiKey: PNLightConfig.apiKey,
            placement: PNLightConfig.paywallPlacement,
            baseDomain: productionDomain
        )
    }

    /// Applied from the bench during this run. Launch arguments live in the
    /// UserDefaults argument domain, which shadows saved values, so an in-app
    /// change is kept here to beat them until the app quits.
    private static var appliedThisRun: RuntimeConfig?

    static var current: RuntimeConfig {
        if let appliedThisRun { return appliedThisRun }
        let defaults = UserDefaults.standard
        let fallback = compiledDefault
        return RuntimeConfig(
            apiKey: nonEmpty(defaults.string(forKey: Key.apiKey)) ?? fallback.apiKey,
            placement: nonEmpty(defaults.string(forKey: Key.placement)) ?? fallback.placement,
            baseDomain: nonEmpty(defaults.string(forKey: Key.baseDomain)) ?? fallback.baseDomain
        )
    }

    /// True when this launch was started with overrides.
    static var isSetByLaunchArguments: Bool {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        return Key.all.contains { arguments[$0] != nil }
    }

    /// Makes this the config for the rest of the run and for later launches. A
    /// value equal to its compiled-in default is forgotten rather than saved, so
    /// later edits to `PNLightConfig.swift` take effect again.
    func apply() {
        Self.appliedThisRun = self
        let defaults = UserDefaults.standard
        let fallback = Self.compiledDefault
        for (key, value, defaultValue) in [
            (Key.apiKey, apiKey, fallback.apiKey),
            (Key.placement, placement, fallback.placement),
            (Key.baseDomain, baseDomain, fallback.baseDomain),
        ] {
            if value == defaultValue {
                defaults.removeObject(forKey: key)
            } else {
                defaults.set(value, forKey: key)
            }
        }
    }

    /// Whether the SDK's persisted Remote UI cache belongs to another project
    /// or server (or predates cache-scope tracking in this example).
    var requiresRemoteUiCacheReset: Bool {
        UserDefaults.standard.string(forKey: Key.remoteUiCacheScope) != remoteUiCacheScope
    }

    /// Records which project and server own the SDK's current Remote UI cache.
    func recordRemoteUiCacheScope() {
        UserDefaults.standard.set(remoteUiCacheScope, forKey: Key.remoteUiCacheScope)
    }

    var trimmed: RuntimeConfig {
        RuntimeConfig(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            placement: placement.trimmingCharacters(in: .whitespacesAndNewlines),
            baseDomain: baseDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// The first reason the backend would reject this config, checked with the
    /// same rules it applies: the API key is a UUID and placement ids are
    /// lowercase letters, digits, `_` and `-`.
    var validationError: String? {
        let config = trimmed
        if UUID(uuidString: config.apiKey) == nil {
            return "The API key must be a UUID, like 63f48b5c-2bd9-4d19-932a-b2a63c2c965a."
        }
        if config.placement.range(of: "^[a-z0-9_-]+$", options: .regularExpression) == nil {
            return "The placement may only use lowercase letters, digits, _ and -."
        }
        guard let url = URL(string: config.baseDomain),
              ["http", "https"].contains(url.scheme ?? ""),
              url.host != nil else {
            return "The server must be an http or https URL."
        }
        return nil
    }

    var maskedApiKey: String {
        guard apiKey.count > 10 else { return apiKey }
        return "\(apiKey.prefix(6))…\(apiKey.suffix(4))"
    }

    private var remoteUiCacheScope: String {
        "\(apiKey)|\(baseDomain)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
