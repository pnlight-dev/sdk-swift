import SwiftUI
import PNLightSDK

/// Test bench for Remote UI placements and their variants.
///
/// **Resolve** sends the same request the SDK sends and shows which variant the
/// server picked (the SDK drops `variantId` and `variantName`), then can render
/// exactly that config. **Open with RemoteUiView** goes through the real SDK
/// path with the cache bypassed, to check the integration end to end.
///
/// The API key, placement and server set here apply to the whole app, including
/// the home screen's paywall, until reset to `PNLightConfig.swift`.
struct RemoteUiTestBenchScreen: View {

    @State private var draft = RuntimeConfig.current
    @State private var applied = RuntimeConfig.current
    @State private var hasUnpersistedLaunchOverride = RuntimeConfig.isSetByLaunchArguments
    @State private var isApplying = false

    @State private var isResolving = false
    @State private var outcome: ResolveOutcome?
    @State private var preview: ServedConfig?
    @State private var showSdkView = false
    @State private var log: [LogEntry] = []

    private let userId = PNLightSDK.shared.getUserId()
    private let isLaunchOverride = RuntimeConfig.isSetByLaunchArguments

    var body: some View {
        List {
            configSection
            requestSection
            resolveSection
            sdkSection
            logSection
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Remote UI Test Bench")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $preview) { served in
            BenchCover {
                ServedConfigRenderer(
                    served: served,
                    onAction: { record(action: $0) },
                    onClosed: {
                        record("Closed via pnlight://close")
                        preview = nil
                    }
                )
            } onClose: {
                preview = nil
            }
        }
        .fullScreenCover(isPresented: $showSdkView) {
            BenchCover {
                RemoteUiView(
                    placement: applied.placement,
                    cardId: "test_bench",
                    ignoreCache: true,
                    onClosed: {
                        record("Closed via pnlight://close")
                        showSdkView = false
                    },
                    onAction: { action in
                        record(action: action)
                        if action.logId == "close_button" || action.action == "view_dismissed" {
                            showSdkView = false
                        }
                    },
                    onError: { error in
                        record("SDK error: \(error.localizedDescription)", isError: true)
                    }
                )
            } onClose: {
                showSdkView = false
            }
        }
    }

    // MARK: - Config

    private var configSection: some View {
        Section {
            configField("API key", text: $draft.apiKey, keyboard: .asciiCapable)
            configField("Remote UI placement", text: $draft.placement, keyboard: .asciiCapable)
            configField("Server", text: $draft.baseDomain, keyboard: .URL)

            HStack {
                Button("Defaults") { draft = .compiledDefault }
                Button("Local") { draft.baseDomain = RuntimeConfig.localDomain }
                Spacer()
                Button {
                    Task { await applyConfig() }
                } label: {
                    if isApplying { ProgressView() } else { Text("Apply").fontWeight(.semibold) }
                }
                .disabled(
                    (draft.trimmed == applied && !hasUnpersistedLaunchOverride)
                        || draft.validationError != nil
                        || isApplying
                )
            }
            .buttonStyle(.bordered)
        } header: {
            Text("PNLight config")
        } footer: {
            if let error = draft.validationError {
                Text(error).foregroundStyle(.red)
            } else {
                Text((isLaunchOverride ? "This run started with values from launch arguments. " : "")
                    + "Apply uses these across the app right away and keeps them for later launches. Defaults are PNLightConfig.swift. A new key or server re-initializes the SDK and clears its Remote UI cache.")
            }
        }
    }

