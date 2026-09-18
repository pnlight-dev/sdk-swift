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

## Running without Xcode

`run.sh` builds, installs and launches the app on a simulator using `xcodebuild` and `simctl` directly:

```bash
./run.sh                      # newest available iPhone simulator
./run.sh -d "iPhone 16 Pro"   # a specific device (name or UDID)
./run.sh -g                   # regenerate the .xcodeproj first
./run.sh -c                   # wipe DerivedData (forces package re-resolution)
./run.sh --local              # talk to a local backend (see below)
./run.sh -p onboarding        # use this Remote UI placement for the paywall and the bench
./run.sh --locale fr          # launch in French: the locale Remote UI receives
./run.sh --bench              # open the Remote UI test bench on launch
./run.sh --no-console         # launch detached instead of streaming stdout
```

It creates `PNLightConfig.swift` from the template on first run, boots the simulator if needed, and reads the app path and bundle id back out of the build settings so renames in `project.yml` can't desync it.

The SDK logs through `os_log`, not stdout, so the streamed console stays quiet. To watch SDK logs, tail the subsystem instead:

```bash
xcrun simctl spawn booted log stream --level debug \
  --predicate 'subsystem == "app.pnlight.sdk"'
```

This is also the fastest way to tell a broken project from a broken Xcode. If `run.sh` succeeds but Xcode's Run button hangs, the project and the SDK binary are fine and the problem is Xcode's own pipeline — usually package resolution or the debugger attach. Reset it with:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/PNLightExample-*
xcrun simctl shutdown all && xcrun simctl erase all
```

## Remote UI test bench

**Remote UI → Remote UI Test Bench** checks what a placement serves to this install, variant by variant:

- **PNLight config**: override the API key, the Remote UI placement and the server from inside the app. **Apply** uses them across the whole app right away (the home screen's paywall included) and keeps them for later launches. A new key or server re-initializes the SDK and clears its Remote UI cache. **Local** switches the server to `http://localhost:3000`, and **Defaults** goes back to `PNLightConfig.swift`. Values the backend would reject, like a key that isn't a UUID or a placement outside `a-z 0-9 _ -`, can't be applied.
- **Request the SDK sends**: placement, `locale`, `sdkVersion`, `sdkPlatform`, `schemaVersion` and user ID. Tap `locale` to switch the app language; it applies after a relaunch.
- **Resolve on server**: sends that request and shows the variant the server picked (name and id), or lists what can cause a 404. **Preview served config** renders exactly that config. Resolving records an impression like a real request does.
- **Open with RemoteUiView**: the real SDK path with the cache bypassed. Remote UI actions and errors appear in the log.

To run it against a local backend without touching `PNLightConfig.swift`, create `local.env` next to `run.sh`. It is gitignored and never published.

```bash
PNLIGHT_BASE_DOMAIN=http://localhost:3000   # optional, this is the default
PNLIGHT_API_KEY=<the project's access token>
```

Then run:

```bash
./run.sh --local --bench --locale de
```

Launch arguments (`--local`, `--placement`) take precedence over saved values when the app starts. Apply in the bench still replaces them for the rest of that run.

**Locale follows the app's localizations, not the device.** The SDK sends `Locale.current.languageCode`, and iOS only gives it a language the app declares. On a French device, an app localized only into English sends `en`. The example declares the App Store languages in `CFBundleLocalizations` (`project.yml`), so their variants can be tested. The bench shows the device languages next to the sent `locale` so a mismatch is visible. Test devices and debug placements skip placement targeting and attribution, but variants still match on locale, SDK version and platform.

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
├── CircularLoaderExampleScreen.swift # Local DivKit markup with a native iOS loader
├── FileRemoteUiExampleScreen.swift # Remote UI loaded from a bundled JSON file
├── FlowNavigationExampleScreen.swift # Embedded stack + server-driven native page sheet
├── HapticsExampleScreen.swift # UIKit feedback + looping Core Haptics from markup
├── LottieExampleScreen.swift # Inline Lottie rendered by DivKit with no host setup
├── RemoteConfigExampleScreen.swift # Fetch, send custom attribution, read one key per type
├── RemoteConfigDefaults.swift # Compiled-in Remote Config defaults + typed readers
├── RemoteUiTestBenchScreen.swift # Resolve a placement's variant, preview it, open it via the SDK
├── RuntimeConfig.swift  # API key, placement and server: PNLightConfig overridden by launch args or the bench
├── SDKConfig.swift      # Alias for the SDK's PNLightConfig (name-collision shim)
├── RemoteUiExample.json # Bundled schema-v2 Remote UI flow
├── PaywallScreen.swift  # RemoteUiView paywall sheet
├── StoreScreen.swift    # In-app purchase UI (catalog, buy, restore, receipt)
├── StoreManager.swift   # StoreKit 2 IAP harness over the PNLight IAP API
├── DiagnosticsView.swift # SDK + IAP debug panel (key, products, StoreKit probe)
├── Products.storekit    # StoreKit Testing config (simulator products)
└── Info.plist
project.yml              # xcodegen spec (SPM dep + scheme/StoreKit config)
run.sh                   # build + install + launch on a simulator, no Xcode
local.env                # gitignored: local backend key for run.sh --local
```

## Key integration points

| File | What it shows |
|------|--------------|
| `App.swift` | `PNLightSDK.shared.initialize` + `prefetchUIConfig` |
| `PaywallScreen.swift` | `RemoteUiView(placement:cardId:onAction:)` |
| `CircularLoaderExampleScreen.swift` | `pnlight.circular_loader` rendered from local DivKit markup |
| `FileRemoteUiExampleScreen.swift` | Loading Remote UI JSON from the app bundle and passing it to `PNLightRemoteUiView` |
| `FlowNavigationExampleScreen.swift` | One renderer driving an embedded native stack and a native page sheet |
| `HapticsExampleScreen.swift` | `pnlight://haptic/...` actions and a named looping Core Haptics pattern |
| `LottieExampleScreen.swift` | DivKit's `lottie` extension with a self-contained inline animation |
| `RemoteConfigExampleScreen.swift` | `fetchAndActivate` controls, `addAttribution` with an editable provider/identifier/JSON payload, plus string, number, Boolean and JSON-object reads |
| `RemoteUiTestBenchScreen.swift` | Which variant a placement serves for this request, previewing it, and the `RemoteUiView` path with `ignoreCache` |
| `RemoteConfigDefaults.swift` | `remoteConfigDefaults` registered at `initialize()` — one key per supported value type |
| `StoreScreen.swift` | IAP catalog UI driven by `StoreManager` |
| `StoreManager.swift` | `fetchProducts`, `purchase`, `restorePurchases`, `isPremium`, `getAppleReceipt` |
| `DiagnosticsView.swift` | API key, user id, products received, and a live StoreKit-config probe |
| `Products.storekit` | Local products for simulator IAP testing |
| `ContentView.swift` | `addAttribution`, `getUserId`, `resetUserId`, `getIdfa()` for Dashboard test devices |
