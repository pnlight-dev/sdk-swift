import SwiftUI
import PNLightSDK

@main
struct PNLightExampleApp: App {

    @StateObject private var store = StoreManager()

    init() {
        Task {
            await PNLightSDK.shared.initialize(apiKey: PNLightConfig.apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
