import UIKit
import SwiftUI
import DivKit
import PNLight

// MARK: - Action payload

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
}

// MARK: - UIKit view

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
public final class PNLightRemoteUiView: UIView {

    // MARK: - DivKit URL handler

    private final class UrlHandler: DivUrlHandler {
        weak var owner: PNLightRemoteUiView?

        func handle(_ url: URL, info: DivActionInfo, sender: AnyObject?) {
            guard let owner else { return }
            if owner.isCustomAction(url) {
                owner.handleDivAction(info)
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:])
                }
            }
        }

        func handle(_ url: URL, sender: AnyObject?) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:])
            }
        }
    }

    // MARK: - Subviews

    private let divView: DivView
    private let divKitComponents: DivKitComponents
    private let urlHandler: UrlHandler
    private let loadingIndicator: UIActivityIndicatorView
    private let errorLabel: UILabel

    private var secureTextField: UITextField?
    private var secureContainer: UIView?

    // MARK: - Public API

    /// Called on the main thread when the user triggers a custom (non-http/https) action.
    public var onAction: ((RemoteUiAction) -> Void)?

    // MARK: - Init

    public override init(frame: CGRect) {
        urlHandler = UrlHandler()
        divKitComponents = DivKitComponents(urlHandler: urlHandler)
        divView = DivView(divKitComponents: divKitComponents)

        loadingIndicator = UIActivityIndicatorView(style: .large)
        errorLabel = UILabel()

        super.init(frame: frame)

        urlHandler.owner = self
        backgroundColor = .clear
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        loadingIndicator.center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    }

    // MARK: - Public

    /// Load and display a DivKit layout.
    /// - Parameters:
    ///   - configJson: JSON string returned by `PNLightSDK.shared.getUIConfig(placement:)`.config
    ///   - cardId: Unique card identifier used by DivKit.
    public func applyConfig(configJson: String?, cardId: String) {
        guard let configJson, !configJson.isEmpty,
              let data = configJson.data(using: .utf8) else { return }

        errorLabel.alpha = 0
        errorLabel.text = "Failed to load content"
        loadingIndicator.startAnimating()
        loadingIndicator.alpha = 1
        divView.alpha = 0

        let source = DivViewSource(
            kind: .data(data),
            cardId: DivCardID(rawValue: cardId) ?? "divkit"
        )

        Task { @MainActor in
            do {
                try await self.divView.setSource(source)
                self.showContent()
            } catch {
                self.showError(error: error)
            }
        }
    }

    // MARK: - Private helpers

    private func setupSubviews() {
        divView.frame = bounds
        divView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        divView.alpha = 0
        divView.backgroundColor = .clear

        loadingIndicator.center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        loadingIndicator.autoresizingMask = [
            .flexibleLeftMargin, .flexibleRightMargin,
            .flexibleTopMargin, .flexibleBottomMargin,
        ]
        loadingIndicator.hidesWhenStopped = false
        loadingIndicator.startAnimating()

        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.frame = bounds
        errorLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        errorLabel.alpha = 0

        let container = makeSecureContainer(frame: bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        secureContainer = container

        container.addSubview(divView)
        container.addSubview(loadingIndicator)
        container.addSubview(errorLabel)
        addSubview(container)
    }

    /// Builds a secure UIView layer that hides content during screenshots and screen recording
    /// by exploiting the `UITextField.isSecureTextEntry` private rendering layer.
    private func makeSecureContainer(frame: CGRect) -> UIView {
        let textField = UITextField(frame: frame)
        textField.isSecureTextEntry = true
        textField.isUserInteractionEnabled = false
        textField.backgroundColor = .clear
        secureTextField = textField

        guard let sublayer = textField.layer.sublayers?.first,
              let secureView = sublayer.delegate as? UIView else {
            NSLog("[PNLight][RemoteUiView] Secure container unavailable, using fallback")
            let fallback = UIView(frame: frame)
            fallback.backgroundColor = .clear
            return fallback
        }

        secureView.subviews.forEach { $0.removeFromSuperview() }
        secureView.frame = frame
        secureView.isUserInteractionEnabled = true
        secureView.backgroundColor = .clear
        secureView.clipsToBounds = true
        return secureView
    }

    private func showContent() {
        loadingIndicator.stopAnimating()
        UIView.animate(withDuration: 0.3) {
            self.loadingIndicator.alpha = 0
            self.divView.alpha = 1
        }
    }

    private func showError(error: Error) {
        errorLabel.text = "Failed to load content:\n\(error.localizedDescription)"
        loadingIndicator.stopAnimating()
        UIView.animate(withDuration: 0.3) {
            self.loadingIndicator.alpha = 0
            self.errorLabel.alpha = 1
        }
    }

    private func isCustomAction(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme != "http" && scheme != "https"
    }

    private func handleDivAction(_ action: DivActionInfo) {
        guard let onAction, let url = action.url else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var params: [String: String] = [:]
        components?.queryItems?.forEach { params[$0.name] = $0.value ?? "" }

        let payload = RemoteUiAction(
            url: url.absoluteString,
            scheme: components?.scheme ?? "",
            path: components?.path ?? "",
            params: params,
            logId: action.logId
        )
        onAction(payload)
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
    public var onAction: ((RemoteUiAction) -> Void)?

    public init(
        placement: String,
        cardId: String,
        onAction: ((RemoteUiAction) -> Void)? = nil
    ) {
        self.placement = placement
        self.cardId = cardId
        self.onAction = onAction
    }

    public func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.onAction = onAction
        context.coordinator.load(into: view, placement: placement, cardId: cardId)
        return view
    }

    public func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {
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
