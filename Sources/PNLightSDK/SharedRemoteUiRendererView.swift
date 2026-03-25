import UIKit
import DivKit
import PNLight

struct RemoteUiActionPayload {
    let url: String
    let scheme: String
    let path: String
    let params: [String: String]
    let logId: String
    let action: String?

    init(action: DivActionInfo) {
        let resolvedUrl = action.url
        let components = resolvedUrl.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }

        var extractedParams: [String: String] = [:]
        components?.queryItems?.forEach { extractedParams[$0.name] = $0.value ?? "" }

        url = resolvedUrl?.absoluteString ?? ""
        scheme = components?.scheme ?? ""
        path = components?.path ?? ""
        params = extractedParams
        logId = action.logId
        self.action = nil
    }

    init(customAction: String) {
        url = ""
        scheme = ""
        path = ""
        params = [:]
        logId = customAction
        action = customAction
    }

    func asDictionary() -> [String: Any] {
        var payload: [String: Any] = ["logId": logId]

        if let action = action {
            payload["action"] = action
        }

        if !url.isEmpty {
            payload["url"] = url
            payload["scheme"] = scheme
            payload["path"] = path
            if !params.isEmpty {
                payload["params"] = params
            }
        }

        return payload
    }
}

public class PNLightRemoteUiRendererView: UIView {
    private final class UrlHandler: DivUrlHandler {
        weak var owner: PNLightRemoteUiRendererView?

        func handle(_ url: URL, info: DivActionInfo, sender: AnyObject?) {
            guard let owner else { return }

            if owner.isCustomAction(url) {
                owner.onCustomAction?(RemoteUiActionPayload(action: info))
                return
            }

            owner.open(url)
        }

        func handle(_ url: URL, sender: AnyObject?) {
            owner?.open(url)
        }
    }

    private let divView: DivView
    private let loadingIndicator: UIActivityIndicatorView
    private let errorLabel: UILabel
    private let contentContainer: UIView
    private let urlHandler: UrlHandler
    private let dismissActionName = "view_dismissed"
    private var captureObservers: [NSObjectProtocol] = []
    private var hasHandledCaptureAttempt = false
    private var pendingDismissAction = false
    var secure: Bool {
        didSet {
            guard secure != oldValue else { return }
            updateContainerView()
        }
    }
    var preventRecording: Bool {
        didSet {
            guard preventRecording != oldValue else { return }
            updateCaptureMonitoring()
        }
    }
    private var secureTextField: UITextField?
    private var containerView: UIView?

    var onCustomAction: ((RemoteUiActionPayload) -> Void)? {
        didSet {
            flushPendingDismissActionIfNeeded()
            if preventRecording {
                evaluateCaptureStateIfNeeded()
            }
        }
    }

    var loadFailureMessage: String {
        "Failed to load DivKit content"
    }

    public override init(frame: CGRect) {
        secure = true
        preventRecording = true
        urlHandler = UrlHandler()
        let divKitComponents = DivKitComponents(urlHandler: urlHandler)
        divView = DivView(divKitComponents: divKitComponents)
        loadingIndicator = UIActivityIndicatorView(style: .large)
        errorLabel = UILabel()
        contentContainer = UIView()

        super.init(frame: frame)

        urlHandler.owner = self
        backgroundColor = .clear
        setupSubviews()
        updateCaptureMonitoring()
    }

    public init(frame: CGRect, secure: Bool, preventRecording: Bool = true) {
        self.secure = secure
        self.preventRecording = preventRecording
        urlHandler = UrlHandler()
        let divKitComponents = DivKitComponents(urlHandler: urlHandler)
        divView = DivView(divKitComponents: divKitComponents)
        loadingIndicator = UIActivityIndicatorView(style: .large)
        errorLabel = UILabel()
        contentContainer = UIView()

        super.init(frame: frame)

        urlHandler.owner = self
        backgroundColor = .clear
        setupSubviews()
        updateCaptureMonitoring()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopCaptureMonitoring()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        loadingIndicator.center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        evaluateCaptureStateIfNeeded()
    }

