import SwiftUI
import PNLightSDK

@main
struct PNLightExampleApp: App {

    @StateObject private var store = StoreManager()

    init() {
        Task {
            // Remote Config fallbacks ship with the app, so every key reads a sane
            // value before (and without) a successful fetch.
            let config = SDKConfig(
                remoteConfigDefaults: RemoteConfigDefaults.values
            )
            await PNLightSDK.shared.initialize(apiKey: PNLightConfig.apiKey, config: config)
            PNLightSDK.shared.prefetchUIConfig(placement: PNLightConfig.paywallPlacement)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
