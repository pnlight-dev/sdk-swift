import SwiftUI
import PNLightSDK

struct FlowNavigationExampleScreen: View {
    var body: some View {
        FlowNavigationMarkupView()
            .navigationTitle("Native Remote UI Flow")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct FlowNavigationMarkupView: UIViewRepresentable {
    func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.applyConfig(
            configJson: Self.markup,
            cardId: "native_flow_navigation_example"
        )
        return view
    }

    func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {}

    private static let markup = #"""
    {
      "schemaVersion": 2,
      "type": "flow",
      "referenceSize": {
        "width": 390,
        "height": 844
      },
      "safe_area": {
        "mode": "content",
        "edges": ["top", "bottom"]
      },
      "initial_route": "welcome",
      "dialogs": {
        "continue_alert": {
          "style": "alert",
          "title": "Continue to details?",
          "message": "The selected button runs an ordered array of ordinary DivKit actions.",
          "buttons": [
            {
              "title": "Cancel",
              "style": "cancel",
              "actions": []
            },
            {
              "title": "Continue",
              "actions": [
                {
                  "log_id": "alert_success_haptic",
                  "url": "pnlight://haptic/notification?type=success"
                },
                {
                  "log_id": "alert_push_details",
                  "url": "pnlight://navigation/push?route=details"
                }
              ]
            }
          ]
        },
        "quick_actions": {
          "style": "action_sheet",
          "title": "Quick actions",
          "buttons": [
            {
              "title": "Open offer sheet",
              "actions": [
                {
                  "log_id": "action_sheet_present_offer",
                  "url": "pnlight://navigation/present?route=offer"
                }
              ]
            },
            {
              "title": "Cancel",
              "style": "cancel",
              "actions": []
            }
          ]
        }
      },
      "routes": {
        "welcome": {
          "divkit": {
            "templates": {
              "title": {
                "type": "text",
                "font_size": 30,
                "font_weight": "bold",
                "text_color": "#FF111827",
                "width": { "type": "match_parent" },
                "height": { "type": "wrap_content" }
              },
              "body": {
                "type": "text",
                "font_size": 16,
                "line_height": 22,
                "text_color": "#FF6B7280",
                "width": { "type": "match_parent" },
                "height": { "type": "wrap_content" }
              }
            },
            "card": {
              "log_id": "flow_welcome",
              "states": [
                {
                  "state_id": 0,
                  "div": {
                    "type": "container",
                    "orientation": "vertical",
                    "width": { "type": "match_parent" },
                    "height": { "type": "match_parent" },
                    "paddings": {
                      "left": "@{24 * scaleX}",
                      "right": "@{24 * scaleX}",
                      "top": "@{safe_area_top + 32 * scaleY}",
                      "bottom": "@{safe_area_bottom + 32 * scaleY}"
                    },
                    "background": [
                      { "type": "solid", "color": "#FFF7F8FC" }
                    ],
                    "items": [
                      {
                        "type": "title",
                        "text": "One RemoteUiView.\nMultiple native screens."
                      },
                      {
                        "type": "body",
                        "text": "scaleX @{scaleX}, scaleY @{scaleY}. The buttons below open native dialogs or navigate the private stack.",
                        "margins": { "top": 12, "bottom": 28 }
                      },
                      {
                        "type": "custom",
                        "custom_type": "pnlight.cta_button",
                        "width": { "type": "match_parent" },
                        "height": { "type": "fixed", "value": 56 },
                        "custom_props": {
                          "title": "Show native alert",
                          "background_color": "#FF087EF5",
                          "corner_radius": 16,
                          "shimmer": false,
                          "bounce": { "idle": false, "press": true },
                          "url": "pnlight://dialog/show?id=continue_alert"
                        }
                      },
                      {
                        "type": "custom",
                        "custom_type": "pnlight.cta_button",
                        "width": { "type": "match_parent" },
                        "height": { "type": "fixed", "value": 56 },
                        "margins": { "top": 14 },
                        "custom_props": {
                          "title": "Show native action sheet",
                          "background_color": "#FF6750A4",
                          "corner_radius": 16,
                          "shimmer": false,
                          "bounce": { "idle": false, "press": true },
                          "url": "pnlight://dialog/show?id=quick_actions"
                        }
                      },
                      {
                        "type": "custom",
                        "custom_type": "pnlight.cta_button",
                        "width": { "type": "match_parent" },
                        "height": { "type": "fixed", "value": 56 },
                        "margins": { "top": 14 },
                        "custom_props": {
                          "title": "Push details directly",
                          "background_color": "#FF087EF5",
                          "corner_radius": 16,
                          "shimmer": false,
                          "bounce": { "idle": false, "press": true },
                          "url": "pnlight://navigation/push?route=details"
                        }
                      }
                    ]
                  }
                }
              ]
            }
          }
        },
        "details": {
          "divkit": {
            "templates": {
              "title": {
                "type": "text",
                "font_size": 30,
                "font_weight": "bold",
                "text_color": "#FF111827",
                "width": { "type": "match_parent" },
                "height": { "type": "wrap_content" }
              },
              "body": {
                "type": "text",
                "font_size": 16,
                "line_height": 22,
                "text_color": "#FF6B7280",
                "width": { "type": "match_parent" },
                "height": { "type": "wrap_content" }
              }
            },
            "card": {
              "log_id": "flow_details",
              "states": [
                {
                  "state_id": 0,
                  "div": {
                    "type": "container",
                    "orientation": "vertical",
                    "width": { "type": "match_parent" },
                    "height": { "type": "match_parent" },
                    "paddings": {
                      "left": 24,
                      "right": 24,
                      "top": "@{safe_area_top + 32}",
                      "bottom": "@{safe_area_bottom + 32}"
                    },
                    "background": [
                      { "type": "solid", "color": "#FFF0F7FF" }
                    ],
                    "items": [
                      {
                        "type": "title",
                        "text": "Details"
                      },
                      {
                        "type": "body",
                        "text": "This is a separate DivKit document hosted by a real child UIViewController in PNLight's private UINavigationController.",
                        "margins": { "top": 12, "bottom": 28 }
                      },
                      {
                        "type": "custom",
                        "custom_type": "pnlight.cta_button",
                        "width": { "type": "match_parent" },
                        "height": { "type": "fixed", "value": 54 },
                        "custom_props": {
                          "title": "Pop to welcome",
                          "background_color": "#FF087EF5",
                          "corner_radius": 16,
                          "shimmer": false,
                          "bounce": { "idle": false, "press": true },
                          "url": "pnlight://navigation/pop"
                        }
                      },
                      {
                        "type": "custom",
                        "custom_type": "pnlight.cta_button",
                        "width": { "type": "match_parent" },
                        "height": { "type": "fixed", "value": 54 },
                        "margins": { "top": 14 },
                        "custom_props": {
                          "title": "Present sheet from here",
                          "background_color": "#FF6750A4",
                          "corner_radius": 16,
                          "shimmer": false,
                          "bounce": { "idle": false, "press": true },
                          "url": "pnlight://navigation/present?route=offer"
                        }
                      }
                    ]
                  }
                }
              ]
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
            "templates": {
              "title": {
                "type": "text",
                "font_size": 30,
                "font_weight": "bold",
                "text_color": "#FFFFFFFF",
                "width": { "type": "match_parent" },
                "height": { "type": "wrap_content" }
              },
              "body": {
                "type": "text",
                "font_size": 16,
                "line_height": 22,
                "text_color": "#D9FFFFFF",
                "width": { "type": "match_parent" },
                "height": { "type": "wrap_content" }
              }
            },
            "card": {
              "log_id": "flow_offer_sheet",
              "states": [
                {
                  "state_id": 0,
                  "div": {
                    "type": "container",
                    "orientation": "vertical",
                    "width": { "type": "match_parent" },
                    "height": { "type": "match_parent" },
                    "paddings": {
                      "left": 24,
                      "right": 24,
                      "top": "@{safe_area_top + 34}",
                      "bottom": "@{safe_area_bottom + 32}"
                    },
                    "background": [
                      {
                        "type": "gradient",
                        "angle": 135,
                        "colors": [
                          "#FF2F246B",
                          "#FF6750A4"
                        ]
                      }
                    ],
                    "items": [
                      {
                        "type": "title",
                        "text": "Native page sheet"
                      },
                      {
                        "type": "body",
                        "text": "The Flutter or SwiftUI host supplied no modal configuration. PNLight presented this route from the server-defined flow.",
                        "margins": { "top": 12, "bottom": 28 }
                      },
                      {
                        "type": "custom",
                        "custom_type": "pnlight.cta_button",
                        "width": { "type": "match_parent" },
                        "height": { "type": "fixed", "value": 54 },
                        "custom_props": {
                          "title": "Push inside modal",
                          "background_color": "#FFFFFFFF",
                          "title_color": "#FF4B3585",
                          "corner_radius": 16,
                          "shimmer": false,
                          "bounce": { "idle": false, "press": true },
                          "url": "pnlight://navigation/push?route=terms"
                        }
                      },
                      {
                        "type": "custom",
                        "custom_type": "pnlight.cta_button",
                        "width": { "type": "match_parent" },
                        "height": { "type": "fixed", "value": 54 },
                        "margins": { "top": 14 },
                        "custom_props": {
                          "title": "Dismiss sheet",
                          "background_color": "#33FFFFFF",
                          "title_color": "#FFFFFFFF",
                          "corner_radius": 16,
                          "shimmer": false,
                          "bounce": { "idle": false, "press": true },
                          "url": "pnlight://navigation/dismiss"
                        }
                      }
                    ]
                  }
                }
              ]
            }
          }
        },
        "terms": {
          "divkit": {
            "templates": {
              "title": {
                "type": "text",
                "font_size": 30,
                "font_weight": "bold",
                "text_color": "#FF111827",
                "width": { "type": "match_parent" },
                "height": { "type": "wrap_content" }
              },
              "body": {
                "type": "text",
                "font_size": 16,
                "line_height": 22,
                "text_color": "#FF6B7280",
                "width": { "type": "match_parent" },
                "height": { "type": "wrap_content" }
              }
            },
            "card": {
              "log_id": "flow_terms",
              "states": [
                {
                  "state_id": 0,
                  "div": {
                    "type": "container",
                    "orientation": "vertical",
                    "width": { "type": "match_parent" },
                    "height": { "type": "match_parent" },
                    "paddings": {
                      "left": 24,
                      "right": 24,
                      "top": "@{safe_area_top + 34}",
                      "bottom": "@{safe_area_bottom + 32}"
                    },
                    "background": [
                      { "type": "solid", "color": "#FFFFFFFF" }
                    ],
                    "items": [
                      {
                        "type": "title",
                        "text": "Modal stack"
                      },
                      {
                        "type": "body",
                        "text": "This route was pushed inside the sheet's own UINavigationController. Pop returns to the sheet root without touching the embedded stack.",
                        "margins": { "top": 12, "bottom": 28 }
                      },
                      {
                        "type": "custom",
                        "custom_type": "pnlight.cta_button",
                        "width": { "type": "match_parent" },
                        "height": { "type": "fixed", "value": 54 },
                        "custom_props": {
                          "title": "Pop to offer",
                          "background_color": "#FF087EF5",
                          "corner_radius": 16,
                          "shimmer": false,
                          "bounce": { "idle": false, "press": true },
                          "url": "pnlight://navigation/pop"
                        }
                      },
                      {
                        "type": "custom",
                        "custom_type": "pnlight.cta_button",
                        "width": { "type": "match_parent" },
                        "height": { "type": "fixed", "value": 54 },
                        "margins": { "top": 14 },
                        "custom_props": {
                          "title": "Dismiss complete sheet",
                          "background_color": "#FF6750A4",
                          "corner_radius": 16,
                          "shimmer": false,
                          "bounce": { "idle": false, "press": true },
                          "url": "pnlight://navigation/dismiss"
                        }
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