    public func applyConfig(configJson: String?, cardId: String) {
        guard let configJson, !configJson.isEmpty,
              let data = configJson.data(using: .utf8) else {
            return
        }

        errorLabel.alpha = 0
        errorLabel.text = loadFailureMessage
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
                self.showError(error)
            }
        }
    }

    private func setupSubviews() {
        contentContainer.frame = bounds
        contentContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentContainer.backgroundColor = .clear

        divView.frame = bounds
        divView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        divView.alpha = 0
        divView.backgroundColor = .clear

        loadingIndicator.center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        loadingIndicator.autoresizingMask = [
            .flexibleLeftMargin,
            .flexibleRightMargin,
            .flexibleTopMargin,
            .flexibleBottomMargin,
        ]
        loadingIndicator.hidesWhenStopped = false
        loadingIndicator.startAnimating()

        errorLabel.text = loadFailureMessage
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.frame = bounds
        errorLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        errorLabel.alpha = 0

        contentContainer.addSubview(divView)
        contentContainer.addSubview(loadingIndicator)
        contentContainer.addSubview(errorLabel)
        updateContainerView()
    }

    private func updateContainerView() {
        let nextContainer = secure
            ? makeSecureContainer(frame: bounds)
            : makePlainContainer(frame: bounds)
        nextContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        contentContainer.removeFromSuperview()
        nextContainer.addSubview(contentContainer)

        containerView?.removeFromSuperview()
        addSubview(nextContainer)
        containerView = nextContainer
    }

    private func updateCaptureMonitoring() {
        stopCaptureMonitoring()

        guard preventRecording else { return }

        let notificationCenter = NotificationCenter.default

        captureObservers.append(
            notificationCenter.addObserver(
                forName: UIApplication.userDidTakeScreenshotNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleCaptureAttemptIfNeeded()
            }
        )

        captureObservers.append(
            notificationCenter.addObserver(
                forName: UIScreen.capturedDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateCaptureStateIfNeeded()
            }
        )

        captureObservers.append(
            notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateCaptureStateIfNeeded()
            }
        )
    }

    private func stopCaptureMonitoring() {
        captureObservers.forEach(NotificationCenter.default.removeObserver)
        captureObservers.removeAll()
    }

    private func evaluateCaptureStateIfNeeded() {
        guard preventRecording, isAnyScreenCaptured else { return }
        handleCaptureAttemptIfNeeded()
    }

    private var isAnyScreenCaptured: Bool {
        UIScreen.screens.contains { $0.isCaptured }
    }

    private func handleCaptureAttemptIfNeeded() {
        guard hasHandledCaptureAttempt == false else { return }

        hasHandledCaptureAttempt = true
        pendingDismissAction = true
        PNLightSDK.shared.markRemoteUiBlocked()
        flushPendingDismissActionIfNeeded()
    }

    private func flushPendingDismissActionIfNeeded() {
        guard pendingDismissAction, let onCustomAction = onCustomAction else { return }

        pendingDismissAction = false
        onCustomAction(RemoteUiActionPayload(customAction: dismissActionName))
    }

    private func makeSecureContainer(frame: CGRect) -> UIView {
        let textField = UITextField(frame: frame)
        textField.isSecureTextEntry = true
        textField.isUserInteractionEnabled = false
        textField.backgroundColor = .clear
        secureTextField = textField

        guard let secureLayer = textField.layer.sublayers?.first,
              let secureView = secureLayer.delegate as? UIView else {
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

    private func makePlainContainer(frame: CGRect) -> UIView {
        secureTextField = nil
        let container = UIView(frame: frame)
        container.backgroundColor = .clear
        container.clipsToBounds = true
        return container
    }

    private func showContent() {
        loadingIndicator.stopAnimating()
        UIView.animate(withDuration: 0.3) {
            self.loadingIndicator.alpha = 0
            self.divView.alpha = 1
        }
    }

    private func showError(_ error: Error) {
        errorLabel.text = "\(loadFailureMessage):\n\(error.localizedDescription)"
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

    private func open(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
