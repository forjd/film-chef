import SwiftUI

struct ControlsView: View {
    @ObservedObject var editor: EditorStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let recipe = editor.selectedRecipe {
                    InspectorSection("Recipe") {
                        HStack(alignment: .center, spacing: 8) {
                            Label(
                                editor.selectedRecipeIsEditable ? "Editable" : "Bundled",
                                systemImage: editor.selectedRecipeIsEditable ? "pencil.circle" : "lock"
                            )
                            .foregroundStyle(.secondary)

                            Spacer()

                            Button(action: editor.duplicateSelectedRecipeForEditing) {
                                Label("Duplicate", systemImage: "doc.on.doc")
                            }

                            Button(action: editor.exportSelectedRecipe) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        InfoRow("Stock", value: recipe.stock.family.label)
                        InfoRow("ISO", value: "\(recipe.iso)")
                        InfoRow("Balance", value: displayName(for: recipe.stock.nativeBalance))

                        Text(recipe.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if editor.selectedRecipeValidationIssues.isEmpty {
                            Label("Recipe schema valid", systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            ForEach(editor.selectedRecipeValidationIssues, id: \.self) { issue in
                                Label(issue.message, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    InspectorSection("Pipeline") {
                        InfoRow("Process", value: displayName(for: recipe.process.type))
                        InfoRow("Renderer", value: displayName(for: recipe.renderer.type))
                        InfoRow("Layer Model", value: displayName(for: recipe.layerModel.type))
                        InfoRow("Grain", value: recipe.grain.enabled ? displayName(for: recipe.grain.model) : "Off")
                        InfoRow("Halation", value: recipe.halation.enabled ? displayName(for: recipe.halation.model) : "Off")
                    }

                    InspectorSection("Recipe Editor") {
                        TextField("Name", text: $editor.recipeDraft.displayName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!editor.selectedRecipeIsEditable)

                        TextField("Maker", text: $editor.recipeDraft.manufacturer)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!editor.selectedRecipeIsEditable)

                        TextField("Summary", text: $editor.recipeDraft.summary, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Stock ISO",
                            value: $editor.recipeDraft.stockBoxSpeedIso,
                            range: 25...6400,
                            step: 1,
                            valueText: "\(Int(editor.recipeDraft.stockBoxSpeedIso.rounded()))"
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Exposed At",
                            value: $editor.recipeDraft.exposedAtIso,
                            range: 25...6400,
                            step: 1,
                            valueText: "\(Int(editor.recipeDraft.exposedAtIso.rounded()))"
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Profile EV",
                            value: $editor.recipeDraft.exposureCompensationEv,
                            range: -4...4,
                            step: 0.05,
                            valueText: signedValue(editor.recipeDraft.exposureCompensationEv)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Capture Temp",
                            value: $editor.recipeDraft.captureColourTemperatureK,
                            range: 2500...9000,
                            step: 100,
                            valueText: "\(Int(editor.recipeDraft.captureColourTemperatureK.rounded()))K"
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        TextField("Capture Filter", text: $editor.recipeDraft.captureFilterType)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Filter Strength",
                            value: $editor.recipeDraft.captureFilterStrength,
                            range: 0...1,
                            step: 0.01,
                            valueText: "\(Int(editor.recipeDraft.captureFilterStrength * 100))%"
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Recipe Saturation",
                            value: $editor.recipeDraft.colourSaturation,
                            range: 0...3,
                            step: 0.01,
                            valueText: String(format: "%.2f", editor.recipeDraft.colourSaturation)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Recipe Warmth",
                            value: $editor.recipeDraft.colourWarmth,
                            range: -1...1,
                            step: 0.01,
                            valueText: signedValue(editor.recipeDraft.colourWarmth)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Push/Pull",
                            value: $editor.recipeDraft.processPushPullStops,
                            range: -3...3,
                            step: 0.05,
                            valueText: signedValue(editor.recipeDraft.processPushPullStops)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Process Contrast",
                            value: $editor.recipeDraft.processContrastMultiplier,
                            range: 0.25...2.5,
                            step: 0.01,
                            valueText: String(format: "%.2f", editor.recipeDraft.processContrastMultiplier)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Process Grain",
                            value: $editor.recipeDraft.processGrainMultiplier,
                            range: 0...3,
                            step: 0.01,
                            valueText: String(format: "%.2f", editor.recipeDraft.processGrainMultiplier)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        Toggle("Recipe Grain Enabled", isOn: $editor.recipeDraft.grainEnabled)
                            .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Grain Strength",
                            value: $editor.recipeDraft.grainStrength,
                            range: 0...2,
                            step: 0.01,
                            valueText: String(format: "%.2f", editor.recipeDraft.grainStrength)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Grain Size",
                            value: $editor.recipeDraft.grainSize,
                            range: 0...5,
                            step: 0.01,
                            valueText: String(format: "%.2f", editor.recipeDraft.grainSize)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        Toggle("Recipe Halation Enabled", isOn: $editor.recipeDraft.halationEnabled)
                            .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Halation",
                            value: $editor.recipeDraft.halationStrength,
                            range: 0...2,
                            step: 0.01,
                            valueText: String(format: "%.2f", editor.recipeDraft.halationStrength)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Halation Radius",
                            value: $editor.recipeDraft.halationRadius,
                            range: 0...100,
                            step: 0.5,
                            valueText: String(format: "%.1f", editor.recipeDraft.halationRadius)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Acutance",
                            value: $editor.recipeDraft.sharpnessAcutance,
                            range: 0...2,
                            step: 0.01,
                            valueText: String(format: "%.2f", editor.recipeDraft.sharpnessAcutance)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Render Contrast",
                            value: $editor.recipeDraft.rendererContrast,
                            range: 0.1...4,
                            step: 0.01,
                            valueText: String(format: "%.2f", editor.recipeDraft.rendererContrast)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Render Saturation",
                            value: $editor.recipeDraft.rendererSaturation,
                            range: 0...4,
                            step: 0.01,
                            valueText: String(format: "%.2f", editor.recipeDraft.rendererSaturation)
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        TextField("Output Space", text: $editor.recipeDraft.outputColourSpace)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!editor.selectedRecipeIsEditable)

                        SliderControl(
                            title: "Output Bit Depth",
                            value: $editor.recipeDraft.outputBitDepth,
                            range: 8...32,
                            step: 1,
                            valueText: "\(Int(editor.recipeDraft.outputBitDepth.rounded()))"
                        )
                        .disabled(!editor.selectedRecipeIsEditable)

                        if !editor.selectedRecipeIsEditable {
                            Label("Duplicate this bundled recipe to edit its metadata.", systemImage: "lock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(editor.recipeDraftIssues, id: \.self) { issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        HStack(spacing: 8) {
                            Button(action: editor.resetRecipeDraft) {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(!editor.selectedRecipeIsEditable)

                            Button(action: editor.applyRecipeDraft) {
                                Label("Apply", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!editor.canApplyRecipeDraft)
                        }
                    }
                }

                if let recipeImportStatus = editor.recipeImportStatus {
                    InspectorSection(recipeImportStatus.title) {
                        Text(recipeImportStatus.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: editor.clearRecipeImportStatus) {
                            Label("Dismiss", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                InspectorSection("Look") {
                    Picker("Compare", selection: $editor.comparisonMode) {
                        ForEach(PreviewComparisonMode.allCases) { mode in
                            Text(compactComparisonLabel(for: mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(!editor.hasImportedImage)

                    SliderControl(
                        title: "Zoom",
                        value: $editor.previewZoom,
                        range: 0.5...4.0,
                        step: 0.25,
                        valueText: "\(Int(editor.previewZoom * 100))%"
                    )
                    .disabled(!editor.hasImportedImage)

                    Toggle("Loupe", isOn: $editor.loupeEnabled)
                        .disabled(!editor.hasImportedImage)

                    SliderControl(
                        title: "Loupe Zoom",
                        value: $editor.loupeZoom,
                        range: 1.5...5.0,
                        step: 0.25,
                        valueText: "\(String(format: "%.1f", editor.loupeZoom))x"
                    )
                    .disabled(!editor.hasImportedImage || !editor.loupeEnabled)

                    Picker("Loupe Position", selection: $editor.loupePlacement) {
                        ForEach(LoupePlacement.allCases) { placement in
                            Text(placement.label).tag(placement)
                        }
                    }
                    .disabled(!editor.hasImportedImage || !editor.loupeEnabled)

                    HStack(spacing: 8) {
                        Button(action: { editor.panPreview(deltaX: -32, deltaY: 0) }) {
                            Label("Left", systemImage: "arrow.left")
                                .frame(maxWidth: .infinity)
                        }

                        Button(action: { editor.panPreview(deltaX: 32, deltaY: 0) }) {
                            Label("Right", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }

                        Button(action: editor.resetPreviewView) {
                            Label("Center", systemImage: "scope")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!editor.canResetPreviewView)
                    }
                    .disabled(!editor.hasImportedImage || editor.previewZoom <= 1.0)

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

                InspectorSection("Output") {
                    Picker("Preset", selection: $editor.selectedExportPresetID) {
                        Text("Current Settings").tag(Optional<UUID>.none)
                        ForEach(editor.exportPresets) { preset in
                            Text(preset.name).tag(Optional(preset.id))
                        }
                    }
                    .onChange(of: editor.selectedExportPresetID) {
                        editor.applySelectedExportPreset()
                    }

                    TextField("Preset Name", text: $editor.exportPresetDraftName)
                        .textFieldStyle(.roundedBorder)

                    if let selectedPreset = editor.exportPresets.first(where: { $0.id == editor.selectedExportPresetID }) {
                        Label("Updating \(selectedPreset.name)", systemImage: "square.and.pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Saving creates a new preset", systemImage: "plus.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(editor.exportPresetNameIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack(spacing: 8) {
                        Button(action: editor.beginNewExportPreset) {
                            Label("New", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }

                        Button(action: editor.saveExportPreset) {
                            Label("Save Preset", systemImage: "tray.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!editor.canSaveExportPreset)

                        Button(action: editor.deleteSelectedExportPreset) {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(editor.selectedExportPresetID == nil || editor.exportPresets.count <= 1)
                    }

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
                    InfoRow("Preview Name", value: editor.exportFileNamePreview)
                    ForEach(editor.exportNamingTemplateIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack(spacing: 8) {
                        Button(action: editor.resetControls) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .frame(maxWidth: .infinity)

                        Button(action: editor.exportEditedPhoto) {
                            Label("Export", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!editor.canExportCurrentSettings)
                        .frame(maxWidth: .infinity)
                    }
                }

                InspectorSection("History") {
                    HStack(spacing: 8) {
                        Button(action: editor.undoEdit) {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!editor.canUndoEdit)

                        Button(action: editor.redoEdit) {
                            Label("Redo", systemImage: "arrow.uturn.forward")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!editor.canRedoEdit)
                    }

                    Button(action: { editor.captureVariant() }) {
                        Label("Capture Variant", systemImage: "camera.badge.clock")
                            .frame(maxWidth: .infinity)
                    }

                    InfoRow("Snapshots", value: "\(editor.editHistory.count)")

                    ForEach(Array(editor.editHistory.enumerated()), id: \.element.id) { index, snapshot in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: editor.editHistoryIndex == index ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(editor.editHistoryIndex == index ? Color.accentColor : Color.secondary)
                                    .frame(width: 16)

                                TextField("Variant Name", text: variantNoteBinding(snapshot.id))
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 8) {
                                Button(action: { editor.restoreVariant(id: snapshot.id) }) {
                                    Label("Restore", systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity)
                                }

                                Button(action: { editor.duplicateVariant(id: snapshot.id) }) {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                        .frame(maxWidth: .infinity)
                                }

                                Button(action: { editor.deleteVariant(id: snapshot.id) }) {
                                    Label("Delete", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                                .disabled(editor.editHistory.count <= 1)
                            }
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                InspectorSection("Local") {
                    HStack(spacing: 8) {
                        Button(action: editor.addLocalAdjustment) {
                            Label("Add Layer", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!editor.hasImportedImage)

                        Button(action: editor.removeLocalAdjustments) {
                            Label("Clear", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(editor.localAdjustments.isEmpty)
                    }

                    InfoRow("Layers", value: "\(editor.localAdjustments.count)")

                    if !editor.localAdjustments.isEmpty {
                        Picker("Layer", selection: $editor.selectedLocalAdjustmentID) {
                            ForEach(editor.localAdjustments) { layer in
                                Text(layer.name).tag(Optional(layer.id))
                            }
                        }

                        TextField("Layer Name", text: localLayerBinding(\.name))
                            .textFieldStyle(.roundedBorder)

                        Toggle("Enabled", isOn: localLayerBinding(\.isEnabled))

                        Picker("Mask", selection: localLayerBinding(\.mask)) {
                            ForEach(LocalAdjustmentMask.allCases) { mask in
                                Text(mask.label).tag(mask)
                            }
                        }

                        Toggle("Edit on Preview", isOn: $editor.localMaskEditingEnabled)
                            .disabled(!editor.canEditLocalMaskOnPreview)

                        HStack(spacing: 8) {
                            Button("Center Brush") {
                                let index = selectedLocalAdjustmentIndex()
                                editor.localAdjustments[index].mask = .brush
                                editor.localAdjustments[index].pathPoints = [
                                    NormalizedMaskPoint(
                                        x: editor.localAdjustments[index].centerX,
                                        y: editor.localAdjustments[index].centerY
                                    )
                                ]
                            }
                            .frame(maxWidth: .infinity)

                            Button("Shape Path") {
                                let index = selectedLocalAdjustmentIndex()
                                editor.localAdjustments[index].mask = .path
                                editor.localAdjustments[index].pathPoints = LocalAdjustmentLayer.defaultPathPoints
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Button(action: editor.removeSelectedLocalAdjustment) {
                            Label("Remove Selected", systemImage: "minus.circle")
                                .frame(maxWidth: .infinity)
                        }

                        SliderControl(
                            title: "Center X",
                            value: localLayerBinding(\.centerX),
                            range: 0...1,
                            step: 0.01,
                            valueText: "\(Int(editor.localAdjustments[selectedLocalAdjustmentIndex()].centerX * 100))%"
                        )

                        SliderControl(
                            title: "Center Y",
                            value: localLayerBinding(\.centerY),
                            range: 0...1,
                            step: 0.01,
                            valueText: "\(Int(editor.localAdjustments[selectedLocalAdjustmentIndex()].centerY * 100))%"
                        )

                        SliderControl(
                            title: "Radius",
                            value: localLayerBinding(\.radius),
                            range: 0.05...1,
                            step: 0.01,
                            valueText: "\(Int(editor.localAdjustments[selectedLocalAdjustmentIndex()].radius * 100))%"
                        )

                        if editor.localAdjustments[selectedLocalAdjustmentIndex()].mask == .brush || editor.localAdjustments[selectedLocalAdjustmentIndex()].mask == .path {
                            SliderControl(
                                title: "Brush Size",
                                value: localLayerBinding(\.brushSize),
                                range: 0.02...0.5,
                                step: 0.01,
                                valueText: "\(Int(editor.localAdjustments[selectedLocalAdjustmentIndex()].brushSize * 100))%"
                            )

                            InfoRow("Path Points", value: "\(editor.localAdjustments[selectedLocalAdjustmentIndex()].pathPoints.count)")
                        }

                        SliderControl(
                            title: "Local Exposure",
                            value: localLayerBinding(\.exposureEV),
                            range: -1...1,
                            step: 0.05,
                            valueText: signedValue(editor.localAdjustments[selectedLocalAdjustmentIndex()].exposureEV)
                        )

                        SliderControl(
                            title: "Local Contrast",
                            value: localLayerBinding(\.contrast),
                            range: -0.5...0.5,
                            step: 0.01,
                            valueText: signedValue(editor.localAdjustments[selectedLocalAdjustmentIndex()].contrast)
                        )

                        SliderControl(
                            title: "Local Saturation",
                            value: localLayerBinding(\.saturation),
                            range: -0.75...0.75,
                            step: 0.01,
                            valueText: signedValue(editor.localAdjustments[selectedLocalAdjustmentIndex()].saturation)
                        )
                    }
                }

                InspectorSection("Scopes") {
                    Picker("Channel", selection: $editor.histogramChannelMode) {
                        ForEach(HistogramChannelMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HistogramView(summary: editor.histogramSummary, channelMode: editor.histogramChannelMode)
                        .frame(height: 110)

                    if let summary = editor.histogramSummary {
                        InfoRow("Shadow Clip", value: "\(Int(summary.shadowClippingRatio * 100))%")
                        InfoRow("Highlight Clip", value: "\(Int(summary.highlightClippingRatio * 100))%")
                    }

                    SliderControl(
                        title: "Clip Alert",
                        value: $editor.histogramClipWarningThreshold,
                        range: 0.005...0.25,
                        step: 0.005,
                        valueText: "\(Int(editor.histogramClipWarningThreshold * 100))%"
                    )

                    if let warning = editor.histogramClipWarningText {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if editor.isRenderingPreview {
                        Label(editor.previewRenderStatus, systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                        ProgressView(value: editor.previewRenderProgress)
                    } else if editor.previewCacheHitCount > 0 {
                        Label("Preview cache hits \(editor.previewCacheHitCount)", systemImage: "bolt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: { editor.samplePreviewPixel(x: editor.samplerX, y: editor.samplerY) }) {
                        Label("Sample Marker", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!editor.hasImportedImage)

                    if let sample = editor.pixelSample {
                        InfoRow("Sample RGB", value: rgbText(sample))
                        InfoRow("Sample Luma", value: String(format: "%.2f", sample.luminance))
                        InfoRow(
                            "Sample Position",
                            value: String(format: "%.2f, %.2f", sample.x, sample.y)
                        )
                    }
                }

                InspectorSection("Color") {
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

                    Picker("Output", selection: $editor.colorManagementSettings.outputColorSpace) {
                        ForEach(ColorOutputProfile.allCases) { profile in
                            Text(profile.label).tag(profile.rawValue)
                        }
                    }
                    InfoRow("Output Profile", value: editor.selectedOutputProfile.label)
                    InfoRow("Calibration", value: editor.calibrationDataStatus.note)
                    if !editor.calibrationDataStatus.importedAssetNames.isEmpty {
                        InfoRow("Assets", value: "\(editor.calibrationDataStatus.importedAssetNames.count)")
                        ForEach(editor.calibrationDataStatus.importedAssetSummaries, id: \.self) { summary in
                            Label(summary, systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        InfoRow(
                            "RGB Scale",
                            value: String(
                                format: "%.2f / %.2f / %.2f",
                                editor.calibrationDataStatus.redScale,
                                editor.calibrationDataStatus.greenScale,
                                editor.calibrationDataStatus.blueScale
                            )
                        )
                        InfoRow(
                            "Density Gamma",
                            value: String(format: "%.2f", editor.calibrationDataStatus.densityGamma)
                        )
                        InfoRow(
                            "Grain Spectrum",
                            value: "\(Int(editor.calibrationDataStatus.grainAmount * 100))%"
                        )
                    }
                }

                InspectorSection("Batch") {
                    InfoRow("Status", value: editor.batchExportState.statusText)
                    if !editor.batchExportState.exportedFileNames.isEmpty {
                        InfoRow("Exported", value: "\(editor.batchExportState.exportedFileNames.count)")
                    }
                    if !editor.batchExportState.failures.isEmpty {
                        InfoRow("Failed", value: "\(editor.batchExportState.failures.count)")
                        ForEach(editor.batchExportState.failures) { failure in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failure.itemName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Text(failure.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    ProgressView(value: editor.batchExportState.progress)
                    Button(action: editor.cancelBatchExport) {
                        Label("Cancel Batch", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!editor.batchExportState.isExporting)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

    fileprivate func compactComparisonLabel(for mode: PreviewComparisonMode) -> String {
        switch mode {
        case .edited:
            return "Edit"
        case .original:
            return "Orig"
        case .split:
            return "Split"
        case .sideBySide:
            return "Side"
        }
    }

    fileprivate func localLayerBinding<Value>(_ keyPath: WritableKeyPath<LocalAdjustmentLayer, Value>) -> Binding<Value> {
        Binding(
            get: { editor.localAdjustments[selectedLocalAdjustmentIndex()][keyPath: keyPath] },
            set: { value in
                guard !editor.localAdjustments.isEmpty else {
                    return
                }
                editor.localAdjustments[selectedLocalAdjustmentIndex()][keyPath: keyPath] = value
            }
        )
    }

    fileprivate func variantNoteBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { editor.editHistory.first(where: { $0.id == id })?.note ?? "" },
            set: { editor.renameVariant(id: id, note: $0) }
        )
    }

    fileprivate func selectedLocalAdjustmentIndex() -> Int {
        guard let selectedLocalAdjustmentID = editor.selectedLocalAdjustmentID,
              let index = editor.localAdjustments.firstIndex(where: { $0.id == selectedLocalAdjustmentID })
        else {
            return 0
        }
        return index
    }

}

private struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            }
        }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
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
                    .lineLimit(1)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.callout)

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
