import SwiftUI
import PNLightSDK

struct ContentView: View {

    @EnvironmentObject private var store: StoreManager
    @State private var showPaywall = false
    @State private var showAttribution = false

    var body: some View {
        NavigationStack {
            List {
                // SDK status section
                Section("SDK") {
                    LabeledContent("User ID") {
                        Text(PNLightSDK.shared.getUserId())
                            .foregroundStyle(.secondary)
                            .font(.caption.monospaced())
                    }
                    LabeledContent("Status") {
                        Label(
                            store.isPremium ? "Premium" : "Free",
                            systemImage: store.isPremium ? "crown.fill" : "person"
                        )
                        .foregroundStyle(store.isPremium ? .yellow : .secondary)
                    }
                }

                // Actions section
                Section("Actions") {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Open Paywall (RemoteUI)", systemImage: "creditcard")
                    }

                    Button {
                        Task {
                            await PNLightSDK.shared.logEvent("home_screen_viewed")
                        }
                    } label: {
                        Label("Log Custom Event", systemImage: "text.page")
                    }

                    Button {
                        Task {
                            await PNLightSDK.shared.addAttribution(
                                provider: .appsFlyer,
                                data: ["af_status": "Non-organic", "campaign": "example"],
                                identifier: "example-appsflyer-id"
                            )
                        }
                    } label: {
                        Label("Send Attribution", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    Button(role: .destructive) {
                        PNLightSDK.shared.resetUserId()
                    } label: {
                        Label("Reset User ID", systemImage: "arrow.counterclockwise")
                    }
                }

                if let error = store.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("PNLight Example")
            .sheet(isPresented: $showPaywall) {
                PaywallScreen()
                    .environmentObject(store)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(StoreManager())
}
