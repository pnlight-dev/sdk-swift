import SwiftUI
import PNLightSDK

struct PaywallScreen: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager
    @State private var didRequestDismiss = false

    var body: some View {
        RemoteUiView(
            placement: RuntimeConfig.current.placement,
            cardId: "paywall_card",
            onPurchased: { _ in
                Task { await store.refreshEntitlements() }
            },
            onClosed: dismissOnce,
            onAction: handleAction
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Action handling

    private func handleAction(_ action: RemoteUiAction) {
        switch action.logId {
        case "close_button":
            dismissOnce()

        default:
            // Treat any unrecognised action as dismiss
            dismissOnce()
        }
    }

    private func dismissOnce() {
        guard !didRequestDismiss else { return }
        didRequestDismiss = true
        dismiss()
    }
}

#Preview {
    PaywallScreen()
        .environmentObject(StoreManager())
}
