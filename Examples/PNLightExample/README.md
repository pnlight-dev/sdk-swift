# PNLight SDK – Swift Example

Minimal iOS app demonstrating [PNLight SDK](https://github.com/pnlight-dev/sdk-swift) integration, including `RemoteUiView` for server-driven paywall UI, IDFA-based test devices, and backend-controlled Remote UI capture protection.

## Requirements

- Xcode 15+
- iOS 16.0+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```bash
# 1. Create your local config from the template
cp PNLightExample/PNLightConfig.example.swift PNLightExample/PNLightConfig.swift

# 2. Generate the .xcodeproj
xcodegen generate

# 3. Open in Xcode
open PNLightExample.xcodeproj
```

Then replace `"YOUR_API_KEY"` in `PNLightConfig.swift` with your real PNLight API key, and set `paywallPlacement` to your placement name. `PNLightConfig.swift` is gitignored, so your key is never committed.

To test debug Remote UI delivery on a physical device:

1. Run the example app and tap **Request ATT / Refresh IDFA**.
2. Copy the displayed IDFA.
3. Open Dashboard -> Integration -> Test devices.
4. Add the IDFA and optional label.

Remote UI secure rendering and capture blocking are controlled by the backend. The example intentionally does not pass deprecated `secure` or `preventRecording` values to `RemoteUiView`.

## Testing in-app purchases on the simulator

The example scheme ships with a **StoreKit configuration file** (`PNLightExample/Products.storekit`), so the IAP flow (`fetchProducts`, `purchase`, `restorePurchases`, entitlement checks, receipt) works on a plain simulator — no App Store Connect entry and no sandbox account needed.

> **Important:** `fetchProducts()` resolves the product IDs configured for your app on the **PNLight backend**, then asks StoreKit to resolve those IDs. The IDs in `Products.storekit` must match your backend config, or the catalog comes back empty. The bundled `com.example.pnlight.premium.*` IDs are placeholders — replace them with your real product IDs.

1. Open `Products.storekit` in Xcode and edit the products in the StoreKit editor (IDs, prices, trials, subscription periods). Make the product IDs match your backend config.
2. Run on a simulator and open **In-App Purchases**. Tap a product to buy — StoreKit presents the local purchase sheet; `restorePurchases`, `isPremium`, and the receipt all resolve against the local store.
3. While the app is running, use **Debug ▸ StoreKit ▸ Manage Transactions** to inspect, refund, or reset purchases between runs.

The StoreKit file is referenced only by the scheme's Run action and is never bundled into the app. To run against the real App Store / sandbox instead, clear it in **Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ StoreKit Configuration**.

## Project structure

```
PNLightExample/
├── App.swift            # @main entry – SDK init + prefetch
├── ContentView.swift    # Home screen (logEvent, attribution, userId, IDFA)
├── PaywallScreen.swift  # RemoteUiView paywall sheet
├── StoreScreen.swift    # In-app purchase UI (catalog, buy, restore, receipt)
├── StoreManager.swift   # StoreKit 2 IAP harness over the PNLight IAP API
├── DiagnosticsView.swift # SDK + IAP debug panel (key, products, StoreKit probe)
├── Products.storekit    # StoreKit Testing config (simulator products)
└── Info.plist
project.yml              # xcodegen spec (SPM dep + scheme/StoreKit config)
```

## Key integration points

| File | What it shows |
|------|--------------|
| `App.swift` | `PNLightSDK.shared.initialize` + `prefetchUIConfig` |
| `PaywallScreen.swift` | `RemoteUiView(placement:cardId:onAction:)` |
| `StoreScreen.swift` | IAP catalog UI driven by `StoreManager` |
| `StoreManager.swift` | `fetchProducts`, `purchase`, `restorePurchases`, `isPremium`, `getAppleReceipt` |
| `DiagnosticsView.swift` | API key, user id, products received, and a live StoreKit-config probe |
| `Products.storekit` | Local products for simulator IAP testing |
| `ContentView.swift` | `addAttribution`, `getUserId`, `resetUserId`, `getIdfa()` for Dashboard test devices |
