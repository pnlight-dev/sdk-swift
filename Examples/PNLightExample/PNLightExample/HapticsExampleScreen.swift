import SwiftUI
import PNLightSDK

struct HapticsExampleScreen: View {
    var body: some View {
        HapticsMarkupView()
            .navigationTitle("Remote UI Haptics")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct HapticsMarkupView: UIViewRepresentable {
    func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.applyConfig(configJson: Self.markup, cardId: "native_haptics_example")
        return view
    }

    func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {}

    private static let markup = #"""
    {
      "schemaVersion": 2,
      "type": "flow",
      "initial_route": "haptics",
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
        "haptics": {
          "divkit": {
            "templates": {
              "button": {
                "type": "custom",
                "custom_type": "pnlight.cta_button",
                "width": { "type": "match_parent" },
                "height": { "type": "fixed", "value": 52 },
                "custom_props": {
                  "background_color": "#FF087EF5",
                  "title_color": "#FFFFFFFF",
                  "corner_radius": 14,
                  "font_size": 17,
                  "font_weight": "bold",
                  "shimmer": false,
                  "bounce": { "idle": false, "press": true },
                  "$title": "title",
                  "$url": "url"
                }
              }
            },
            "card": {
              "log_id": "native_haptics",
              "states": [
                {
                  "state_id": 0,
                  "div": {
                    "type": "gallery",
                    "orientation": "vertical",
                    "width": { "type": "match_parent" },
                    "height": { "type": "match_parent" },
                    "paddings": {
                      "left": 20,
                      "right": 20,
                      "top": 20,
                      "bottom": 32
                    },
                    "item_spacing": 12,
                    "items": [
                      {
                        "type": "text",
                        "text": "Simple UIKit feedback",
                        "font_size": 23,
                        "font_weight": "bold",
                        "text_color": "#FF111827",
                        "width": { "type": "match_parent" },
                        "height": { "type": "wrap_content" }
                      },
                      {
                        "type": "button",
                        "title": "Light impact",
                        "url": "pnlight://haptic/impact?style=light"
                      },
                      {
                        "type": "button",
                        "title": "Rigid impact",
                        "url": "pnlight://haptic/impact?style=rigid&intensity=0.8"
                      },
                      {
                        "type": "button",
                        "title": "Selection",
                        "url": "pnlight://haptic/selection"
                      },
                      {
                        "type": "button",
                        "title": "Success notification",
                        "url": "pnlight://haptic/notification?type=success"
                      },
                      {
                        "type": "text",
                        "text": "Looping Core Haptics pattern",
                        "font_size": 23,
                        "font_weight": "bold",
                        "text_color": "#FF111827",
                        "width": { "type": "match_parent" },
                        "height": { "type": "wrap_content" },
                        "margins": { "top": 12 }
                      },
                      {
                        "type": "button",
                        "title": "Start ambient pattern",
                        "url": "pnlight://haptic/start?pattern=ambient_pulse"
                      },
                      {
                        "type": "button",
                        "title": "Stop ambient pattern",
                        "url": "pnlight://haptic/stop?pattern=ambient_pulse"
                      },
                      {
                        "type": "text",
                        "text": "Core Haptics requires a physical supported iPhone. Active patterns stop when this screen disappears or the app enters the background.",
                        "font_size": 14,
                        "line_height": 19,
                        "text_color": "#FF6B7280",
                        "width": { "type": "match_parent" },
                        "height": { "type": "wrap_content" },
                        "margins": { "top": 4 }
                      }
                    ]
                  }
                }
              ]
            }
          }
        }
      }
    }
    """#
}
