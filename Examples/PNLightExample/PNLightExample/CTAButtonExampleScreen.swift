import SwiftUI
import PNLightSDK

struct CTAButtonExampleScreen: View {
    @State private var lastAction: String?

    var body: some View {
        VStack(spacing: 0) {
            CTAButtonMarkupView { action in
                lastAction = action.params["id"] ?? action.logId
            }

            Divider()

            HStack {
                Text("Last tap")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(lastAction ?? "—")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(lastAction == nil ? .secondary : .primary)
            }
            .padding()
        }
        .navigationTitle("Native CTA Button")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct CTAButtonMarkupView: UIViewRepresentable {
    let onAction: (RemoteUiAction) -> Void

    func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.onAction = onAction
        view.applyConfig(configJson: Self.markup, cardId: "native_cta_button_example")
        return view
    }

    func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {
        uiView.onAction = onAction
    }

    // Each button is a native `pnlight.cta_button` custom element. The first
    // mirrors the reference CTA (blue fill, shimmer + bounce); the rest show the
    // animation props, the `loading` / `disabled` states, and how a state can be
    // bound to a card variable so it flips at runtime.
    private static let markup = #"""
    {
      "card": {
        "log_id": "native_cta_button_example",
        "variables": [
          { "type": "boolean", "name": "is_busy", "value": false }
        ],
        "states": [
          {
            "state_id": 0,
            "div": {
              "type": "gallery",
              "orientation": "vertical",
              "width": { "type": "match_parent" },
              "height": { "type": "match_parent" },
              "paddings": { "left": 20, "right": 20, "top": 8, "bottom": 32 },
              "items": [
                {
                  "type": "cta_label",
                  "text": "Shimmer + bounce (both)"
                },
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
                },
                {
                  "type": "cta_label",
                  "text": "Gradient fill, faster shimmer"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.cta_button",
                  "width": { "type": "match_parent" },
                  "height": { "type": "fixed", "value": 58 },
                  "custom_props": {
                    "title": "Upgrade to Premium",
                    "background_color": "#FF5E5CE6",
                    "background_color_end": "#FFBF5AF2",
                    "title_color": "#FFFFFFFF",
                    "corner_radius": 16,
                    "font_size": 19,
                    "font_weight": "bold",
                    "shimmer": {
                      "color": "#80FFFFFF",
                      "duration": 1.0,
                      "pause": 0.6,
                      "band_width": 0.35,
                      "angle": 22
                    },
                    "bounce": { "idle": { "scale": 1.05, "period": 2.0 }, "press": true },
                    "url": "pnlight://cta?id=upgrade"
                  }
                },
                {
                  "type": "cta_label",
                  "text": "Press bounce only (no shimmer, no idle)"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.cta_button",
                  "width": { "type": "match_parent" },
                  "height": { "type": "fixed", "value": 54 },
                  "custom_props": {
                    "title": "Continue",
                    "background_color": "#FF34C759",
                    "corner_radius": 14,
                    "font_size": 18,
                    "shimmer": false,
                    "bounce": { "idle": false, "press": true },
                    "url": "pnlight://cta?id=continue"
                  }
                },
                {
                  "type": "cta_label",
                  "text": "Icon buttons — circular, native SF Symbols. The ones without a background_color are Liquid Glass on iOS 26+."
                },
                {
                  "type": "container",
                  "orientation": "horizontal",
                  "width": { "type": "match_parent" },
                  "height": { "type": "wrap_content" },
                  "items": [
                    {
                      "type": "custom",
                      "custom_type": "pnlight.icon_button",
                      "width": { "type": "fixed", "value": 44 },
                      "height": { "type": "fixed", "value": 44 },
                      "margins": { "right": 12 },
                      "custom_props": {
                        "icon": "xmark",
                        "accessibility_label": "Close",
                        "url": "pnlight://cta?id=close"
                      }
                    },
                    {
                      "type": "custom",
                      "custom_type": "pnlight.icon_button",
                      "width": { "type": "fixed", "value": 44 },
                      "height": { "type": "fixed", "value": 44 },
                      "margins": { "right": 12 },
                      "custom_props": {
                        "icon": "heart.fill",
                        "icon_color": "#FFFFFFFF",
                        "background_color": "#FFFF3B30",
                        "accessibility_label": "Favorite",
                        "url": "pnlight://cta?id=favorite"
                      }
                    },
                    {
                      "type": "custom",
                      "custom_type": "pnlight.icon_button",
                      "width": { "type": "wrap_content" },
                      "height": { "type": "wrap_content" },
                      "margins": { "right": 12 },
                      "custom_props": {
                        "icon": "gearshape.fill",
                        "icon_size": 22,
                        "icon_color": "#FFFFFFFF",
                        "background_color": "#FF007AFF",
                        "accessibility_label": "Settings",
                        "url": "pnlight://cta?id=settings"
                      }
                    },
                    {
                      "type": "custom",
                      "custom_type": "pnlight.icon_button",
                      "width": { "type": "fixed", "value": 44 },
                      "height": { "type": "fixed", "value": 44 },
                      "margins": { "right": 12 },
                      "custom_props": {
                        "icon": "arrow.clockwise",
                        "loading": true,
                        "accessibility_label": "Refreshing"
                      }
                    },
                    {
                      "type": "custom",
                      "custom_type": "pnlight.icon_button",
                      "width": { "type": "fixed", "value": 44 },
                      "height": { "type": "fixed", "value": 44 },
                      "custom_props": {
                        "icon": "bolt.fill",
                        "disabled": true,
                        "accessibility_label": "Boost unavailable"
                      }
                    }
                  ]
                },
                {
                  "type": "cta_label",
                  "text": "Icon + title, squared off (corner_radius opts out of circular)"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.cta_button",
                  "width": { "type": "match_parent" },
                  "height": { "type": "fixed", "value": 54 },
                  "custom_props": {
                    "title": "Open details",
                    "icon": "info.circle.fill",
                    "icon_size": 20,
                    "background_color": "#FF1C1C1E",
                    "corner_radius": 14,
                    "font_size": 18,
                    "shimmer": false,
                    "url": "pnlight://cta?id=open_details"
                  }
                },
                {
                  "type": "cta_label",
                  "text": "Liquid Glass over content — where the material actually shows"
                },
                {
                  "type": "container",
                  "orientation": "vertical",
                  "width": { "type": "match_parent" },
                  "height": { "type": "wrap_content" },
                  "paddings": { "left": 16, "right": 16, "top": 18, "bottom": 18 },
                  "border": { "corner_radius": 20 },
                  "background": [
                    {
                      "type": "gradient",
                      "angle": 135,
                      "colors": ["#FF0A84FF", "#FFBF5AF2", "#FFFF9F0A"]
                    }
                  ],
                  "items": [
                    {
                      "type": "container",
                      "orientation": "horizontal",
                          "width": { "type": "match_parent" },
                      "height": { "type": "wrap_content" },
                      "items": [
                        {
                          "type": "custom",
                          "custom_type": "pnlight.icon_button",
                          "width": { "type": "fixed", "value": 48 },
                          "height": { "type": "fixed", "value": 48 },
                          "margins": { "right": 12 },
                          "custom_props": {
                            "icon": "chevron.left",
                            "accessibility_label": "Back",
                            "url": "pnlight://cta?id=glass_back"
                          }
                        },
                        {
                          "type": "custom",
                          "custom_type": "pnlight.icon_button",
                          "width": { "type": "fixed", "value": 48 },
                          "height": { "type": "fixed", "value": 48 },
                          "margins": { "right": 12 },
                          "custom_props": {
                            "icon": "square.and.arrow.up",
                            "glass": { "style": "clear" },
                            "icon_color": "#FFFFFFFF",
                            "accessibility_label": "Share",
                            "url": "pnlight://cta?id=glass_share"
                          }
                        },
                        {
                          "type": "custom",
                          "custom_type": "pnlight.icon_button",
                          "width": { "type": "fixed", "value": 48 },
                          "height": { "type": "fixed", "value": 48 },
                          "margins": { "right": 12 },
                          "custom_props": {
                            "icon": "heart.fill",
                            "glass": { "tint": "#99FF375F" },
                            "icon_color": "#FFFFFFFF",
                            "accessibility_label": "Favorite",
                            "url": "pnlight://cta?id=glass_favorite"
                          }
                        },
                        {
                          "type": "custom",
                          "custom_type": "pnlight.icon_button",
                          "width": { "type": "fixed", "value": 48 },
                          "height": { "type": "fixed", "value": 48 },
                          "custom_props": {
                            "icon": "ellipsis",
                            "loading": "@{is_busy}",
                            "accessibility_label": "More"
                          }
                        }
                      ]
                    },
                    {
                      "type": "custom",
                      "custom_type": "pnlight.cta_button",
                      "width": { "type": "match_parent" },
                      "height": { "type": "fixed", "value": 54 },
                      "margins": { "top": 16 },
                      "custom_props": {
                        "title": "Glass CTA",
                        "icon": "sparkles",
                        "glass": true,
                        "corner_radius": 16,
                        "font_size": 18,
                        "url": "pnlight://cta?id=glass_cta"
                      }
                    },
                    {
                      "type": "custom",
                      "custom_type": "pnlight.cta_button",
                      "width": { "type": "match_parent" },
                      "height": { "type": "fixed", "value": 54 },
                      "margins": { "top": 12 },
                      "custom_props": {
                        "title": "Prominent glass",
                        "glass": { "prominent": true, "tint": "#FF0A84FF" },
                        "title_color": "#FFFFFFFF",
                        "corner_radius": 16,
                        "font_size": 18,
                        "url": "pnlight://cta?id=glass_prominent"
                      }
                    }
                  ]
                },
                {
                  "type": "cta_label",
                  "text": "loading — spinner replaces the title, taps ignored"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.cta_button",
                  "width": { "type": "match_parent" },
                  "height": { "type": "fixed", "value": 54 },
                  "custom_props": {
                    "title": "Processing",
                    "background_color": "#FF007AFF",
                    "corner_radius": 14,
                    "font_size": 18,
                    "loading": true,
                    "url": "pnlight://cta?id=never_fires"
                  }
                },
                {
                  "type": "cta_label",
                  "text": "disabled — dimmed, taps ignored"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.cta_button",
                  "width": { "type": "match_parent" },
                  "height": { "type": "fixed", "value": 54 },
                  "custom_props": {
                    "title": "Unavailable",
                    "background_color": "#FF007AFF",
                    "corner_radius": 14,
                    "font_size": 18,
                    "disabled": true,
                    "url": "pnlight://cta?id=never_fires"
                  }
                },
                {
                  "type": "cta_label",
                  "text": "Bound to a card variable — tap the row to toggle"
                },
                {
                  "type": "text",
                  "text": "Toggle is_busy (now: @{is_busy})",
                  "font_size": 15,
                  "font_weight": "medium",
                  "text_alignment_horizontal": "center",
                  "text_color": "#FF007AFF",
                  "width": { "type": "match_parent" },
                  "height": { "type": "fixed", "value": 44 },
                  "paddings": { "top": 12 },
                  "border": { "corner_radius": 12 },
                  "background": [{ "type": "solid", "color": "#FFE5E5EA" }],
                  "actions": [
                    {
                      "log_id": "toggle_is_busy",
                      "typed": {
                        "type": "set_variable",
                        "variable_name": "is_busy",
                        "value": { "type": "boolean", "value": "@{!is_busy}" }
                      }
                    }
                  ]
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.cta_button",
                  "width": { "type": "match_parent" },
                  "height": { "type": "fixed", "value": 54 },
                  "margins": { "top": 8 },
                  "custom_props": {
                    "title": "Submit",
                    "background_color": "#FFFF9500",
                    "corner_radius": 14,
                    "font_size": 18,
                    "loading": "@{is_busy}",
                    "url": "pnlight://cta?id=submit"
                  }
                }
              ]
            }
          }
        ]
      },
      "templates": {
        "cta_label": {
          "type": "text",
          "font_size": 13,
          "font_weight": "medium",
          "text_color": "#8E8E93",
          "width": { "type": "match_parent" },
          "height": { "type": "wrap_content" },
          "margins": { "top": 22, "bottom": 8 }
        }
      }
    }
    """#
}

#Preview {
    NavigationStack {
        CTAButtonExampleScreen()
    }
}
