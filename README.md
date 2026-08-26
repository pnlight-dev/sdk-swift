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

- iOS 15.0+
- Swift 5.7+

---

## iOS Setup

Make sure the host iOS app links the frameworks required by PNLight:

- StoreKit.framework
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

### Remote Config

Remote Config resolves a published, per-install JSON configuration on the
server. Set non-sensitive application defaults locally; they are never
uploaded. The active response is persisted, so app startup and typed reads work
offline. Do not store credentials, API keys, or other secrets in Remote Config.

Use the `PNLightSDK` facade just like the other SDK features:

```swift
import PNLightSDK

let config = PNLightConfig(remoteConfigDefaults: [
    "paywall_enabled": .boolean(false),
    "welcome_title": .string("Welcome"),
])
await PNLightSDK.shared.initialize(apiKey: "your-api-key", config: config)

// Waits briefly for attribution-dependent overrides by default.
let result = await PNLightSDK.shared.fetchAndActivate()
let isPaywallEnabled = PNLightSDK.shared.remoteConfigBoolean(
    forKey: "paywall_enabled",
    fallback: false
)

// Use an immediate base-only fetch during development or when required.
let immediateResult = await PNLightSDK.shared.fetchAndActivate(
    minimumFetchInterval: 0,
    waitAttribution: false
)
```

`fetchAndActivate` reports `activated`, `notModified`, `throttled`, or
`failed`. By default it waits up to eight seconds for AppsFlyer attribution,
which lets the backend return campaign-dependent overrides. A failed fetch
keeps the previously active configuration unchanged.

#### AppsFlyer Integration Example

PNLight does not depend on the AppsFlyer initialization order — it only needs the conversion data, delivered via `addAttribution`. Make sure the conversion ("attribution success") callback is not processed before PNLight is initialized: if it can fire earlier, store the conversion data in memory and call `addAttribution` once `initialize` completes.

AppsFlyer requires the ATT prompt to complete before it starts. If PNLight is initialized before ATT authorization, call `updateIdfa()` after the prompt completes so PNLight receives the granted IDFA.

```swift
import AppTrackingTransparency
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

        Task {
            await PNLightSDK.shared.initialize(apiKey: "your-api-key")

            // Request ATT, then pass the granted IDFA to PNLight.
            await ATTrackingManager.requestTrackingAuthorization()
            await PNLightSDK.shared.updateIdfa()

            // Start AppsFlyer after ATT completes (an AppsFlyer requirement).
            AppsFlyerLib.shared().start()
        }
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

If PNLight is initialized before the ATT prompt, send the IDFA once authorization is granted:

```swift
import PNLightSDK

await PNLightSDK.shared.updateIdfa()
```

### In-App Purchases

PNLight wraps StoreKit 2 for fetching products (price, offers, trial info),
purchasing, restoring, and checking entitlements. The product ids are configured
on the backend — `fetchProducts` resolves them against the App Store. The model
types (`PNLightProduct`, `PNLightSubscriptionOffer`, …) are re-exported, so only
`import PNLightSDK` is needed.

```swift
import PNLightSDK

// Load the configured products with their App Store price/offer info.
let products = try await PNLightSDK.shared.fetchProducts()
for product in products {
    print("\(product.displayName): \(product.displayPrice)")

    if let offer = product.subscription?.introductoryOffer,
       product.subscription?.isEligibleForIntroOffer == true {
        // e.g. pay-as-you-go: "$0.99/month for 6 months"
        print("Offer: \(offer.displayPrice) (\(offer.paymentMode), "
            + "\(offer.periodCount) × \(offer.period.value) \(offer.period.unit))")
    }
}

// Purchase.
let result = try await PNLightSDK.shared.purchase("your.product.id")
if result == .success {
    // Unlock content.
}

// Entitlement checks (local StoreKit entitlements, work offline).
let premium = await PNLightSDK.shared.isPremium()
let eligible = await PNLightSDK.shared.isEligibleForTrial(productId: "your.product.id")

