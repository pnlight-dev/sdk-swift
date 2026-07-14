import SwiftUI
import PNLightSDK

struct CircularLoaderExampleScreen: View {
    var body: some View {
        CircularLoaderMarkupView()
            .navigationTitle("Native Circular Loader")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct CircularLoaderMarkupView: UIViewRepresentable {
    func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.applyConfig(configJson: Self.markup, cardId: "native_circular_loader_example")
        return view
    }

    func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {}

    private static let markup = #"""
    {
      "card": {
        "log_id": "native_circular_loader_example",
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
              "items": [
                {
                  "type": "custom",
                  "custom_type": "pnlight.circular_loader",
                  "width": { "type": "fixed", "value": 48 },
                  "height": { "type": "fixed", "value": 48 },
                  "custom_props": {
                    "style": "large",
                    "color": "#FF007AFF",
                    "accessibility_label": "Loading example content"
                  }
                },
                {
                  "type": "text",
                  "text": "Native UIActivityIndicatorView",
                  "font_size": 17,
                  "font_weight": "medium",
                  "text_alignment_horizontal": "center",
                  "width": { "type": "wrap_content" },
                  "height": { "type": "wrap_content" },
                  "margins": { "top": 16 }
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
        CircularLoaderExampleScreen()
    }
}
