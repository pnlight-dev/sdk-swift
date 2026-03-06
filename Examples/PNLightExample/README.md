# PNLight SDK – Swift Example

Minimal iOS app demonstrating [PNLight SDK](https://github.com/pnlight-dev/sdk-swift) integration, including `RemoteUiView` for server-driven paywall UI.

## Requirements

- Xcode 15+
- iOS 16.0+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```bash
# 1. Generate the .xcodeproj
xcodegen generate

# 2. Open in Xcode
open PNLightExample.xcodeproj
```

Then replace `"YOUR_API_KEY"` in `App.swift` with your real PNLight API key.

## Project structure

```
PNLightExample/
├── App.swift            # @main entry – SDK init + prefetch
├── ContentView.swift    # Home screen (logEvent, attribution, userId)
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
| `ContentView.swift` | `addAttribution`, `getUserId`, `resetUserId` |