// Restore previous purchases.
try await PNLightSDK.shared.restorePurchases()
```

---

## RemoteUiView - Server-driven UI

`RemoteUiView` fetches and renders a server-driven layout from PNLight for a given placement. It calls `getUIConfig(placement:)` internally, renders the native view, and emits action events to Swift.

When using external attribution providers such as AppsFlyer, send attribution as early as possible (see the AppsFlyer example above). `getUIConfig` waits for attribution data internally when `attributionRequired` is `true` (the default), so no manual delay is needed.

### SwiftUI

```swift
import PNLightSDK
import SwiftUI

struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RemoteUiView(
            placement: "paywall",
            cardId: "paywall_card"
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
    private let remoteView = PNLightRemoteUiView()

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
            let config = await PNLightSDK.shared.getUIConfig(placement: "paywall")
            remoteView.applyConfig(configJson: config?.config, cardId: "paywall_card")
        }
    }
}
```

### Remote UI schema version

PNLight versions the Remote UI envelope independently from the SDK package.
Add `"schemaVersion": 2` at the document root to opt into PNLight safe-area
handling, linear-scaling variables, server-driven flows, native haptics, and
native dialogs:

```json
{
  "schemaVersion": 2,
  "card": {}
}
```

A missing `schemaVersion` (or an explicit value of `1`) is legacy v1. This is
intentional: an existing backend config continues to use its previous
edge-to-edge DivKit behavior after an app upgrades PNLight. It does not receive
the v2 scaling variables or opt into PNLight-owned navigation, haptic, and
dialog action handling. New configs that use any feature below should declare
`"schemaVersion": 2`.

### Safe areas

PNLight keeps Remote UI content clear of the Dynamic Island, status bar, home
indicator, and landscape sensor housing without requiring host-app
configuration in schema v2. A v2 document with no `safe_area` field uses
`inset` mode on all four edges:

```json
{
  "schemaVersion": 2,
  "safe_area": {
    "mode": "inset",
    "edges": ["top", "bottom", "left", "right"]
  },
  "card": {}
}
```

| Mode | Behavior |
| --- | --- |
| `inset` | Default. PNLight places the complete DivKit document inside the selected safe-area edges. Use this for existing markup and screens without full-bleed backgrounds. |
| `content` | The document remains edge-to-edge and PNLight exposes the selected insets through DivKit system variables. Use this for full-bleed backgrounds. |
| `edge_to_edge` | The document remains edge-to-edge and safe-area variables resolve to zero. Use only when content may intentionally appear under system UI. |

In `content` mode, apply the variables to the root content container while its
background continues to fill the complete screen:

```json
{
  "schemaVersion": 2,
  "safe_area": {
    "mode": "content",
    "edges": ["top", "bottom"]
  },
  "card": {
    "log_id": "full_bleed_offer",
    "states": [
      {
        "state_id": 0,
        "div": {
          "type": "container",
          "width": { "type": "match_parent" },
          "height": { "type": "match_parent" },
          "paddings": {
            "top": "@{safe_area_top + 24}",
            "bottom": "@{safe_area_bottom + 24}",
            "left": 24,
            "right": 24
          },
          "items": []
        }
      }
    ]
  }
}
```

The available variables are `safe_area_top`, `safe_area_bottom`,
`safe_area_left`, and `safe_area_right`. PNLight updates them automatically
after rotation, window resizing, sheet presentation, and other UIKit safe-area
changes.

Flows accept `safe_area` beside `type`, `initial_route`, and `routes`. A route
may override the flow default by declaring its own `safe_area` beside
`divkit` and `presentation`:

```json
{
  "schemaVersion": 2,
  "type": "flow",
  "safe_area": { "mode": "inset" },
  "initial_route": "welcome",
  "routes": {
    "welcome": {
      "divkit": {}
    },
    "immersive_offer": {
      "safe_area": {
        "mode": "content",
        "edges": ["top", "bottom"]
      },
      "divkit": {}
    }
  }
}
```

### Linear scaling variables

Add an optional logical design viewport at the document root:

```json
{
  "schemaVersion": 2,
  "referenceSize": {
    "width": 390,
    "height": 844
  },
  "card": {}
}
```

PNLight exposes `scaleX` as the available logical viewport width divided by
`referenceSize.width`, and `scaleY` as the available height divided by
`referenceSize.height`. Use them in ordinary DivKit expressions:

```json
{
  "type": "container",
  "paddings": {
    "left": "@{24 * scaleX}",
    "right": "@{24 * scaleX}",
    "top": "@{20 * scaleY}"
  },
  "items": []
}
```

The ratios are raw and are not clamped. For the responsive-mobile-layout
policy, use `scaleX` as the uniform visual scale and apply the desired
`0.85...1.15` bounds in markup. Safe-area values remain system-provided and
must not be multiplied by either scale. If `referenceSize` is absent,
`scaleX` and `scaleY` are both `1` in schema v2.

The available viewport is measured after physical `inset` safe-area handling.
Values update after rotation, window resizing, and sheet-size changes. A flow
may declare one `referenceSize` beside `routes`; a route can override it beside
`divkit`. A `referenceSize` inside the route's complete `divkit` document is
also accepted.

### Server-driven native flows

`PNLightRemoteUiView` also accepts a PNLight flow envelope. The public API does
not change: the host still renders one view or one `RemoteUiView(placement:)`.
The initial route is embedded in that surface, while navigation declared by the
server is handled entirely inside the SPM renderer.

```json
{
  "schemaVersion": 2,
  "type": "flow",
  "initial_route": "welcome",
  "routes": {
    "welcome": {
      "divkit": {
        "templates": {},
        "card": {
          "log_id": "welcome",
          "states": [{
            "state_id": 0,
            "div": {
              "type": "custom",
              "custom_type": "pnlight.cta_button",
              "width": { "type": "match_parent" },
              "height": { "type": "fixed", "value": 56 },
              "custom_props": {
                "title": "Open offer",
                "url": "pnlight://navigation/present?route=offer"
              }
            }
          }]
        }
      }
    },
    "offer": {
      "presentation": {
        "style": "sheet",
        "detent": "large",
        "grabber": true,
        "dismissible": true,
        "corner_radius": 28
      },
      "divkit": {
        "templates": {},
        "card": {
          "log_id": "offer",
          "states": [{
            "state_id": 0,
            "div": {
              "type": "custom",
              "custom_type": "pnlight.cta_button",
              "width": { "type": "match_parent" },
              "height": { "type": "fixed", "value": 56 },
              "custom_props": {
                "title": "Dismiss",
                "url": "pnlight://navigation/dismiss"
              }
            }
          }]
        }
      }
    }
  }
}
```

Each route contains a complete DivKit document under `divkit`. Route IDs are
local to the flow, and `initial_route` must reference a declared route.

The renderer consumes these URLs before they reach `onAction`:

| URL | Native behavior |
| --- | --- |
| `pnlight://navigation/push?route=details` | Push the route on the active private `UINavigationController`. |
| `pnlight://navigation/pop` | Pop the active stack. |
| `pnlight://navigation/replace?route=details` | Replace the active route. |
| `pnlight://navigation/pop_to_root` | Pop the active stack to its first route. |
| `pnlight://navigation/present?route=offer` | Present the route over the whole app in a new native modal navigation context. |
| `pnlight://navigation/dismiss` | Dismiss the current PNLight modal context. |

