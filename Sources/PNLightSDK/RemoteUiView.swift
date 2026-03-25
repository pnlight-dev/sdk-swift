import UIKit
import SwiftUI
import PNLight

/// Decoded action payload fired when a user taps a custom (non-http/https) DivKit element.
public struct RemoteUiAction {
    /// Full URL string of the triggered action.
    public let url: String
    /// URL scheme (e.g. `"myapp"`).
    public let scheme: String
    /// URL path component.
    public let path: String
    /// Query parameters extracted from the URL.
    public let params: [String: String]
    /// DivKit log ID for the triggered action.
    public let logId: String
    /// Synthetic action emitted by the SDK, for example `"view_dismissed"`.
    public let action: String?

    init(payload: RemoteUiActionPayload) {
        url = payload.url
        scheme = payload.scheme
        path = payload.path
        params = payload.params
        logId = payload.logId
        action = payload.action
    }
}

/// A UIKit view that renders a server-driven DivKit layout fetched from PNLight.
///
/// Usage:
/// ```swift
/// let view = PNLightRemoteUiView(secure: false, preventRecording: true)
/// view.onAction = { action in print(action.url) }
/// Task {
///     if let config = await PNLightSDK.shared.getUIConfig(placement: "my_placement") {
///         view.applyConfig(configJson: config.config, cardId: "my_card")
///     }
/// }
/// ```
public final class PNLightRemoteUiView: PNLightRemoteUiRendererView {
    /// Called on the main thread when the user triggers a custom (non-http/https) action.
    public var onAction: ((RemoteUiAction) -> Void)? {
        didSet {
            onCustomAction = onAction.map { handler in
                { payload in
                    handler(RemoteUiAction(payload: payload))
                }
            }
        }
    }

    override var loadFailureMessage: String {
        "Failed to load content"
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public override init(frame: CGRect, secure: Bool, preventRecording: Bool = true) {
        super.init(frame: frame, secure: secure, preventRecording: preventRecording)
    }

    public convenience init(secure: Bool = true, preventRecording: Bool = true) {
        self.init(frame: .zero, secure: secure, preventRecording: preventRecording)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - SwiftUI wrapper

/// A SwiftUI view that fetches a PNLight UI config for the given placement and renders it with DivKit.
///
/// Usage:
/// ```swift
/// RemoteUiView(placement: "my_placement", cardId: "my_card", secure: false, preventRecording: true) { action in
///     print("Tapped:", action.url)
/// }
/// ```
@available(iOS 14, *)
public struct RemoteUiView: UIViewRepresentable {
    public let placement: String
    public let cardId: String
    public let secure: Bool
    public let preventRecording: Bool
    public var onAction: ((RemoteUiAction) -> Void)?

    public init(
        placement: String,
        cardId: String,
        secure: Bool = true,
        preventRecording: Bool = true,
        onAction: ((RemoteUiAction) -> Void)? = nil
    ) {
        self.placement = placement
        self.cardId = cardId
        self.secure = secure
        self.preventRecording = preventRecording
        self.onAction = onAction
    }

    public func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView(secure: secure, preventRecording: preventRecording)
        view.onAction = onAction
        context.coordinator.load(into: view, placement: placement, cardId: cardId)
        return view
    }

    public func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {
        uiView.secure = secure
        uiView.preventRecording = preventRecording
        uiView.onAction = onAction
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        private var currentPlacement: String?

        func load(into view: PNLightRemoteUiView, placement: String, cardId: String) {
            guard placement != currentPlacement else { return }
            currentPlacement = placement
            Task { @MainActor in
                let config = await PNLightSDK.shared.getUIConfig(placement: placement)
                view.applyConfig(configJson: config?.config, cardId: cardId)
            }
        }
    }
}
