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

## Project structure

```
PNLightExample/
├── App.swift            # @main entry – SDK init + prefetch
├── ContentView.swift    # Home screen (logEvent, attribution, userId, IDFA)
├── PaywallScreen.swift  # RemoteUiView paywall sheet
├── StoreManager.swift   # validatePurchase + logEvent wrapper
└── Info.plist
project.yml              # xcodegen spec (SPM dep declared here)
```

## Key integration points

| File | What it shows |
|------|--------------|
| `App.swift` | `PNLightSDK.shared.initialize` + `prefetchUIConfig` |
| `PaywallScreen.swift` | `RemoteUiView(placement:cardId:onAction:)` |
| `StoreManager.swift` | `validatePurchase()` + `logEvent(_:eventArgs:)` |
| `ContentView.swift` | `addAttribution`, `getUserId`, `resetUserId`, `getIdfa()` for Dashboard test devices |