A presented route can push more routes; those pushes stay inside that modal's
own stack. Dismissing it reveals the embedded stack with its existing view
controllers, DivKit variables, and scroll state intact.

All declared routes, including the initial route, are parsed and built through
DivKit's preloader when the flow is received. Pushes and presentations therefore
reuse a prepared native controller instead of showing a DivKit loader. PNLight
builds and lays out the prepared destination in `viewWillAppear` with zero
visible bounds, then publishes its real bounds in `viewDidAppear`. Navigation
therefore starts with an already-rendered destination while one-shot visibility
actions, timers started by visibility actions, and visibility transitions still
begin only when the route is actually visible. After a prepared route is
consumed, the SDK warms another instance for a later visit.

`presentation.style` accepts `sheet` (the default) or `full_screen`. Sheets
use the native page-sheet controller and give the presenting app a receding,
rounded background-layer transition. The background returns interactively when
the sheet is dismissed. Sheets support:

| Field | Default | Description |
| --- | --- | --- |
| `detent` | `large` | `large`, or `medium` with expansion to `large`. |
| `grabber` | `true` | Shows the native sheet grabber. |
| `dismissible` | `true` | When `false`, disables swipe-to-dismiss. |
| `corner_radius` | system | Preferred native sheet corner radius. |

The `present` URL may override those fields for one navigation edge, for
example:

