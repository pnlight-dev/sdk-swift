# PNLight SDK - Swift Package Manager

A Swift Package Manager wrapper for the PNLight iOS SDK.

## Installation

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/pnlight-dev/sdk-swift.git", from: "0.2.0")
]
```

Or add it directly in Xcode:

1. Go to **File → Add Packages...**
2. Enter `https://github.com/pnlight-dev/sdk-swift.git`
3. Select the version you want to use

## Requirements

- iOS 13.0+
- Swift 5.7+

---

## Usage

### Initialization

```swift
import PNLightSDK

await PNLightSDK.shared.initialize(apiKey: "your-api-key")
```

### Purchase Validation

```swift
let isAllowed = await PNLightSDK.shared.validatePurchase()
let isAllowed = await PNLightSDK.shared.validatePurchase(captcha: false)
```

### Event Logging

```swift
await PNLightSDK.shared.logEvent("purchase_completed", eventArgs: [
    "product_id": "premium_subscription",
    "amount": 9.99
])
```

### Attribution

```swift
await PNLightSDK.shared.addAttribution(
    provider: .appsFlyer,
    data: ["af_status": "Non-organic"],
    identifier: "your-appsflyer-id"
)
```

### User Identity

```swift
let userId = PNLightSDK.shared.getUserId()
PNLightSDK.shared.resetUserId()
```

### IDFA

```swift
if let idfa = PNLightSDK.shared.getIdfa() {
    print("IDFA:", idfa)
}
```

---

## RemoteUiView — Server-driven UI

`RemoteUiView` fetches and renders a DivKit layout from PNLight for a given placement. It handles loading and error states automatically.

### SwiftUI

```swift
import PNLightSDK
import SwiftUI

struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: StoreManager

    var body: some View {
        RemoteUiView(placement: "paywall", cardId: "paywall_card") { action in
            if action.logId == "paywall_button" {
                navigationPath.append(Route.paywall)
            } else if action.logId == "purchase_button" {
                let productId = action.params["id"] ?? ""
                Task { await store.purchase(productId) }
            } else if action.logId == "close_button" {
                dismiss()
            } else {
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

final class PaywallViewController: UIViewController {

    private let remoteView = PNLightRemoteUiView()

    override func viewDidLoad() {
        super.viewDidLoad()

        remoteView.frame = view.bounds
        remoteView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(remoteView)

        remoteView.onAction = { [weak self] action in
            if action.logId == "paywall_button" {
                self?.showPaywall()
            } else if action.logId == "purchase_button" {
                let productId = action.params["id"] ?? ""
                Task { await self?.store.purchase(productId) }
            } else if action.logId == "close_button" {
                self?.navigateToMain()
            } else {
                self?.navigateToMain()
            }
        }

        Task {
            let config = await PNLightSDK.shared.getUIConfig(placement: "paywall")
            remoteView.applyConfig(configJson: config?.config, cardId: "paywall_card")
        }
    }
}
```

### Prefetching

Call `prefetchUIConfig` early (e.g. at app launch) to warm the in-memory cache so `RemoteUiView` renders instantly:

```swift
PNLightSDK.shared.prefetchUIConfig(placement: "paywall")
```

### Clearing the cache

```swift
PNLightSDK.shared.clearUIConfigCache()
```

---

## API Reference

### `PNLightSDK.shared`


| Method                                                    | Description                                                                   |
| --------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `initialize(apiKey:config:) async`                        | Initialize the SDK with your API key and optional config                      |
| `validatePurchase(captcha:) async -> Bool`                | Validate a purchase; shows a CAPTCHA challenge when blocked (default: `true`) |
| `logEvent(_:eventArgs:) async`                            | Log a custom event with optional arguments                                    |
| `addAttribution(provider:data:identifier:) async -> Bool` | Send attribution data from AppsFlyer, Adjust, Firebase, etc.                  |
| `getUserId() -> String`                                   | Get or create a stable user identifier                                        |
| `resetUserId()`                                           | Reset the user identifier                                                     |
| `getIdfa() -> String?`                                    | Return IDFA if ATT is already authorized, otherwise `nil`                     |
| `prefetchUIConfig(placement:)`                            | Prefetch a UI config into the in-memory cache                                 |
| `getUIConfig(placement:) async -> UIConfig?`              | Fetch a UI config (uses cache when available)                                 |
| `clearUIConfigCache()`                                    | Clear the in-memory UI config cache                                           |


### `RemoteUiView` (SwiftUI, iOS 14+)


| Parameter   | Type                          | Description                              |
| ----------- | ----------------------------- | ---------------------------------------- |
| `placement` | `String`                      | PNLight placement identifier             |
| `cardId`    | `String`                      | DivKit card identifier                   |
| `onAction`  | `((RemoteUiAction) -> Void)?` | Called when a custom action is triggered |


### `PNLightRemoteUiView` (UIKit)


| Member                                  | Description                                          |
| --------------------------------------- | ---------------------------------------------------- |
| `onAction: ((RemoteUiAction) -> Void)?` | Called on the main thread when a custom action fires |
| `applyConfig(configJson:cardId:)`       | Load and render a DivKit layout from a JSON string   |


### `RemoteUiAction`


| Property | Type               | Description                             |
| -------- | ------------------ | --------------------------------------- |
| `url`    | `String`           | Full URL string of the triggered action |
| `scheme` | `String`           | URL scheme (e.g. `"myapp"`)             |
| `path`   | `String`           | URL path component                      |
| `params` | `[String: String]` | Query parameters extracted from the URL |
| `logId`  | `String`           | DivKit log ID for the triggered action  |


### `AttributionProvider`

`.appsFlyer` · `.adjust` · `.firebase` · `.appleAdsAttribution` · `.facebook` · `.custom`