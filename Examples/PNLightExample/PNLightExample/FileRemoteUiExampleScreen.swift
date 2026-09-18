import PNLightSDK
import SwiftUI

struct FileRemoteUiExampleScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FileRemoteUiView {
            dismiss()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}

private struct FileRemoteUiView: UIViewRepresentable {
    let onClose: () -> Void

    func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.onAction = handleAction
        view.onClosed = onClose

        guard let fileUrl = Bundle.main.url(
            forResource: "RemoteUiExample",
            withExtension: "json"
        ) else {
            assertionFailure("RemoteUiExample.json is missing from the app bundle")
            view.applyConfig(configJson: nil, cardId: "file_remote_ui_example")
            return view
        }

        do {
            let configJson = try String(contentsOf: fileUrl, encoding: .utf8)
            view.applyConfig(
                configJson: configJson,
                cardId: "file_remote_ui_example"
            )
        } catch {
            assertionFailure("Failed to read RemoteUiExample.json: \(error)")
            view.applyConfig(configJson: nil, cardId: "file_remote_ui_example")
        }

        return view
    }

    func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {
        uiView.onAction = handleAction
        uiView.onClosed = onClose
    }

    private func handleAction(_ action: RemoteUiAction) {
        guard action.logId == "close_button"
            || action.action == "view_dismissed" else {
            return
        }
        onClose()
    }
}

#Preview {
    NavigationStack {
        FileRemoteUiExampleScreen()
    }
}