```text
pnlight://navigation/present?route=offer&detent=medium&grabber=false
```

Unknown routes are ignored and logged by the SDK. Navigation URLs in legacy
single-card documents continue to surface through `onAction`; they are only
consumed while rendering a valid flow.

### Native alerts and action sheets

Declare `dialogs` at the document root (beside `card` for a single screen, or
beside `routes` for a flow), then open one from any DivKit action with
`pnlight://dialog/show?id=<dialog-id>`. PNLight presents a real
`UIAlertController`; the host app does not provide a presenter or callback.

```json
{
  "schemaVersion": 2,
  "dialogs": {
    "delete_confirmation": {
      "style": "alert",
      "title": "Delete item?",
      "message": "This cannot be undone.",
      "buttons": [
        {
          "title": "Cancel",
          "style": "cancel",
          "actions": []
        },
        {
          "title": "Delete",
          "style": "destructive",
          "actions": [
            {
              "log_id": "delete_haptic",
              "url": "pnlight://haptic/notification?type=warning"
            },
            {
              "log_id": "delete_confirmed",
              "url": "my-app://delete?id=42"
            }
          ]
        }
      ]
    }
  },
  "card": {}
}
```

`style` accepts `alert` or `action_sheet`. Button `style` accepts `default`,
`cancel`, or `destructive`, and a dialog may contain at most one cancel button.
Each button's `actions` is an ordered array of normal DivKit actions. PNLight
dispatches the complete actions through the current card's DivKit action
handler, so typed actions such as `set_variable`/`set_state`, PNLight
navigation and haptics, analytics, and custom URLs retain their normal
behavior. Empty arrays are valid for dismiss-only buttons.

### Native haptics

PNLight consumes `pnlight://haptic/...` actions before they reach `onAction`.
In schema v2, simple feedback works in both single-card documents and flow
routes:

| URL | Native behavior |
| --- | --- |
| `pnlight://haptic/impact?style=light` | UIKit impact feedback. `style` accepts `light`, `medium`, `heavy`, `soft`, or `rigid`; optional `intensity` is clamped to `0...1`. |
| `pnlight://haptic/selection` | UIKit selection feedback. |
| `pnlight://haptic/notification?type=success` | UIKit notification feedback. `type` accepts `success`, `warning`, or `error`. |

Flows may also declare named Core Haptics patterns at the top level:

```json
{
  "schemaVersion": 2,
  "type": "flow",
  "initial_route": "main",
  "haptics": {
    "ambient_pulse": {
      "events": [
        {
          "type": "continuous",
          "time": 0,
          "duration": 0.8,
          "intensity": 0.25,
          "sharpness": 0.35
        },
        {
          "type": "transient",
          "time": 0.4,
          "intensity": 0.65,
          "sharpness": 0.55
        }
      ],
      "loop": true,
      "max_duration": 120
    }
  },
  "routes": {
    "main": {
      "divkit": {
        "templates": {},
        "card": {
          "log_id": "main",
          "states": [
            {
              "state_id": 0,
              "div": {
                "type": "text",
                "text": "Haptic demo",
                "width": { "type": "match_parent" },
                "height": { "type": "wrap_content" }
              }
            }
          ]
        }
      }
    }
  }
}
```

Use `pnlight://haptic/start?pattern=ambient_pulse` to start a named pattern and
`pnlight://haptic/stop?pattern=ambient_pulse` to stop it. Calling `stop` without a
pattern stops every active player owned by the current route.

Patterns accept 1–128 transient or continuous events. Times and durations are
in seconds; `_ms` variants such as `time_ms`, `duration_ms`, and
`max_duration_ms` are also accepted. Intensity and sharpness are clamped to
`0...1`. A pattern may run for at most 600 seconds, and defaults to a
five-minute safety limit.

Core Haptics is a no-op on unsupported hardware. Active players stop when their
route leaves the window, the renderer receives a new configuration, the app
enters the background, or the renderer is destroyed.

