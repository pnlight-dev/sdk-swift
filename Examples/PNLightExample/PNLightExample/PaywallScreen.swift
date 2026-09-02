import SwiftUI
import PNLightSDK

struct PaywallScreen: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager

    var body: some View {
        RemoteUiView(
            placement: PNLightConfig.paywallPlacement,
            cardId: "paywall_card",
            onPurchased: { _ in
                Task { await store.refreshEntitlements() }
            },
            onAction: handleAction
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Action handling

    private func handleAction(_ action: RemoteUiAction) {
        switch action.logId {
        case "close_button":
            dismiss()

        default:
            // Treat any unrecognised action as dismiss
            dismiss()
        }
    }
}

#Preview {
    PaywallScreen()
        .environmentObject(StoreManager())
}
