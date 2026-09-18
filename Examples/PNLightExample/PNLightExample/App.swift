import SwiftUI
import PNLightSDK

@main
struct PNLightExampleApp: App {

    @StateObject private var store = StoreManager()

    init() {
        Task {
            // PNLightConfig.swift unless overridden from run.sh or the Remote UI test bench.
            let runtime = RuntimeConfig.current
            // Remote Config fallbacks ship with the app, so every key reads a sane
            // value before (and without) a successful fetch.
            let config = SDKConfig(
                baseDomain: runtime.baseDomain,
                remoteConfigDefaults: RemoteConfigDefaults.values
            )
            if runtime.requiresRemoteUiCacheReset {
                PNLightSDK.shared.clearUIConfigCache()
                runtime.recordRemoteUiCacheScope()
            }
            await PNLightSDK.shared.initialize(apiKey: runtime.apiKey, config: config)
            PNLightSDK.shared.prefetchUIConfig(placement: runtime.placement)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