    private func configField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .submitLabel(.done)
        }
    }

    // MARK: - Request

    private var requestSection: some View {
        Section {
            value("placement", applied.placement)

            NavigationLink {
                BenchLanguagePicker()
            } label: {
                LabeledContent("locale") {
                    Text("\(BenchLocale.sent) · \(BenchLocale.name(for: BenchLocale.sent))")
                        .font(.callout.monospaced())
                }
            }

            // These differ from `locale` when the device language isn't one the app is
            // localized into; the SDK then sends the app's language instead.
            value("device languages", Locale.preferredLanguages.prefix(3).joined(separator: ", "))
            value("Locale.current", Locale.current.identifier)
            value("sdkVersion", SDKBinary.version)
            value("sdkPlatform", "spm")
            value("schemaVersion", "\(SDKBinary.remoteUiSchemaVersion)")
            LabeledContent("userId") {
                HStack(spacing: 6) {
                    Text(userId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        UIPasteboard.general.string = userId
                        record("Copied user ID")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Request the SDK sends")
        } footer: {
            Text("Add the user ID in Dashboard → Integration → Test devices to skip placement targeting, attribution and show-once. Variants still match on locale, SDK version and platform.")
        }
    }

    // MARK: - Resolve

    private var resolveSection: some View {
        Section {
            Button {
                Task { await resolve() }
            } label: {
                HStack {
                    Label("Resolve on server", systemImage: "arrow.triangle.branch")
                    Spacer()
                    if isResolving { ProgressView() }
                }
            }
            .disabled(isResolving)

            switch outcome {
            case .none:
                EmptyView()
            case .served(let served):
                LabeledContent("Variant") {
                    Text(served.variantName ?? "Unnamed")
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                if let variantId = served.variantId {
                    value("variantId", variantId)
                }
                value("debug", served.debug == true ? "yes" : "no")
                value("protection", served.protectionMode ?? (served.secure == true ? "secure" : "off"))
                value("showOnlyOncePerUser", served.showOnlyOncePerUser == true ? "yes" : "no")
                value("config", ByteCountFormatter.string(fromByteCount: Int64(served.config?.utf8.count ?? 0), countStyle: .file))
                Button {
                    preview = served
                } label: {
                    Label("Preview served config", systemImage: "eye")
                }
                .disabled(served.config == nil)
            case .notServed(let status, let message):
                LabeledContent("HTTP \(status)") {
                    Text(message).foregroundStyle(.orange)
                }
                ForEach(Self.reasons(for: status), id: \.self) { reason in
                    Label(reason, systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Resolve")
        } footer: {
            Text("Counts as a real request: it records an impression, so a show-once placement is spent for this user.")
        }
    }

    // MARK: - SDK

    private var sdkSection: some View {
        Section("SDK path") {
            Button {
                showSdkView = true
            } label: {
                Label("Open with RemoteUiView", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }

            Button {
                PNLightSDK.shared.clearUIConfigCache()
                record("Cleared the SDK Remote UI cache")
            } label: {
                Label("Clear SDK UI cache", systemImage: "trash")
            }
        }
    }

    // MARK: - Log

    @ViewBuilder
    private var logSection: some View {
        if !log.isEmpty {
            Section {
                ForEach(log.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.caption.monospaced())
                            .foregroundStyle(entry.isError ? .red : .primary)
                        Text(entry.date.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack {
                    Text("Log")
                    Spacer()
                    Button("Clear") { log.removeAll() }
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Work

    private func applyConfig() async {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isApplying = true
        defer { isApplying = false }

        let next = draft.trimmed
        let previous = applied
        next.apply()

        if next.apiKey != previous.apiKey || next.baseDomain != previous.baseDomain {
            await PNLightSDK.shared.initialize(
                apiKey: next.apiKey,
                config: SDKConfig(baseDomain: next.baseDomain, remoteConfigDefaults: RemoteConfigDefaults.values)
            )
            // Remote UI cache keys don't include the key or server.
            PNLightSDK.shared.clearUIConfigCache()
            next.recordRemoteUiCacheScope()
            record("SDK re-initialized with key \(next.maskedApiKey) against \(next.baseDomain)")
        }
        if next.placement != previous.placement {
            record("Placement is now \(next.placement)")
        }
        // Warm the new placement the way the app does at launch.
        PNLightSDK.shared.prefetchUIConfig(placement: next.placement)

        draft = next
        applied = next
        hasUnpersistedLaunchOverride = false
        outcome = nil
    }

    private func resolve() async {
        isResolving = true
        defer { isResolving = false }

        let config = applied
        guard let url = URL(string: "\(config.baseDomain)/api/v1/sdk/\(config.apiKey)/ui") else {
            outcome = .failed("Invalid base domain")
            return
        }
        let body = UiConfigRequest(
            placement: config.placement,
            userId: userId,
            locale: BenchLocale.sent,
            sdkVersion: SDKBinary.version,
            sdkPlatform: "spm",
            schemaVersion: SDKBinary.remoteUiSchemaVersion
        )

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                let served = try JSONDecoder().decode(ServedConfig.self, from: data)
                outcome = .served(served)
                record("\(body.placement) [\(body.locale)] → \(served.variantName ?? "unnamed variant")")
            } else {
                let message = Self.errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: status)
                outcome = .notServed(status: status, message: message)
                record("\(body.placement) [\(body.locale)] → HTTP \(status) \(message)", isError: true)
            }
        } catch {
            outcome = .failed(error.localizedDescription)
            record("Resolve failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func record(action: RemoteUiAction) {
        record("action \(action.logId): \(action.url)")
    }

    private func record(_ message: String, isError: Bool = false) {
        log.append(LogEntry(message: message, isError: isError))
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }

    private func value(_ label: String, _ text: String) -> some View {
        LabeledContent(label) {
            Text(text)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The server answers every refusal with the same 404, so list what can cause one.
    private static func reasons(for status: Int) -> [String] {
        switch status {
        case 403:
            return ["The API key isn't a project on this server."]
        case 404:
            return [
                "The placement doesn't exist or is disabled.",
                "Placement targeting doesn't match this install. Campaign and account rules wait for resolved attribution.",
                "No variant matched. Variants are tried top to bottom, and without a default nothing may match.",
                "Show once per user, and this user has already seen it.",
                "Capture blocking is on and this user was caught recording.",
            ]
        default:
            return []
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = json["message"] as? String { return message }
        if let messages = json["message"] as? [String] { return messages.joined(separator: "; ") }
        return nil
    }
}

// MARK: - Wire types

/// The SDK's request body for `POST /ui`, field for field.
private struct UiConfigRequest: Encodable {
    let placement: String
    let userId: String
    let locale: String
    let sdkVersion: String
    let sdkPlatform: String
    let schemaVersion: Int
}

private struct ServedConfig: Decodable, Identifiable {
    let variantId: String?
    let variantName: String?
    let debug: Bool?
    let secure: Bool?
    let protectionMode: String?
    let showOnlyOncePerUser: Bool?
    let config: String?

    var id: String { variantId ?? "served" }
}

private enum ResolveOutcome {
    case served(ServedConfig)
    case notServed(status: Int, message: String)
    case failed(String)
}

private struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
    let isError: Bool
}

// MARK: - Rendering

/// Full-screen host with a close button that works even when the markup has none.
private struct BenchCover<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let onClose: () -> Void

    var body: some View {
        content()
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .padding(.trailing, 16)
                .accessibilityLabel("Close")
            }
    }
}

/// Renders a config the bench fetched itself. Capture protection is applied only
/// on the SDK path, since the wrapper keeps the renderer's `secure` flag internal.
private struct ServedConfigRenderer: UIViewRepresentable {
    let served: ServedConfig
    let onAction: (RemoteUiAction) -> Void
    let onClosed: () -> Void

    func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.onAction = onAction
        view.onClosed = onClosed
        view.applyConfig(configJson: served.config, cardId: "test_bench_preview")
        return view
    }

    func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {
        uiView.onAction = onAction
        uiView.onClosed = onClosed
    }
}

// MARK: - Locale

/// The locale value Remote UI receives, computed the way the SDK computes it.
enum BenchLocale {
    static let languageKey = "AppleLanguages"
    static let localeKey = "AppleLocale"

    /// `Locale.languageCode` is deprecated from iOS 16 but is what the SDK sends,
    /// so it is read through a protocol to match it exactly without a warning.
    static var sent: String {
        (Locale.current as LegacyLanguageCode).languageCode ?? "en"
    }

    /// The languages the SDK can send from this app: `Locale.current` only takes a
    /// language the app is localized into, whatever the device is set to.
    static let available: [(code: String, name: String)] = {
        let codes = Set(Bundle.main.localizations.compactMap {
            $0 == "Base" ? nil : (Locale(identifier: $0) as LegacyLanguageCode).languageCode
        })
        return codes
            .map { ($0, name(for: $0)) }
            .sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
    }()

    static func name(for code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    static var isSetByLaunchArguments: Bool {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[languageKey] != nil
    }
}

private protocol LegacyLanguageCode {
    var languageCode: String? { get }
}

extension Locale: LegacyLanguageCode {}

/// Changes the app's language for the next launch. `Locale.current` is fixed for
/// the life of the process, so the choice only takes effect after a relaunch.
private struct BenchLanguagePicker: View {
    @State private var search = ""
    @State private var chosen: String?

    var body: some View {
        List {
            if BenchLocale.isSetByLaunchArguments {
                Text("This run was launched with -AppleLanguages, which overrides the choice below.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Section {
                Button("System language") { choose(nil) }
            } footer: {
                Text("Only languages the app is localized into can be sent. Any other device language arrives as the app's development language, so declare a language in CFBundleLocalizations to test its variants.")
            }
            ForEach(filtered, id: \.code) { language in
                Button {
                    choose(language.code)
                } label: {
                    HStack {
                        Text(language.name).foregroundStyle(.primary)
                        Spacer()
                        Text(language.code)
                            .font(.callout.monospaced())
                            .foregroundStyle(language.code == BenchLocale.sent ? .green : .secondary)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Name or code")
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Relaunch to apply",
            isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } })
        ) {
            Button("Quit now", role: .destructive) { exit(0) }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The SDK reads the locale once per launch. Quit, then open the app again.")
        }
    }

    private var filtered: [(code: String, name: String)] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return BenchLocale.available }
        return BenchLocale.available.filter {
            $0.code.hasPrefix(query) || $0.name.lowercased().contains(query)
        }
    }

    private func choose(_ code: String?) {
        let defaults = UserDefaults.standard
        if let code {
            defaults.set([code], forKey: BenchLocale.languageKey)
            defaults.set(code, forKey: BenchLocale.localeKey)
        } else {
            defaults.removeObject(forKey: BenchLocale.languageKey)
            defaults.removeObject(forKey: BenchLocale.localeKey)
        }
        chosen = code ?? "system"
    }
}

#Preview {
    NavigationStack {
        RemoteUiTestBenchScreen()
    }
}