### Lottie animations

PNLightSDK configures DivKit's standard `lottie` extension automatically. The
host app does not need to install Lottie separately, register a renderer, or
change its `RemoteUiView` integration.

Add the extension to a fixed-size DivKit element and provide either a remote
Lottie JSON URL:

```json
{
  "type": "container",
  "width": { "type": "fixed", "value": 200 },
  "height": { "type": "fixed", "value": 200 },
  "items": [],
  "extensions": [
    {
      "id": "lottie",
      "params": {
        "lottie_url": "https://cdn.example.com/animation.json",
        "repeat_count": 0,
        "repeat_mode": "restart",
        "is_playing": true
      }
    }
  ]
}
```

or embed the decoded Lottie document directly as `lottie_json`:

```json
{
  "id": "lottie",
  "params": {
    "lottie_json": {
      "v": "5.7.4",
      "fr": 60,
      "ip": 0,
      "op": 120,
      "w": 200,
      "h": 200,
      "assets": [],
      "layers": []
    }
  }
}
```

`repeat_mode` accepts `restart` (the default) or `reverse`. A
`repeat_count` of `0` repeats indefinitely. `is_playing` defaults to `true`.
Remote URLs are loaded by PNLightSDK's DivKit resource pipeline; use HTTPS in
production. This integration supports uncompressed Lottie JSON documents,
whether inline or downloaded. It does not decode `.lottie` ZIP archives.

### Native iOS circular loader

Use DivKit's custom element to render a native `UIActivityIndicatorView` inside Remote UI markup:

```json
{
  "type": "custom",
  "custom_type": "pnlight.circular_loader",
  "width": { "type": "fixed", "value": 48 },
  "height": { "type": "fixed", "value": 48 },
  "custom_props": {
    "style": "large",
    "color": "#FF007AFF",
    "accessibility_label": "Loading"
  }
}
```

`style` accepts `"medium"` (the default) or `"large"`. `color` accepts `#RRGGBB` or DivKit-style `#AARRGGBB` and defaults to the adaptive iOS label color. `accessibility_label` defaults to `"Loading"`. Standard DivKit `width` and `height` fields control the element's layout; set a dimension to `{ "type": "wrap_content" }` to use the native indicator's intrinsic size for that dimension.

### Native iOS animated prepend list

`pnlight.animated_prepend_list` is a persistent native UIKit list. Increasing
`count` by one fades and slides the newly revealed item into the beginning of
the list while the existing rows move down. It can be used for activity feeds,
progressive results, notifications, logs, or any other incrementally revealed
content. Row height is always calculated from its title and body; there is
intentionally no `row_height` or `line_height` prop.

```json
{
  "type": "custom",
  "custom_type": "pnlight.animated_prepend_list",
  "width": { "type": "match_parent" },
  "height": { "type": "match_parent" },
  "custom_props": {
    "instance_id": "activity_feed",
    "count": 0,
    "count_variable": "visible_item_count",
    "reduced_motion": "@{reduce_motion}",
    "status_text": "New",
    "animation_duration": 0.5,
    "slide_distance": 12,
    "fade": true,
    "slide": true,
    "items": [
      {
        "title": "New message",
        "body": "A teammate sent you an update",
        "icon_preview": "data:image/png;base64,..."
      },
      {
        "title": "File uploaded",
        "body": "The latest document is ready to review",
        "icon_preview": "data:image/png;base64,..."
      }
    ]
  }
}
```

`items` stays in discovery order: item `0` appears when `count` becomes `1`,
item `1` appears when it becomes `2`, and so on. The native view displays the
newest visible item first. A one-step increase is animated; resetting the count,
changing the item data/style, or jumping by several items is applied
immediately. Give every simultaneously rendered list a stable, unique
`instance_id`; that identity lets the native view keep its animation state
across DivKit variable updates.

Use `count_variable` for a variable-driven list so the same JSON is reactive in
both the native and web renderers. Other props support DivKit expressions.
Colors accept `#RRGGBB` or DivKit-style `#AARRGGBB`.

