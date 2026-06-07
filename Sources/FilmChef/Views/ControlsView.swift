import SwiftUI

struct ControlsView: View {
    @ObservedObject var editor: EditorStore

    var body: some View {
        Form {
            if let recipe = editor.selectedRecipe {
                Section("Recipe") {
                    LabeledContent("Stock", value: recipe.stockType.label)
                    LabeledContent("ISO", value: "\(recipe.iso)")

                    Text(recipe.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Look") {
                SliderControl(
                    title: "Intensity",
                    value: $editor.intensity,
                    range: 0...1,
                    step: 0.01,
                    valueText: "\(Int(editor.intensity * 100))%"
                )

                SliderControl(
                    title: "Exposure",
                    value: $editor.exposureTrim,
                    range: -1...1,
                    step: 0.05,
                    valueText: signedValue(editor.exposureTrim)
                )

                SliderControl(
                    title: "Contrast",
                    value: $editor.contrastTrim,
                    range: -0.5...0.5,
                    step: 0.01,
                    valueText: signedValue(editor.contrastTrim)
                )

                SliderControl(
                    title: "Saturation",
                    value: $editor.saturationTrim,
                    range: -0.75...0.75,
                    step: 0.01,
                    valueText: signedValue(editor.saturationTrim)
                )

                Toggle("Grain", isOn: $editor.grainEnabled)
                    .disabled(!editor.hasImportedImage)

                Toggle("Original", isOn: $editor.showOriginal)
                    .disabled(!editor.hasImportedImage)
            }
            .disabled(!editor.hasImportedImage)

            Section("Output") {
                Button {
                    editor.resetControls()
                } label: {
                    Label("Reset Adjustments", systemImage: "arrow.counterclockwise")
                }

                Button {
                    editor.exportEditedPhoto()
                } label: {
                    Label("Export Edited Photo", systemImage: "square.and.arrow.down")
                }
                .disabled(!editor.canExport)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Controls")
    }

    private func signedValue(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return value > 0 ? "+\(formatted)" : formatted
    }
}

private struct SliderControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range, step: step)
        }
    }
}
