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
/// let view = PNLightRemoteUiView()
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

    /// Called on the main thread when the UI config fails to load (network/server error).
    public var onError: ((Error) -> Void)?

    override var loadFailureMessage: String {
        "Failed to load content"
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, deprecated, message: "Remote UI secure rendering and capture blocking are controlled by the backend.")
    public override init(frame: CGRect, secure: Bool, preventRecording: Bool = true) {
        super.init(frame: frame, secure: secure, preventRecording: preventRecording)
    }

    @available(*, deprecated, message: "Remote UI secure rendering and capture blocking are controlled by the backend. Use init() instead.")
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
/// RemoteUiView(placement: "my_placement", cardId: "my_card") { action in
///     print("Tapped:", action.url)
/// }
/// ```
@available(iOS 14, *)
public struct RemoteUiView: UIViewRepresentable {
    public let placement: String
    public let cardId: String
    @available(*, deprecated, message: "Remote UI secure rendering is controlled by the backend.")
    public let secure: Bool
    @available(*, deprecated, message: "Remote UI capture blocking is controlled by the backend.")
    public let preventRecording: Bool
    /// When true, always wait for a fresh server response instead of serving the cache.
    public let ignoreCache: Bool
    public var onAction: ((RemoteUiAction) -> Void)?
    /// Called when the UI config fails to load (network/server error).
    public var onError: ((Error) -> Void)?

    public init(
        placement: String,
        cardId: String,
        ignoreCache: Bool = false,
        onAction: ((RemoteUiAction) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.placement = placement
        self.cardId = cardId
        self.secure = true
        self.preventRecording = true
        self.ignoreCache = ignoreCache
        self.onAction = onAction
        self.onError = onError
    }

    @available(*, deprecated, message: "Remote UI secure rendering and capture blocking are controlled by the backend. Use init(placement:cardId:ignoreCache:onAction:onError:) instead.")
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
        self.ignoreCache = false
        self.onAction = onAction
        self.onError = nil
    }

    public func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.onAction = onAction
        view.onError = onError
        context.coordinator.load(into: view, placement: placement, cardId: cardId, ignoreCache: ignoreCache)
        return view
    }

    public func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {
        uiView.onAction = onAction
        uiView.onError = onError
        context.coordinator.load(into: uiView, placement: placement, cardId: cardId, ignoreCache: ignoreCache)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        private var currentPlacement: String?
        private var currentCardId: String?
        private var currentRequestId = 0

        func load(into view: PNLightRemoteUiView, placement: String, cardId: String, ignoreCache: Bool) {
            guard placement != currentPlacement || cardId != currentCardId else { return }
            currentPlacement = placement
            currentCardId = cardId
            currentRequestId += 1
            let requestId = currentRequestId
            view.secure = true
            view.showLoading()
            Task {
                let result = await PNLightSDK.shared.getUIConfigResult(placement: placement, ignoreCache: ignoreCache)
                await MainActor.run {
                    guard requestId == currentRequestId,
                          placement == currentPlacement,
                          cardId == currentCardId else { return }
                    switch result {
                    case .success(let config):
                        view.secure = config?.secure ?? true
                        view.applyConfig(configJson: config?.config, cardId: cardId)
                    case .failure(let error):
                        view.secure = true
                        view.showLoadFailure()
                        view.onError?(error)
                    }
                }
            }
        }
    }
}