| Prop | Default | Description |
| --- | --- | --- |
| `instance_id` | fallback shared ID | Stable identity for retaining list state; set this explicitly. |
| `count` | `0` | Number of discovered items to display, clamped to `0...items.count`. |
| `count_variable` | `""` | Optional DivKit variable name that drives `count` reactively across native and web renderers. |
| `items` | required | Discovery-ordered array of `title`, `body`, and Base64 `icon_preview` values. |
| `reduced_motion` | `false` | Applies count changes immediately without fade or movement. |
| `status_text` | `""` | Optional trailing text shown on every row. |
| `card_background_color` | `#FFFEFEFE` | Row fill. |
| `title_color` | `#FF1C1C1E` | Title color. |
| `body_color` | `#FF3A3A3C` | Body color. |
| `status_color` | iOS `systemRed` | Status color. |
| `corner_radius` | `20` | Continuous row corner radius in points. |
| `title_font_size` | `14` | Title point size. |
| `title_font_weight` | `bold` | `ultralight`/`thin`/`light`/`regular`/`medium`/`semibold`/`bold`/`heavy`/`black`. |
| `body_font_size` | `12` | Body point size. |
| `body_font_weight` | `light` | Same weight values as the title. |
| `status_font_size` | `12` | Status point size. |
| `status_font_weight` | `semibold` | Same weight values as the title. |
| `list_horizontal_padding` | `4` | Inset between the list bounds and each row. |
| `row_spacing` | `15` | Vertical gap between rows. |
| `bottom_padding` | `20` | Scrollable space after the last row. |
| `row_horizontal_padding` | `16` | Leading and trailing content inset inside a row. |
| `row_vertical_padding` | `16` | Top and bottom content inset; content still determines final height. |
| `icon_size` | `20` | Square icon size. |
| `icon_text_spacing` | `13` | Gap from the icon to the text column. |
| `text_status_spacing` | `13` | Minimum gap from text to the status. |
| `animation_duration` | `0.36` | Fade/slide duration in seconds. |
| `slide_distance` | `8` | New row's upward starting offset in points. |
| `fade` | `true` | Enables the new-row opacity transition. |
| `slide` | `true` | Enables the new-row movement transition. |
| `shows_scroll_indicator` | `false` | Shows the native vertical scroll indicator. |

The outer list size is still controlled by the standard DivKit `width` and
`height` fields. Only the rows use intrinsic content sizing. The component is
implemented by PNLightSDK on iOS and by `@pnlight/sdk-react` on the web. A host
using DivKit directly, without either PNLight wrapper, must register the same
`custom_type` itself.

### Native iOS CTA button

Render a native, animated call-to-action button with a repeating shimmer streak,
an idle attention pulse, and a spring press bounce. Taps are routed through the
same action pipeline as DivKit buttons, so `onAction` fires with the payload
decoded from `url`.

```json
{
  "type": "custom",
  "custom_type": "pnlight.cta_button",
  "width": { "type": "match_parent" },
  "height": { "type": "fixed", "value": 58 },
  "custom_props": {
    "title": "Continue",
    "background_color": "#FF007AFF",
    "title_color": "#FFFFFFFF",
    "corner_radius": 16,
    "font_size": 19,
    "font_weight": "bold",
    "shimmer": true,
    "bounce": true,
    "url": "pnlight://cta?id=continue"
  }
}
```

All props are optional; only `title` and `url` are usually needed. Colors accept
`#RRGGBB` or DivKit-style `#AARRGGBB`.

