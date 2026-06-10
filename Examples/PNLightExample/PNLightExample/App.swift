import SwiftUI
import PNLightSDK

@main
struct PNLightExampleApp: App {

    @StateObject private var store = StoreManager()

    init() {
        Task {
            await PNLightSDK.shared.initialize(apiKey: PNLightConfig.apiKey)
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
