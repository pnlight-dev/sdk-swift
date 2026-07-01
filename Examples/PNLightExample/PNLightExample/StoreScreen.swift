import SwiftUI
import PNLightSDK

/// Exercises the PNLight in-app purchase API end to end: product catalog with
/// price / trial info, purchase, restore, entitlement checks, and the raw
/// App Store receipt.
struct StoreScreen: View {

    @EnvironmentObject private var store: StoreManager

    var body: some View {
        List {
            statusSection
            productsSection
            receiptSection
            messagesSection
        }
        .navigationTitle("In-App Purchases")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.products.isEmpty {
                await store.loadProducts()
            }
        }
        .refreshable {
            await store.loadProducts()
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Entitlements") {
            LabeledContent("Premium") {
                Label(
                    store.isPremium ? "Active" : "Inactive",
                    systemImage: store.isPremium ? "crown.fill" : "xmark.circle"
                )
                .foregroundStyle(store.isPremium ? .yellow : .secondary)
            }

            Button {
                Task { await store.restore() }
            } label: {
                HStack {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                    if store.isRestoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(store.isBusy)
        }
    }

    // MARK: - Products

    private var productsSection: some View {
        Section("Products (fetchProducts)") {
            if store.isLoadingProducts {
                HStack {
                    ProgressView()
                    Text("Loading products…")
                        .foregroundStyle(.secondary)
                }
            } else if store.products.isEmpty {
                Text("No products available.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.products, id: \.id) { product in
                    ProductRow(
                        product: product,
                        isOwned: store.purchasedProductIds.contains(product.id),
                        isTrialEligible: store.trialEligibleProductIds.contains(product.id),
                        isPurchasing: store.purchasingProductId == product.id,
                        purchaseDisabled: store.isBusy
                    ) {
                        Task { await store.purchase(product.id) }
                    }
                }
            }
        }
    }

    // MARK: - Receipt

    private var receiptSection: some View {
        Section("Receipt (getAppleReceipt)") {
            Button {
                Task { await store.loadReceipt() }
            } label: {
                Label("Load App Store Receipt", systemImage: "doc.text")
            }
            .disabled(store.isBusy)

            if let receipt = store.receipt {
                LabeledContent("Length") {
                    Text("\(receipt.count) chars")
                        .foregroundStyle(.secondary)
                }
                Text(receipt.prefix(120) + (receipt.count > 120 ? "…" : ""))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Button {
                    UIPasteboard.general.string = receipt
                } label: {
                    Label("Copy Receipt", systemImage: "doc.on.doc")
                }
            } else {
                Text("No receipt loaded.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messagesSection: some View {
        if let status = store.statusMessage {
            Section {
                Label(status, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        if let error = store.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Product row

private struct ProductRow: View {

    let product: PNLightProduct
    let isOwned: Bool
    let isTrialEligible: Bool
    let isPurchasing: Bool
    let purchaseDisabled: Bool
    let onPurchase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(product.displayName)
                    .font(.headline)
                Spacer()
                Text(product.displayPrice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !product.description.isEmpty {
                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                tag(productTypeText, systemImage: "tag")
                if let period = subscriptionPeriodText {
                    tag(period, systemImage: "clock")
                }
                if isTrialEligible, let offer = offerText {
                    tag(offer, systemImage: "gift", tint: .green)
                }
            }

            purchaseControl
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var purchaseControl: some View {
        if isOwned {
            Label("Owned", systemImage: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        } else {
            Button(action: onPurchase) {
                HStack {
                    Spacer()
                    if isPurchasing {
                        ProgressView()
                    } else {
                        Text("Buy \(product.displayPrice)")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchaseDisabled)
        }
    }

    // MARK: Formatting helpers

    private func tag(_ text: String, systemImage: String, tint: Color = .secondary) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var productTypeText: String {
        switch product.type {
        case .consumable: return "Consumable"
        case .nonConsumable: return "Non-consumable"
        case .autoRenewable: return "Auto-renewable"
        case .nonRenewable: return "Non-renewable"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    private var subscriptionPeriodText: String? {
        guard let period = product.subscription?.period else { return nil }
        return "Every \(periodText(period))"
    }

    private var offerText: String? {
        guard let offer = product.subscription?.introductoryOffer else { return nil }
        switch offer.paymentMode {
        case .freeTrial:
            return "\(periodText(offer.period)) free trial"
        case .payAsYouGo:
            return "\(offer.displayPrice) for \(offer.periodCount) × \(periodText(offer.period))"
        case .payUpFront:
            return "\(offer.displayPrice) for \(periodText(offer.period))"
        case .unknown:
            return offer.displayPrice
        @unknown default:
            return offer.displayPrice
        }
    }

    private func periodText(_ period: PNLightSubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        case .unknown: unit = "period"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? "1 \(unit)" : "\(period.value) \(unit)s"
    }
}

#Preview {
    NavigationStack {
        StoreScreen()
            .environmentObject(StoreManager())
    }
}