| Prop | Default | Description |
| --- | --- | --- |
| `title` | `""` | Button label. |
| `background_color` | `#FF007AFF` | Fill color (also the gradient start). |
| `background_color_end` | — | When set, the fill is a horizontal gradient to this color. |
| `glass` | off (on for icon buttons) | Native Liquid Glass fill on iOS 26+. See below. |
| `title_color` | `#FFFFFFFF` | Label color. |
| `corner_radius` | `14` | Corner radius in points (continuous curve). |
| `font_size` | `18` | Label point size. |
| `font_weight` | `semibold` | `regular`/`medium`/`semibold`/`bold`/`heavy`/`black`. |
| `horizontal_padding` / `vertical_padding` | `24` / `16` | Used to size the button when `width`/`height` is `wrap_content`. |
| `icon` | — | SF Symbol name, e.g. `"shield.lefthalf.filled"`. Renders before the title. |
| `icon_size` | `20` | Symbol point size. |
| `icon_weight` | `semibold` | `ultralight` … `black`. |
| `icon_color` | `title_color` | Symbol tint. |
| `icon_spacing` | `8` | Gap between icon and title. |
| `loading` | `false` | Swaps the title for a native spinner and ignores taps. |
| `disabled` | `false` | Dims the button and ignores taps. |
| `disabled_alpha` | `0.45` | Opacity used while `disabled`. |
| `disabled_background_color` | — | Replaces the fill (and any gradient) while `disabled`. |
| `disabled_title_color` | — | Replaces the label color while `disabled`. |
| `loading_indicator_color` | `title_color` | Spinner color. |
| `loading_indicator_style` | `medium` | `medium` or `large`. |
| `url` | — | Action fired on tap (custom scheme → `onAction`; http(s) → opened). |
| `log_id` | — | Emitted as the action's `logId` when there is no `url`. |
| `accessibility_label` | `title` | VoiceOver label (defaults to `"Loading"` while `loading`). |

Both `loading` and `disabled` make the button inert: taps are ignored and the
shimmer and bounce animations stop, so an in-flight CTA sits still.

`shimmer` and `bounce` accept a boolean shorthand (`true`/`false` to toggle) or a
props object for fine control:

```json
{
  "shimmer": {
    "enabled": true,
    "color": "#80FFFFFF",
    "duration": 1.4,
    "pause": 1.1,
    "band_width": 0.3,
    "angle": 16
  },
  "bounce": {
    "idle":  { "enabled": true, "scale": 1.03, "period": 2.6 },
    "press": { "enabled": true, "scale": 0.96 }
  }
}
```

`{ "bounce": true }` enables both the idle pulse and the press bounce;
`{ "bounce": { "idle": false, "press": true } }` keeps only the press feedback.

#### Liquid Glass (iOS 26+)

Buttons can render with the native Liquid Glass material. **Icon buttons opt in
automatically** — if the markup doesn't pick a `background_color`, the button
uses glass on iOS 26+ and the flat `secondarySystemFill` below it. Nothing in the
markup has to branch on OS version.

An explicit `background_color` turns that off, on the assumption that markup
naming a color wants that exact button. To get both, ask for glass and the color
becomes the material's tint:

```json
{
  "glass": {
    "enabled": true,
    "style": "regular",
    "tint": "#99FF375F",
    "prominent": true
  }
}
```

`{ "glass": true }` is the shorthand, and is how a `pnlight.cta_button` opts in.
`prominent` selects the filled primary-action treatment.
Two defaults shift when glass is on, because the material is light and busy:
`title_color` falls back to the adaptive `label` color instead of white, and
`shimmer` turns off (a travelling highlight over glass reads as a rendering
glitch). Set either prop explicitly to override.

Glass only earns its look over content — a photo, a gradient, a scrolling list.
Over a flat background it degrades to a plain translucent fill.

The material falls back to the solid `background_color` when it can't be drawn:
on iOS 25 and earlier, when **Reduce Transparency** is on, and while
`disabled_background_color` applies.

#### Driving `loading` / `disabled` at runtime

Any prop accepts a DivKit expression, so a state can be bound to a card
variable and flipped while the card is on screen:

```json
{
  "card": {
    "variables": [{ "type": "boolean", "name": "is_busy", "value": false }],
    "states": [{ "state_id": 0, "div": {
      "type": "custom",
      "custom_type": "pnlight.cta_button",
      "custom_props": {
        "title": "Submit",
        "loading": "@{is_busy}",
        "url": "pnlight://cta?id=submit"
      }
    }}]
  }
}
```

Toggle it from markup with a standard `set_variable` action:

```json
{
  "actions": [{
    "log_id": "begin",
    "typed": {
      "type": "set_variable",
      "variable_name": "is_busy",
      "value": { "type": "boolean", "value": true }
    }
  }]
}
```

Handle the tap in `onAction` just like any other action:

