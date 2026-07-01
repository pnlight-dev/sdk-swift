import SwiftUI
import PNLightSDK

/// Read-only panel surfacing the SDK + IAP state that matters when debugging:
/// the API key / user identity, the products `fetchProducts()` returned, and
/// whether the StoreKit Testing configuration is active on this simulator run.
struct DiagnosticsView: View {

    @EnvironmentObject private var store: StoreManager

    var body: some View {
        List {
            sdkSection
            productsSection
            storeKitSection
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.products.isEmpty { await store.loadProducts() }
            if store.storeKitProbeCount == nil { await store.probeStoreKitConfiguration() }
        }
        .refreshable {
            await store.loadProducts()
            await store.probeStoreKitConfiguration()
        }
    }

    // MARK: - PNLight identity

    private var sdkSection: some View {
        Section("PNLight") {
            // No separate "token" exists — the API key is the credential, and the
            // user id is the stable per-install identifier sent to the backend.
            row("API key", maskedApiKey, mono: true, copyable: PNLightConfig.apiKey)
            row("User ID", PNLightSDK.shared.getUserId(), mono: true, copyable: PNLightSDK.shared.getUserId())
            row("Placement", PNLightConfig.paywallPlacement)
            row("IDFA", PNLightSDK.shared.getIdfa() ?? "Unavailable (ATT not authorized)", mono: true)
        }
    }

    // MARK: - Products received

    @ViewBuilder
    private var productsSection: some View {
        Section("Products received (fetchProducts)") {
            LabeledContent("Count") {
                Text("\(store.products.count)")
                    .fontWeight(.semibold)
                    .foregroundStyle(store.products.isEmpty ? .red : .green)
            }

            if store.products.isEmpty {
                Text("No products resolved — see StoreKit Testing below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.products, id: \.id) { product in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.id)
                            .font(.caption.monospaced())
                        Text("\(product.displayName) · \(product.displayPrice)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                }
            }

            Button {
                Task { await store.loadProducts() }
            } label: {
                Label("Reload products", systemImage: "arrow.clockwise")
            }
            .disabled(store.isBusy)
        }
    }

    // MARK: - StoreKit Testing

    @ViewBuilder
    private var storeKitSection: some View {
        Section("StoreKit Testing (simulator)") {
            LabeledContent("Local config") {
                switch store.storeKitProbeCount {
                case .none:
                    Text("Not checked").foregroundStyle(.secondary)
                case .some(0):
                    Label("Inactive", systemImage: "xmark.circle").foregroundStyle(.red)
                case .some(let count):
                    Label("Active (\(count) products)", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }

            if store.storeKitProbeCount == 0 {
                Text("Products.storekit isn't resolving. Check Scheme ▸ Run ▸ Options ▸ "
                    + "StoreKit Configuration, then fully quit and reopen the project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let count = store.storeKitProbeCount, count > 0, store.products.isEmpty {
                Text("StoreKit Testing works, but the backend's product ids don't match "
                    + "Products.storekit. Align the ids so fetchProducts() can resolve them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await store.probeStoreKitConfiguration() }
            } label: {
                Label("Probe StoreKit config", systemImage: "stethoscope")
            }
        }
    }

    // MARK: - Helpers

    private var maskedApiKey: String {
        let key = PNLightConfig.apiKey
        guard key.count > 10 else { return key }
        return "\(key.prefix(6))…\(key.suffix(4))"
    }

    private func row(_ label: String, _ value: String, mono: Bool = false, copyable: String? = nil) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Text(value)
                    .foregroundStyle(.secondary)
                    .font(mono ? .caption.monospaced() : .body)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                if let copyable {
                    Button {
                        UIPasteboard.general.string = copyable
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
            .environmentObject(StoreManager())
    }
}
