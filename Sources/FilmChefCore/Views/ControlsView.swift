import SwiftUI

struct ControlsView: View {
    @ObservedObject var editor: EditorStore

    var body: some View {
        Form {
            if let recipe = editor.selectedRecipe {
                Section("Recipe") {
                    LabeledContent("Stock", value: recipe.stock.family.label)
                    LabeledContent("ISO", value: "\(recipe.iso)")
                    LabeledContent("Balance", value: displayName(for: recipe.stock.nativeBalance))

                    Text(recipe.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Pipeline") {
                    LabeledContent("Process", value: displayName(for: recipe.process.type))
                    LabeledContent("Renderer", value: displayName(for: recipe.renderer.type))
                    LabeledContent("Layer Model", value: displayName(for: recipe.layerModel.type))
                    LabeledContent("Grain", value: recipe.grain.enabled ? displayName(for: recipe.grain.model) : "Off")
                    LabeledContent("Halation", value: recipe.halation.enabled ? displayName(for: recipe.halation.model) : "Off")
                }
            }

            Section("Look") {
                Picker("Compare", selection: $editor.comparisonMode) {
                    ForEach(PreviewComparisonMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!editor.hasImportedImage)

                SliderControl(
                    title: "Zoom",
                    value: $editor.previewZoom,
                    range: 0.5...2.0,
                    step: 0.25,
                    valueText: "\(Int(editor.previewZoom * 100))%"
                )
                .disabled(!editor.hasImportedImage)

                SliderControl(
                    title: "Split",
                    value: $editor.splitPosition,
                    range: 0.1...0.9,
                    step: 0.05,
                    valueText: "\(Int(editor.splitPosition * 100))%"
                )
                .disabled(!editor.hasImportedImage || editor.comparisonMode != .split)

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
                Picker("Format", selection: $editor.exportSettings.fileFormat) {
                    ForEach(ExportFileFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }

                SliderControl(
                    title: "JPEG Quality",
                    value: $editor.exportSettings.jpegQuality,
                    range: 0.1...1.0,
                    step: 0.01,
                    valueText: "\(Int(editor.exportSettings.jpegQuality * 100))%"
                )
                .disabled(editor.exportSettings.fileFormat != .jpeg)

                SliderControl(
                    title: "Scale",
                    value: $editor.exportSettings.scale,
                    range: 0.25...2.0,
                    step: 0.25,
                    valueText: "\(Int(editor.exportSettings.scale * 100))%"
                )

                Toggle("Preserve Metadata", isOn: $editor.exportSettings.preserveMetadata)
                Toggle("Embed Color Profile", isOn: $editor.exportSettings.embedColorProfile)
                TextField("Naming", text: $editor.exportSettings.namingTemplate)
                    .textFieldStyle(.roundedBorder)

                Button(action: editor.resetControls) {
                    Label("Reset Adjustments", systemImage: "arrow.counterclockwise")
                }

                Button(action: editor.exportEditedPhoto) {
                    Label("Export Edited Photo", systemImage: "square.and.arrow.down")
                }
                .disabled(!editor.canExport)
            }

            Section("History") {
                HStack {
                    Button(action: editor.undoEdit) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!editor.canUndoEdit)

                    Button(action: editor.redoEdit) {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!editor.canRedoEdit)
                }

                Button(action: { editor.captureVariant() }) {
                    Label("Capture Variant", systemImage: "camera.badge.clock")
                }

                LabeledContent("Snapshots", value: "\(editor.editHistory.count)")
            }

            Section("Local") {
                HStack {
                    Button(action: editor.addLocalAdjustment) {
                        Label("Add Layer", systemImage: "plus.circle")
                    }
                    .disabled(!editor.hasImportedImage)

                    Button(action: editor.removeLocalAdjustments) {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(editor.localAdjustments.isEmpty)
                }

                LabeledContent("Layers", value: "\(editor.localAdjustments.count)")

                if !editor.localAdjustments.isEmpty {
                    Toggle("Enabled", isOn: localLayerBinding(\.isEnabled))

                    Picker("Mask", selection: localLayerBinding(\.mask)) {
                        ForEach(LocalAdjustmentMask.allCases) { mask in
                            Text(mask.label).tag(mask)
                        }
                    }

                    HStack {
                        Button("Center Brush") {
                            editor.localAdjustments[0].mask = .brush
                            editor.localAdjustments[0].pathPoints = [
                                NormalizedMaskPoint(
                                    x: editor.localAdjustments[0].centerX,
                                    y: editor.localAdjustments[0].centerY
                                )
                            ]
                        }

                        Button("Shape Path") {
                            editor.localAdjustments[0].mask = .path
                            editor.localAdjustments[0].pathPoints = LocalAdjustmentLayer.defaultPathPoints
                        }
                    }

                    SliderControl(
                        title: "Center X",
                        value: localLayerBinding(\.centerX),
                        range: 0...1,
                        step: 0.01,
                        valueText: "\(Int(editor.localAdjustments[0].centerX * 100))%"
                    )

                    SliderControl(
                        title: "Center Y",
                        value: localLayerBinding(\.centerY),
                        range: 0...1,
                        step: 0.01,
                        valueText: "\(Int(editor.localAdjustments[0].centerY * 100))%"
                    )

                    SliderControl(
                        title: "Radius",
                        value: localLayerBinding(\.radius),
                        range: 0.05...1,
                        step: 0.01,
                        valueText: "\(Int(editor.localAdjustments[0].radius * 100))%"
                    )

                    if editor.localAdjustments[0].mask == .brush || editor.localAdjustments[0].mask == .path {
                        SliderControl(
                            title: "Brush Size",
                            value: localLayerBinding(\.brushSize),
                            range: 0.02...0.5,
                            step: 0.01,
                            valueText: "\(Int(editor.localAdjustments[0].brushSize * 100))%"
                        )

                        LabeledContent("Path Points", value: "\(editor.localAdjustments[0].pathPoints.count)")
                    }

                    SliderControl(
                        title: "Local Exposure",
                        value: localLayerBinding(\.exposureEV),
                        range: -1...1,
                        step: 0.05,
                        valueText: signedValue(editor.localAdjustments[0].exposureEV)
                    )

                    SliderControl(
                        title: "Local Contrast",
                        value: localLayerBinding(\.contrast),
                        range: -0.5...0.5,
                        step: 0.01,
                        valueText: signedValue(editor.localAdjustments[0].contrast)
                    )

                    SliderControl(
                        title: "Local Saturation",
                        value: localLayerBinding(\.saturation),
                        range: -0.75...0.75,
                        step: 0.01,
                        valueText: signedValue(editor.localAdjustments[0].saturation)
                    )
                }
            }

            Section("Scopes") {
                Picker("Channel", selection: $editor.histogramChannelMode) {
                    ForEach(HistogramChannelMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HistogramView(summary: editor.histogramSummary, channelMode: editor.histogramChannelMode)
                    .frame(height: 110)

                if let summary = editor.histogramSummary {
                    LabeledContent("Shadow Clip", value: "\(Int(summary.shadowClippingRatio * 100))%")
                    LabeledContent("Highlight Clip", value: "\(Int(summary.highlightClippingRatio * 100))%")
                }

                if editor.isRenderingPreview {
                    Label("Rendering preview", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }

                Button(action: { editor.samplePreviewPixel(x: editor.samplerX, y: editor.samplerY) }) {
                    Label("Sample Marker", systemImage: "scope")
                }
                .disabled(!editor.hasImportedImage)

                if let sample = editor.pixelSample {
                    LabeledContent("Sample RGB", value: rgbText(sample))
                    LabeledContent("Sample Luma", value: String(format: "%.2f", sample.luminance))
                    LabeledContent(
                        "Sample Position",
                        value: String(format: "%.2f, %.2f", sample.x, sample.y)
                    )
                }
            }

            Section("Color") {
                Toggle("RAW Development", isOn: $editor.colorManagementSettings.rawDevelopmentEnabled)

                SliderControl(
                    title: "RAW Exposure",
                    value: $editor.colorManagementSettings.rawDevelopment.exposureEV,
                    range: -2...2,
                    step: 0.05,
                    valueText: signedValue(editor.colorManagementSettings.rawDevelopment.exposureEV)
                )

                SliderControl(
                    title: "Temperature",
                    value: $editor.colorManagementSettings.rawDevelopment.temperatureK,
                    range: 2500...9000,
                    step: 100,
                    valueText: "\(Int(editor.colorManagementSettings.rawDevelopment.temperatureK))K"
                )

                SliderControl(
                    title: "Tint",
                    value: $editor.colorManagementSettings.rawDevelopment.tint,
                    range: -1...1,
                    step: 0.05,
                    valueText: signedValue(editor.colorManagementSettings.rawDevelopment.tint)
                )

                SliderControl(
                    title: "Highlight Recovery",
                    value: $editor.colorManagementSettings.rawDevelopment.highlightRecovery,
                    range: 0...1,
                    step: 0.05,
                    valueText: "\(Int(editor.colorManagementSettings.rawDevelopment.highlightRecovery * 100))%"
                )

                TextField("Input", text: $editor.colorManagementSettings.inputIntent)
                TextField("Working", text: $editor.colorManagementSettings.workingColorSpace)
                TextField("Output", text: $editor.colorManagementSettings.outputColorSpace)
                LabeledContent("Calibration", value: editor.calibrationDataStatus.note)
                if !editor.calibrationDataStatus.importedAssetNames.isEmpty {
                    LabeledContent("Assets", value: "\(editor.calibrationDataStatus.importedAssetNames.count)")
                    LabeledContent(
                        "RGB Scale",
                        value: String(
                            format: "%.2f / %.2f / %.2f",
                            editor.calibrationDataStatus.redScale,
                            editor.calibrationDataStatus.greenScale,
                            editor.calibrationDataStatus.blueScale
                        )
                    )
                    LabeledContent(
                        "Density Gamma",
                        value: String(format: "%.2f", editor.calibrationDataStatus.densityGamma)
                    )
                    LabeledContent(
                        "Grain Spectrum",
                        value: "\(Int(editor.calibrationDataStatus.grainAmount * 100))%"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Controls")
    }

    fileprivate func signedValue(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return value > 0 ? "+\(formatted)" : formatted
    }

    fileprivate func displayName(for value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    fileprivate func rgbText(_ sample: PixelSample) -> String {
        "R \(String(format: "%.2f", sample.red)) G \(String(format: "%.2f", sample.green)) B \(String(format: "%.2f", sample.blue))"
    }

    fileprivate func localLayerBinding<Value>(_ keyPath: WritableKeyPath<LocalAdjustmentLayer, Value>) -> Binding<Value> {
        Binding(
            get: { editor.localAdjustments[0][keyPath: keyPath] },
            set: { value in
                guard !editor.localAdjustments.isEmpty else {
                    return
                }
                editor.localAdjustments[0][keyPath: keyPath] = value
            }
        )
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

package enum ControlsViewCoverageProbe {
    @MainActor
    package static func touch(editor: EditorStore) {
        let controlsView = ControlsView(editor: editor)
        _ = controlsView.body
        _ = controlsView.signedValue(0.2)
        _ = controlsView.signedValue(-0.2)
        _ = controlsView.displayName(for: "test_value")

        var value = 0.5
        _ = SliderControl(
            title: "Test",
            value: Binding(get: { value }, set: { value = $0 }),
            range: 0...1,
            step: 0.1,
            valueText: "50%"
        ).body
    }
}
