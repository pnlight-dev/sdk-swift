import SwiftUI
import PNLightSDK

struct LottieExampleScreen: View {
    var body: some View {
        LottieMarkupView()
            .navigationTitle("Remote UI Lottie")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct LottieMarkupView: UIViewRepresentable {
    func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.applyConfig(configJson: Self.markup, cardId: "lottie_example")
        return view
    }

    func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {}

    private static let markup = #"""
    {
      "card": {
        "log_id": "lottie_example",
        "states": [
          {
            "state_id": 0,
            "div": {
              "type": "container",
              "orientation": "vertical",
              "content_alignment_horizontal": "center",
              "content_alignment_vertical": "center",
              "width": { "type": "match_parent" },
              "height": { "type": "match_parent" },
              "paddings": {
                "left": 24,
                "right": 24,
                "top": 24,
                "bottom": 24
              },
              "items": [
                {
                  "type": "container",
                  "width": { "type": "fixed", "value": 220 },
                  "height": { "type": "fixed", "value": 220 },
                  "items": [],
                  "extensions": [
                    {
                      "id": "lottie",
                      "params": {
                        "repeat_count": 0,
                        "repeat_mode": "reverse",
                        "is_playing": true,
                        "lottie_json": {
                          "v": "5.7.4",
                          "fr": 60,
                          "ip": 0,
                          "op": 120,
                          "w": 200,
                          "h": 200,
                          "nm": "PNLight pulse",
                          "ddd": 0,
                          "assets": [],
                          "layers": [
                            {
                              "ddd": 0,
                              "ind": 1,
                              "ty": 4,
                              "nm": "Pulse",
                              "sr": 1,
                              "ks": {
                                "o": { "a": 0, "k": 100 },
                                "r": { "a": 0, "k": 0 },
                                "p": { "a": 0, "k": [100, 100, 0] },
                                "a": { "a": 0, "k": [0, 0, 0] },
                                "s": {
                                  "a": 1,
                                  "k": [
                                    {
                                      "t": 0,
                                      "s": [60, 60, 100],
                                      "e": [100, 100, 100]
                                    },
                                    {
                                      "t": 60,
                                      "s": [100, 100, 100],
                                      "e": [60, 60, 100]
                                    },
                                    {
                                      "t": 120,
                                      "s": [60, 60, 100]
                                    }
                                  ]
                                }
                              },
                              "ao": 0,
                              "shapes": [
                                {
                                  "ty": "el",
                                  "p": { "a": 0, "k": [0, 0] },
                                  "s": { "a": 0, "k": [120, 120] },
                                  "nm": "Ellipse"
                                },
                                {
                                  "ty": "fl",
                                  "c": { "a": 0, "k": [0.03, 0.49, 0.96, 1] },
                                  "o": { "a": 0, "k": 100 },
                                  "r": 1,
                                  "nm": "Fill"
                                }
                              ],
                              "ip": 0,
                              "op": 120,
                              "st": 0,
                              "bm": 0
                            }
                          ]
                        }
                      }
                    }
                  ]
                },
                {
                  "type": "text",
                  "text": "DivKit Lottie extension",
                  "font_size": 22,
                  "font_weight": "bold",
                  "text_alignment_horizontal": "center",
                  "text_color": "#FF111827",
                  "width": { "type": "match_parent" },
                  "height": { "type": "wrap_content" },
                  "margins": { "top": 16 }
                },
                {
                  "type": "text",
                  "text": "This animation is embedded in the server markup. Apps using PNLightSDK require no Lottie configuration.",
                  "font_size": 15,
                  "line_height": 21,
                  "text_alignment_horizontal": "center",
                  "text_color": "#FF6B7280",
                  "width": { "type": "match_parent" },
                  "height": { "type": "wrap_content" },
                  "margins": { "top": 8 }
                }
              ]
            }
          }
        ]
      }
    }
    """#
}

#Preview {
    NavigationStack {
        LottieExampleScreen()
    }
}
