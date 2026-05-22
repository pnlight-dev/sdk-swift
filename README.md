# PNLight SDK - Swift Package Manager

[![Swift Package](https://img.shields.io/badge/Swift_Package-pnlight--dev%2Fsdk--swift-orange.svg)](https://github.com/pnlight-dev/sdk-swift)

A Swift Package Manager wrapper for the PNLight iOS SDK.

## Installation

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/pnlight-dev/sdk-swift.git", from: "0.2.1")
]
```

Or add it directly in Xcode:

1. Go to **File -> Add Packages...**
2. Enter `https://github.com/pnlight-dev/sdk-swift.git`
3. Select the version you want to use

## Requirements

- iOS 13.0+
- Swift 5.7+

---

## iOS Setup

Make sure the host iOS app links the frameworks required by PNLight:

- StoreKit.framework
- CoreMotion.framework
- AdSupport.framework
- AppTrackingTransparency.framework

For apps that need IDFA tracking, add `NSUserTrackingUsageDescription` to `Info.plist`:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This app uses device tracking to provide analytics and improve user experience.</string>
```

---

## Example Project

A complete example project is included in the `Examples/PNLightExample` directory. It demonstrates:

- SDK initialization
- Remote UI rendering with `RemoteUiView`
- Event logging, attribution, and user identity management

To run the example:

```bash
cd Examples/PNLightExample

# Generate Xcode project with xcodegen
xcodegen generate

# Open in Xcode
open PNLightExample.xcodeproj
```

Update `YOUR_API_KEY` in `App.swift` with your real credentials before running.

---

## Usage

### Initialization

Initialize PNLight before using analytics, attribution, or Remote UI:

```swift
import PNLightSDK

await PNLightSDK.shared.initialize(apiKey: "your-api-key")
```

### Event Logging

```swift
import PNLightSDK

await PNLightSDK.shared.logEvent("purchase_completed", eventArgs: [
    "product_id": "premium_subscription",
    "amount": 9.99,
    "currency": "USD"
])
```

### Attribution

Send attribution data from external providers before requesting UI config.

```swift
import PNLightSDK

let success = await PNLightSDK.shared.addAttribution(
    provider: .appsFlyer,
    data: ["af_status": "Non-organic"],
    identifier: "your-appsflyer-id"
)
```

#### AppsFlyer Integration Example

```swift
import AppsFlyerLib
import PNLightSDK
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate, AppsFlyerLibDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppsFlyerLib.shared().appsFlyerDevKey = "your-appsflyer-dev-key"
        AppsFlyerLib.shared().appleAppID = "your-ios-app-id"
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().start()
        return true
    }

    func onConversionDataSuccess(_ installData: [AnyHashable: Any]) {
        let data = Dictionary(uniqueKeysWithValues: installData.compactMap { key, value in
            guard let key = key as? String else { return nil }
            return (key, value)
        })

        Task {
            await PNLightSDK.shared.addAttribution(
                provider: .appsFlyer,
                data: data,
                identifier: AppsFlyerLib.shared().getAppsFlyerUID()
            )
        }
    }

    func onConversionDataFail(_ error: Error) {
        print("AppsFlyer conversion data error:", error)
    }
}
```

Supported providers:

- `.appsFlyer`
- `.firebase`
- `.facebook`

### User Identity

```swift
import PNLightSDK

let userId = PNLightSDK.shared.getUserId()
```

### IDFA

```swift
import PNLightSDK

if let idfa = PNLightSDK.shared.getIdfa() {
    print("IDFA:", idfa)
}
```

---

## RemoteUiView - Server-driven UI

`RemoteUiView` fetches and renders a server-driven layout from PNLight for a given placement. It calls `getUIConfig(placement:)` internally, renders the native view, and emits action events to Swift.

When using external attribution providers such as AppsFlyer, send attribution first and request UI config only after the attribution callback is processed. In production, it is recommended to wait 3-5 seconds before requesting config so provider data has time to become available.

### SwiftUI

```swift
import PNLightSDK
import SwiftUI

struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RemoteUiView(
            placement: "paywall",
            cardId: "paywall_card",
            secure: true,
            preventRecording: true
        ) { action in
            if action.logId == "purchase_button" {
                let productId = action.params["id"] ?? ""
                // Start purchase flow for productId
            } else if action.logId == "close_button" {
                dismiss()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

### UIKit

```swift
import PNLightSDK
import UIKit

final class PaywallViewController: UIViewController {
    private let remoteView = PNLightRemoteUiView(
        secure: true,
        preventRecording: true
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        remoteView.frame = view.bounds
        remoteView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(remoteView)

        remoteView.onAction = { [weak self] action in
            if action.logId == "purchase_button" {
                let productId = action.params["id"] ?? ""
                // Start purchase flow for productId
            } else if action.logId == "close_button" {
                self?.dismiss(animated: true)
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let config = await PNLightSDK.shared.getUIConfig(placement: "paywall")
            remoteView.applyConfig(configJson: config?.config, cardId: "paywall_card")
        }
    }
}
```

### Manual Config Fetching

Use `getUIConfig` if you need to fetch the placement configuration yourself. When attribution is required, call it after sending attribution and preferably after a 3-5 second delay:

```swift
import PNLightSDK

try? await Task.sleep(nanoseconds: 3_000_000_000)

let config = await PNLightSDK.shared.getUIConfig(placement: "paywall")
let configWithoutAttributionWait = await PNLightSDK.shared.getUIConfig(
    placement: "paywall",
    attributionRequired: false
)
```

### Clearing the cache

```swift
PNLightSDK.shared.clearUIConfigCache()
```

---

## API Reference

### `PNLightSDK.shared`

| Method | Description |
| --- | --- |
| `initialize(apiKey:config:) async` | Initialize the SDK with your API key and optional config |
| `logEvent(_:eventArgs:) async` | Log a custom event with optional arguments |
| `addAttribution(provider:data:identifier:) async -> Bool` | Send attribution data from AppsFlyer, Firebase, or Facebook |
| `getUserId() -> String` | Get or create a stable user identifier |
| `getIdfa() -> String?` | Return IDFA if ATT is already authorized, otherwise `nil` |
| `prefetchUIConfig(placement:)` | Prefetch a UI config into the in-memory cache |
| `getUIConfig(placement:attributionRequired:) async -> UIConfig?` | Fetch a UI config; waits for attribution by default |
| `clearUIConfigCache()` | Clear the in-memory UI config cache |

### `RemoteUiView` (SwiftUI, iOS 14+)

| Parameter | Type | Description |
| --- | --- | --- |
| `placement` | `String` | PNLight placement identifier |
| `cardId` | `String` | Card identifier |
| `secure` | `Bool` | Prevent screenshots and recordings; defaults to `true` |
| `preventRecording` | `Bool` | Dismiss and block Remote UI after a capture attempt; defaults to `true` |
| `onAction` | `((RemoteUiAction) -> Void)?` | Called when a custom action is triggered |

### `PNLightRemoteUiView` (UIKit)

| Member | Description |
| --- | --- |
| `onAction: ((RemoteUiAction) -> Void)?` | Called on the main thread when a custom action fires |
| `applyConfig(configJson:cardId:)` | Load and render a server-driven layout from a JSON string |

### `RemoteUiAction`

| Property | Type | Description |
| --- | --- | --- |
| `url` | `String` | Full URL string of the triggered action |
| `scheme` | `String` | URL scheme |
| `path` | `String` | URL path component |
| `params` | `[String: String]` | Query parameters extracted from the URL |
| `logId` | `String` | Log ID for the triggered action |
| `action` | `String?` | Raw action value when provided by the native view |
