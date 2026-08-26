import SwiftUI
import PNLightSDK

/// Reads the keys declared in `RemoteConfigDefaults`.
///
/// One key per supported type. Before a fetch the compiled-in defaults answer
/// every key; after a successful fetch the activated remote values do.
struct RemoteConfigExampleScreen: View {

    @State private var waitForAttribution = true
    @State private var bypassThrottle = false
    @State private var isFetching = false
    @State private var fetchStatus = "Not fetched"
    @State private var fetchError: String?

    @State private var provider = AttributionProviderOption.appsFlyer
    @State private var attributionIdentifier = "example-appsflyer-id"
    @State private var attributionJSON = AttributionProviderOption.nonOrganicPreset
    @State private var isSendingAttribution = false
    @State private var attributionStatus: String?
    @State private var attributionFailed = false

    @State private var stringValue = ""
    @State private var numberValue = 0.0
    @State private var booleanValue = false
    @State private var jsonValue: [String: RemoteConfigJSONValue] = [:]

    var body: some View {
        List {
            Section("Fetch") {
                LabeledContent("Status") {
                    if isFetching {
                        ProgressView()
                    } else {
                        Text(fetchStatus)
                            .foregroundStyle(statusColor)
                    }
                }

                Toggle("Wait for attribution", isOn: $waitForAttribution)
                Toggle("Bypass 15-minute throttle", isOn: $bypassThrottle)

                Button {
                    Task { await fetchRemoteConfig() }
                } label: {
                    Label("Fetch and activate", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(isFetching)

                if let fetchError {
                    Label(fetchError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Remote values are persisted by the SDK. If a fetch fails, the last activated values remain available offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Send attribution") {
                Picker("Provider", selection: $provider) {
                    ForEach(AttributionProviderOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("identifier")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Optional", text: $attributionIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption.monospaced())
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("data (JSON object)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Menu("Presets") {
                            Button("Non-organic campaign") {
                                attributionJSON = AttributionProviderOption.nonOrganicPreset
                            }
                            Button("Organic") {
                                attributionJSON = AttributionProviderOption.organicPreset
                            }
                            Button("Empty") { attributionJSON = "" }
                        }
                        .font(.caption)
                    }

                    TextEditor(text: $attributionJSON)
                        .font(.caption.monospaced())
                        .frame(minHeight: 110)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        )
                }
                .padding(.vertical, 2)

                Button {
                    Task { await sendAttribution() }
                } label: {
                    Label("Send attribution", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(isSendingAttribution)

                if isSendingAttribution {
                    ProgressView()
                } else if let attributionStatus {
                    Label(
                        attributionStatus,
                        systemImage: attributionFailed
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(attributionFailed ? .red : .green)
                }

                Text("Attribution is keyed to this installation's user ID, so the backend can resolve campaign-specific overrides for it. After sending, turn on \"Bypass 15-minute throttle\" and fetch again — a throttled fetch never reaches the backend, so new overrides would not show up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if provider != .appsFlyer {
                    Text("Only AppsFlyer attribution satisfies \"Wait for attribution\". With any other provider that toggle just waits out its 8-second timeout before fetching.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Values") {
                valueRow(key: "example_string", value: stringValue)
                valueRow(key: "example_number", value: numberValue.formatted())
                valueRow(key: "example_boolean", value: booleanValue ? "true" : "false")
            }

            Section("example_json") {
                Text(RemoteConfigStore.prettyPrinted(jsonValue))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section("Bundled defaults") {
                Text("These keys are registered at initialize(). Publish the same keys, with the same types, in Remote Config to override them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(RemoteConfigDefaults.keys, id: \.self) { key in
                    Text(key)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Remote Config")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            readActiveValues()
        }
    }

    private var statusColor: Color {
        switch fetchStatus {
        case "Activated": return .green
        case "Failed": return .red
        default: return .secondary
        }
    }

    @ViewBuilder
    private func valueRow(key: String, value: String) -> some View {
        LabeledContent {
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(key)
                .font(.caption.monospaced())
        }
    }

    @MainActor
    private func fetchRemoteConfig() async {
        isFetching = true
        fetchError = nil

        let result = await PNLightSDK.shared.fetchAndActivate(
            minimumFetchInterval: bypassThrottle ? 0 : 15 * 60,
            waitAttribution: waitForAttribution
        )

        switch result {
        case .activated:
            fetchStatus = "Activated"
        case .notModified:
            fetchStatus = "Not modified"
        case .throttled:
            fetchStatus = "Throttled"
        case .failed(let error):
            fetchStatus = "Failed"
            fetchError = error.localizedDescription
        @unknown default:
            fetchStatus = "Unknown result"
        }

        readActiveValues()
        isFetching = false
    }

    @MainActor
    private func sendAttribution() async {
        isSendingAttribution = true
        attributionStatus = nil
        defer { isSendingAttribution = false }

        // addAttribution rejects a call with neither data nor identifier, so the
        // same rule is applied here to report it as a message rather than a
        // silent `false`.
        let identifier = attributionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = attributionJSON.trimmingCharacters(in: .whitespacesAndNewlines)

        var payload: [String: Any]?
        if !json.isEmpty {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                attributionFailed = true
                attributionStatus = "data must be a JSON object"
                return
            }
            payload = object
        }

        guard payload != nil || !identifier.isEmpty else {
            attributionFailed = true
            attributionStatus = "Provide data, an identifier, or both"
            return
        }

        let sent = await PNLightSDK.shared.addAttribution(
            provider: provider.sdkValue,
            data: payload,
            identifier: identifier.isEmpty ? nil : identifier
        )

        attributionFailed = !sent
        attributionStatus = sent
            ? "Sent as \(provider.label)"
            : "Failed — check the API key, network, and payload"
    }

    @MainActor
    private func readActiveValues() {
        stringValue = RemoteConfigStore.string("example_string")
        numberValue = RemoteConfigStore.number("example_number")
        booleanValue = RemoteConfigStore.bool("example_boolean")
        jsonValue = RemoteConfigStore.jsonObject("example_json")
    }

    enum AttributionProviderOption: String, CaseIterable, Identifiable {
        case appsFlyer
        case adjust
        case firebase
        case appleAdsAttribution
        case custom
        case facebook

        var id: String { rawValue }

        var label: String {
            switch self {
            case .appsFlyer: return "AppsFlyer"
            case .adjust: return "Adjust"
            case .firebase: return "Firebase"
            case .appleAdsAttribution: return "Apple Ads"
            case .custom: return "Custom"
            case .facebook: return "Facebook"
            }
        }

        var sdkValue: PNLightSDK.AttributionProvider {
            switch self {
            case .appsFlyer: return .appsFlyer
            case .adjust: return .adjust
            case .firebase: return .firebase
            case .appleAdsAttribution: return .appleAdsAttribution
            case .custom: return .custom
            case .facebook: return .facebook
            }
        }

        static let nonOrganicPreset = """
        {
          "af_status": "Non-organic",
          "campaign": "example",
          "media_source": "test_source"
        }
        """

        static let organicPreset = """
        {
          "af_status": "Organic"
        }
        """
    }
}

#Preview {
    NavigationStack {
        RemoteConfigExampleScreen()
    }
}
