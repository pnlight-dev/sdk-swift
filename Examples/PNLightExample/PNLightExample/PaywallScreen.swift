import SwiftUI
import PNLightSDK

struct PaywallScreen: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager

    var body: some View {
        RemoteUiView(placement: PNLightConfig.paywallPlacement, cardId: "paywall_card") { action in
            handleAction(action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Action handling

    private func handleAction(_ action: RemoteUiAction) {
        switch action.logId {
        case "purchase_button":
            let productId = action.params["id"] ?? ""
            Task { await store.purchase(productId) }

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