```swift
RemoteUiView(placement: "paywall", cardId: "paywall_card") { action in
    if action.params["id"] == "continue" {
        // continue the flow
    }
}
```

Native CTA and icon buttons also support the standard DivKit `actions` array.
Actions execute in declaration order through DivKit's normal action handler,
including typed variable/state actions, PNLight haptics, dialogs, navigation,
analytics, and custom URLs. A non-empty `actions` array takes precedence over
the `custom_props.url` / `log_id` single-action shorthand.

### Native iOS icon button

`pnlight.icon_button` is the same native button tuned for a small circular
control with an SF Symbol — ideal for close, settings, or favorite affordances.

```json
{
  "type": "custom",
  "custom_type": "pnlight.icon_button",
  "width": { "type": "fixed", "value": 44 },
  "height": { "type": "fixed", "value": 44 },
  "custom_props": {
    "icon": "xmark",
    "accessibility_label": "Close",
    "url": "pnlight://cta?id=close"
  }
}
```

It accepts every `pnlight.cta_button` prop above (including `loading`,
`disabled`, `shimmer`, `bounce`, and expression binding) — only the defaults
differ:

| Prop | CTA default | Icon default |
| --- | --- | --- |
| shape | `corner_radius: 14` | fully circular |
| `background_color` | `#FF007AFF` | `secondarySystemFill` (adaptive) |
| `glass` | off | **on** when no `background_color` is set |
| icon/title color | white | `label` (adaptive) |
| `horizontal_padding` / `vertical_padding` | `24` / `16` | `12` / `12` |
| `shimmer` | on | off |
| `bounce.idle` | on | off |
| `bounce.press` | on | on |

Setting `corner_radius` opts out of the circular shape, giving a rounded square.
With `wrap_content` on both axes the button sizes itself from the symbol plus
padding and stays square.

**Accessibility:** an icon-only button has no title, so set
`accessibility_label`. It falls back to the SF Symbol name, which is rarely what
you want VoiceOver to read. An unknown symbol name is reported in the card's
DivKit errors rather than silently rendering an empty button.

### Manual Config Fetching

Use `getUIConfig` if you need to fetch the placement configuration yourself. When `attributionRequired` is `true` (the default), the SDK waits for attribution data internally before returning:

```swift
import PNLightSDK

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
| `fetchAndActivate(minimumFetchInterval:waitAttribution:) async` | Fetch Remote Config; waits for attribution by default |
| `remoteConfigBoolean/String/Number/StringArray/JSONObject` | Read a typed Remote Config value with a fallback |
| `getUserId() -> String` | Get or create a stable user identifier |
| `getIdfa() -> String?` | Return IDFA if ATT is already authorized, otherwise `nil` |
| `updateIdfa() async -> Bool` | Send the current IDFA to PNLight after the ATT prompt completes |
| `prefetchUIConfig(placement:)` | Prefetch a UI config into the in-memory cache |
| `getUIConfig(placement:attributionRequired:) async -> UIConfig?` | Fetch a UI config; waits for attribution by default |
| `clearUIConfigCache()` | Clear the in-memory UI config cache |
| `fetchProducts() async throws -> [PNLightProduct]` | Load configured products with App Store price/offer/trial info |
| `purchase(_:) async throws -> PNLightPurchaseResult` | Purchase a product |
| `restorePurchases() async throws` | Restore previous purchases by syncing with the App Store |
| `isPremium() async -> Bool` | Whether the user has an active entitlement to any configured product |
| `isPurchased(_:) async -> Bool` | Whether the user has an active entitlement to a specific product |
| `isEligibleForTrial(productId:) async -> Bool` | Whether the user is eligible for a product's introductory offer |
| `getAppleReceipt() async -> String?` | Base64 App Store receipt for server-side validation, or `nil` if absent |

### `RemoteUiView` (SwiftUI, iOS 14+)

| Parameter | Type | Description |
| --- | --- | --- |
| `placement` | `String` | PNLight placement identifier |
| `cardId` | `String` | Card identifier |
| `secure` | `Bool` | Deprecated. Secure rendering is controlled by the backend response. |
| `preventRecording` | `Bool` | Deprecated. Capture blocking is controlled by the backend. |
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
