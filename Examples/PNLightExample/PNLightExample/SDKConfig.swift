import PNLight

/// The example declares its own `PNLightConfig` (api key + placement), which shadows
/// the SDK type of the same name, and the SDK's module and its main class are both
/// called `PNLightSDK` — so the config type can't be qualified at the point of use.
///
/// This file is the only one that imports the underlying `PNLight` module, and it
/// exists solely to re-expose SDK names the rest of the app can't otherwise say.
/// Nothing else belongs here: importing `PNLight` elsewhere would make plain
/// `PNLightSDK.shared` ambiguous between the wrapper and the binary framework.
typealias SDKConfig = PNLight.PNLightConfig

/// Facts about the binary SDK that the Remote UI test bench sends and shows.
/// They come from the same `PNLight` module, so they live here for the same reason.
enum SDKBinary {
    static let version = PNLight.PNLightSDK.defaultSDKVersion
    static let remoteUiSchemaVersion = PNLight.PNLightRemoteUISchema.latestSupportedVersion
}
