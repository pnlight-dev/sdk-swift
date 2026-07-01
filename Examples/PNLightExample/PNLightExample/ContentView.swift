import SwiftUI
import PNLightSDK
import AppTrackingTransparency

struct ContentView: View {

    @EnvironmentObject private var store: StoreManager
    @State private var showPaywall = false
    @State private var showAttribution = false
    @State private var currentIdfa: String?
    @State private var trackingStatus = ATTrackingManager.trackingAuthorizationStatus

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

                Section("Test device") {
                    LabeledContent("IDFA") {
                        Text(currentIdfa ?? "Unavailable")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("ATT status") {
                        Text(trackingStatusDescription)
                            .foregroundStyle(.secondary)
                    }

                    Text("Add this IDFA in Dashboard -> Integration -> Test devices to force Remote UI test-mode delivery for this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await requestTrackingAndRefreshIdfa()
                        }
                    } label: {
                        Label("Request ATT / Refresh IDFA", systemImage: "iphone.gen3")
                    }
                }

                // In-app purchases section
                Section("In-App Purchases") {
                    NavigationLink {
                        StoreScreen()
                            .environmentObject(store)
                    } label: {
                        Label("Products & Receipt", systemImage: "cart")
                    }
                }

                // Diagnostics section
                Section("Diagnostics") {
                    NavigationLink {
                        DiagnosticsView()
                            .environmentObject(store)
                    } label: {
                        Label("SDK & IAP Diagnostics", systemImage: "stethoscope")
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
            .task {
                refreshIdfa()
                await store.refreshEntitlements()
            }
        }
    }

    private var trackingStatusDescription: String {
        switch trackingStatus {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not determined"
        @unknown default:
            return "Unknown"
        }
    }

    @MainActor
    private func refreshIdfa() {
        trackingStatus = ATTrackingManager.trackingAuthorizationStatus
        currentIdfa = PNLightSDK.shared.getIdfa()
    }

    @MainActor
    private func requestTrackingAndRefreshIdfa() async {
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await withCheckedContinuation {
                (continuation: CheckedContinuation<ATTrackingManager.AuthorizationStatus, Never>) in
                ATTrackingManager.requestTrackingAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
        refreshIdfa()
    }
}

#Preview {
    ContentView()
        .environmentObject(StoreManager())
}
