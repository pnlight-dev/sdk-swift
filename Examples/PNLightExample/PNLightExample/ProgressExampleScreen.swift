import SwiftUI
import PNLightSDK

struct ProgressExampleScreen: View {
    var body: some View {
        ProgressMarkupView()
            .navigationTitle("Progress & Numbers")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct ProgressMarkupView: UIViewRepresentable {
    func makeUIView(context: Context) -> PNLightRemoteUiView {
        let view = PNLightRemoteUiView()
        view.applyConfig(configJson: Self.markup, cardId: "native_progress_example")
        return view
    }

    func updateUIView(_ uiView: PNLightRemoteUiView, context: Context) {}

    // `pnlight.progress_bar` and `pnlight.animated_number` are schema v3 native
    // components. Both animate between values on their own, so the markup only
    // has to move a variable; no per-step DivKit animation is involved.
    private static let markup = #"""
    {
      "schemaVersion": 3,
      "card": {
        "log_id": "native_progress_example",
        "variables": [
          { "type": "number", "name": "scan_progress", "value": 0 },
          { "type": "integer", "name": "issues_found", "value": 0 }
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
                  "type": "section_label",
                  "text": "Variable-driven bar (@{scan_progress})"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.progress_bar",
                  "width": { "type": "match_parent" },
                  "height": { "type": "fixed", "value": 10 },
                  "custom_props": {
                    "instance_id": "scan",
                    "progress": 0,
                    "progress_variable": "scan_progress",
                    "animation_duration": 0.45
                  }
                },
                {
                  "type": "container",
                  "orientation": "horizontal",
                  "width": { "type": "match_parent" },
                  "height": { "type": "wrap_content" },
                  "margins": { "top": 12 },
                  "item_spacing": 8,
                  "items": [
                    { "type": "step_button", "text": "0%", "actions": [{ "log_id": "p0", "typed": { "type": "set_variable", "variable_name": "scan_progress", "value": { "type": "number", "value": 0 } } }] },
                    { "type": "step_button", "text": "35%", "actions": [{ "log_id": "p35", "typed": { "type": "set_variable", "variable_name": "scan_progress", "value": { "type": "number", "value": 0.35 } } }] },
                    { "type": "step_button", "text": "70%", "actions": [{ "log_id": "p70", "typed": { "type": "set_variable", "variable_name": "scan_progress", "value": { "type": "number", "value": 0.7 } } }] },
                    { "type": "step_button", "text": "100%", "actions": [{ "log_id": "p100", "typed": { "type": "set_variable", "variable_name": "scan_progress", "value": { "type": "number", "value": 1 } } }] }
                  ]
                },
                {
                  "type": "section_label",
                  "text": "Gradient fill, inset track"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.progress_bar",
                  "width": { "type": "match_parent" },
                  "height": { "type": "fixed", "value": 22 },
                  "custom_props": {
                    "instance_id": "gradient",
                    "progress": 0.62,
                    "initial_progress": 0,
                    "track_color": "#FFE5E5EA",
                    "fill_color": "#FF34C759",
                    "fill_color_end": "#FF007AFF",
                    "corner_radius": 8,
                    "fill_inset": 3,
                    "animation_duration": 1.2
                  }
                },
                {
                  "type": "section_label",
                  "text": "Indeterminate (unknown duration)"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.progress_bar",
                  "width": { "type": "match_parent" },
                  "height": { "type": "wrap_content" },
                  "custom_props": {
                    "instance_id": "indeterminate",
                    "indeterminate": true,
                    "track_height": 6,
                    "fill_color": "#FFFF9500"
                  }
                },
                {
                  "type": "section_label",
                  "text": "Counts up on appear"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.animated_number",
                  "width": { "type": "match_parent" },
                  "height": { "type": "wrap_content" },
                  "custom_props": {
                    "instance_id": "storage",
                    "value": 128.4,
                    "initial_value": 0,
                    "decimals": 1,
                    "suffix": " GB",
                    "font_size": 44,
                    "font_weight": "heavy",
                    "text_color": "#FF007AFF",
                    "animation_duration": 1.4
                  }
                },
                {
                  "type": "section_label",
                  "text": "Variable-driven number"
                },
                {
                  "type": "custom",
                  "custom_type": "pnlight.animated_number",
                  "width": { "type": "match_parent" },
                  "height": { "type": "wrap_content" },
                  "custom_props": {
                    "instance_id": "issues",
                    "value": 0,
                    "value_variable": "issues_found",
                    "suffix": " issues found",
                    "font_size": 28,
                    "font_weight": "bold"
                  }
                },
                {
                  "type": "container",
                  "orientation": "horizontal",
                  "width": { "type": "match_parent" },
                  "height": { "type": "wrap_content" },
                  "margins": { "top": 12 },
                  "item_spacing": 8,
                  "items": [
                    { "type": "step_button", "text": "0", "actions": [{ "log_id": "i0", "typed": { "type": "set_variable", "variable_name": "issues_found", "value": { "type": "integer", "value": 0 } } }] },
                    { "type": "step_button", "text": "14", "actions": [{ "log_id": "i14", "typed": { "type": "set_variable", "variable_name": "issues_found", "value": { "type": "integer", "value": 14 } } }] },
                    { "type": "step_button", "text": "1284", "actions": [{ "log_id": "i1284", "typed": { "type": "set_variable", "variable_name": "issues_found", "value": { "type": "integer", "value": 1284 } } }] }
                  ]
                }
              ]
            }
          }
        ]
      },
      "templates": {
        "section_label": {
          "type": "text",
          "font_size": 13,
          "font_weight": "medium",
          "text_color": "#8E8E93",
          "width": { "type": "match_parent" },
          "height": { "type": "wrap_content" },
          "margins": { "top": 22, "bottom": 8 }
        },
        "step_button": {
          "type": "text",
          "font_size": 15,
          "font_weight": "medium",
          "text_alignment_horizontal": "center",
          "text_color": "#FF007AFF",
          "width": { "type": "match_parent" },
          "height": { "type": "fixed", "value": 40 },
          "paddings": { "top": 10 },
          "border": { "corner_radius": 12 },
          "background": [{ "type": "solid", "color": "#FFE5E5EA" }]
        }
      }
    }
    """#
}

#Preview {
    NavigationStack {
        ProgressExampleScreen()
    }
}
