# PNLight SDK - Swift Package Manager

A Swift Package Manager wrapper for the PNLight iOS SDK.

## Installation

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/pnlight-dev/sdk-swift.git", from: "0.1.1")
]
```

Or add it directly in Xcode:
1. Go to File → Add Packages...
2. Enter `https://github.com/pnlight-dev/sdk-swift.git`
3. Select the version you want to use

## Usage

```swift
import PNLightSDK

// 1. Initialize the SDK (do this first)
await PNLightSDK.shared.initialize(apiKey: "your-api-key")

// 2. Validate a purchase (call before purchase - if false, don't proceed)
let isValidPurchase = await PNLightSDK.shared.validatePurchase() // captcha defaults to true
// Or disable captcha: let isValidPurchase = await PNLightSDK.shared.validatePurchase(captcha: false)
print("Purchase validation result: \(isValidPurchase)")

// 3. Log an event (example: user completed a tutorial)
await PNLightSDK.shared.logEvent("tutorial_completed", eventArgs: [
    "level": "1",
    "duration": "300",
    "success": "true"
])
```

### Important Notes

- **Initialization**: Always initialize the SDK first before using any other methods
- **Purchase Validation**: Call `validatePurchase()` before allowing a purchase. If it returns `false`, it's better not to proceed with the purchase
- **Event Logging**: Use `logEvent()` to log events to the PNLight platform for analytics and tracking

## API Reference

### `PNLightSDK.shared`

The main SDK instance.

#### Methods

- `initialize(apiKey: String) async` - Initialize the SDK with your API key
- `validatePurchase(captcha: Bool = true) async -> Bool` - Validate a purchase with anti-bot protection. Set captcha to false to skip captcha challenge.
- `logEvent(_ eventName: String, eventArgs: [String: Any]?) async` - Log a custom event

## Requirements

- iOS 13.0+
- Swift 5.7+
