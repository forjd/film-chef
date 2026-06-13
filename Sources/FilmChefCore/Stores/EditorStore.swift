import AppKit
import CoreImage
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class EditorStore: ObservableObject {
    private struct PreviewRenderCacheKey: Hashable {
        var projectItemID: UUID?
        var sourceIdentifier: String
        var sourceWidth: Int
        var sourceHeight: Int
        var recipe: FilmRecipe
        var adjustments: RenderAdjustments
        var localAdjustments: [LocalAdjustmentLayer]
        var calibration: CalibrationDataStatus
    }

    private struct PreviewRenderResult {
        var image: NSImage
        var histogram: HistogramSummary
    }

    private struct BatchExportRequest {
        var directory: URL
        var items: [FilmProjectItem]
        var recipes: [FilmRecipe]
        var fallbackRecipeID: String?
        var exportSettings: ExportSettings
        var calibration: CalibrationDataStatus
        var colorSettings: ColorManagementSettings
    }

    package struct RecipeDraft: Equatable {
        package var displayName: String
        package var manufacturer: String
        package var summary: String
        package var stockBoxSpeedIso: Double
        package var exposureBoxSpeedIso: Double
        package var exposedAtIso: Double
        package var exposureCompensationEv: Double
        package var captureColourTemperatureK: Double
        package var captureFilterType: String
        package var captureFilterStrength: Double
        package var colourSaturation: Double
        package var colourWarmth: Double
        package var processPushPullStops: Double
        package var processContrastMultiplier: Double
        package var processGrainMultiplier: Double
        package var grainEnabled: Bool
        package var grainStrength: Double
        package var grainSize: Double
        package var halationEnabled: Bool
        package var halationStrength: Double
        package var halationRadius: Double
        package var sharpnessAcutance: Double
        package var rendererContrast: Double
        package var rendererSaturation: Double
        package var outputColourSpace: String
        package var outputBitDepth: Double
        package var layerRGBToLayerMatrix: [[Double]]
        package var characteristicCurveToes: [String: Double]
        package var characteristicCurveGammas: [String: Double]
        package var characteristicCurveShoulders: [String: Double]

        package init(
            displayName: String = "",
            manufacturer: String = "",
            summary: String = "",
            stockBoxSpeedIso: Double = 400,
            exposureBoxSpeedIso: Double = 400,
            exposedAtIso: Double = 400,
            exposureCompensationEv: Double = 0,
            captureColourTemperatureK: Double = 5500,
            captureFilterType: String = "none",
            captureFilterStrength: Double = 0,
            colourSaturation: Double = 1,
            colourWarmth: Double = 0,
            processPushPullStops: Double = 0,
            processContrastMultiplier: Double = 1,
            processGrainMultiplier: Double = 1,
            grainEnabled: Bool = true,
            grainStrength: Double = 0,
            grainSize: Double = 1,
            halationEnabled: Bool = false,
            halationStrength: Double = 0,
            halationRadius: Double = 0,
            sharpnessAcutance: Double = 0,
            rendererContrast: Double = 1,
            rendererSaturation: Double = 1,
            outputColourSpace: String = "srgb",
            outputBitDepth: Double = 8,
            layerRGBToLayerMatrix: [[Double]] = [],
            characteristicCurveToes: [String: Double] = [:],
            characteristicCurveGammas: [String: Double] = [:],
            characteristicCurveShoulders: [String: Double] = [:]
        ) {
            self.displayName = displayName
            self.manufacturer = manufacturer
            self.summary = summary
            self.stockBoxSpeedIso = stockBoxSpeedIso
            self.exposureBoxSpeedIso = exposureBoxSpeedIso
            self.exposedAtIso = exposedAtIso
            self.exposureCompensationEv = exposureCompensationEv
            self.captureColourTemperatureK = captureColourTemperatureK
            self.captureFilterType = captureFilterType
            self.captureFilterStrength = captureFilterStrength
            self.colourSaturation = colourSaturation
            self.colourWarmth = colourWarmth
            self.processPushPullStops = processPushPullStops
            self.processContrastMultiplier = processContrastMultiplier
            self.processGrainMultiplier = processGrainMultiplier
            self.grainEnabled = grainEnabled
            self.grainStrength = grainStrength
            self.grainSize = grainSize
            self.halationEnabled = halationEnabled
            self.halationStrength = halationStrength
            self.halationRadius = halationRadius
            self.sharpnessAcutance = sharpnessAcutance
            self.rendererContrast = rendererContrast
            self.rendererSaturation = rendererSaturation
            self.outputColourSpace = outputColourSpace
            self.outputBitDepth = outputBitDepth
            self.layerRGBToLayerMatrix = layerRGBToLayerMatrix
            self.characteristicCurveToes = characteristicCurveToes
            self.characteristicCurveGammas = characteristicCurveGammas
            self.characteristicCurveShoulders = characteristicCurveShoulders
        }

        package init(recipe: FilmRecipe) {
            displayName = recipe.displayName
            manufacturer = recipe.manufacturer
            summary = recipe.summary
            stockBoxSpeedIso = Double(recipe.stock.boxSpeedIso)
            exposureBoxSpeedIso = Double(recipe.exposure.boxSpeedIso)
            exposedAtIso = Double(recipe.exposure.exposedAtIso)
            exposureCompensationEv = recipe.exposure.exposureCompensationEv
            captureColourTemperatureK = Double(recipe.captureConditions.colourTemperatureK)
            captureFilterType = recipe.captureConditions.filter.type
            captureFilterStrength = recipe.captureConditions.filter.strength
            colourSaturation = recipe.colourModel.saturation ?? 1
            colourWarmth = recipe.colourModel.warmth ?? 0
            processPushPullStops = recipe.process.pushPullStops
            processContrastMultiplier = recipe.process.contrastMultiplier
            processGrainMultiplier = recipe.process.grainMultiplier
            grainEnabled = recipe.grain.enabled
            grainStrength = recipe.grain.strength
            grainSize = recipe.grain.size
            halationEnabled = recipe.halation.enabled
            halationStrength = recipe.halation.strength
            halationRadius = recipe.halation.radius
            sharpnessAcutance = recipe.sharpness.acutance
            rendererContrast = recipe.renderer.contrast
            rendererSaturation = recipe.renderer.saturation
            outputColourSpace = recipe.output.colourSpace
            outputBitDepth = Double(recipe.output.bitDepth)
            layerRGBToLayerMatrix = recipe.layerModel.rgbToLayerMatrix
            characteristicCurveToes = recipe.characteristicCurves.channels.mapValues(\.toe)
            characteristicCurveGammas = recipe.characteristicCurves.channels.mapValues(\.gamma)
            characteristicCurveShoulders = recipe.characteristicCurves.channels.mapValues(\.shoulder)
        }

        package func hasChanges(comparedTo recipe: FilmRecipe) -> Bool {
            displayName != recipe.displayName ||
                manufacturer != recipe.manufacturer ||
                summary != recipe.summary ||
                Int(stockBoxSpeedIso.rounded()) != recipe.stock.boxSpeedIso ||
                Int(exposureBoxSpeedIso.rounded()) != recipe.exposure.boxSpeedIso ||
                Int(exposedAtIso.rounded()) != recipe.exposure.exposedAtIso ||
                abs(exposureCompensationEv - recipe.exposure.exposureCompensationEv) > 0.001 ||
                Int(captureColourTemperatureK.rounded()) != recipe.captureConditions.colourTemperatureK ||
                trimmedCaptureFilterType() != recipe.captureConditions.filter.type ||
                abs(captureFilterStrength - recipe.captureConditions.filter.strength) > 0.001 ||
                abs(colourSaturation - (recipe.colourModel.saturation ?? 1)) > 0.001 ||
                abs(colourWarmth - (recipe.colourModel.warmth ?? 0)) > 0.001 ||
                abs(processPushPullStops - recipe.process.pushPullStops) > 0.001 ||
                abs(processContrastMultiplier - recipe.process.contrastMultiplier) > 0.001 ||
                abs(processGrainMultiplier - recipe.process.grainMultiplier) > 0.001 ||
                grainEnabled != recipe.grain.enabled ||
                abs(grainStrength - recipe.grain.strength) > 0.001 ||
                abs(grainSize - recipe.grain.size) > 0.001 ||
                halationEnabled != recipe.halation.enabled ||
                abs(halationStrength - recipe.halation.strength) > 0.001 ||
                abs(halationRadius - recipe.halation.radius) > 0.001 ||
                abs(sharpnessAcutance - recipe.sharpness.acutance) > 0.001 ||
                abs(rendererContrast - recipe.renderer.contrast) > 0.001 ||
                abs(rendererSaturation - recipe.renderer.saturation) > 0.001 ||
                trimmedOutputColourSpace() != recipe.output.colourSpace ||
                Int(outputBitDepth.rounded()) != recipe.output.bitDepth ||
                layerRGBToLayerMatrix != recipe.layerModel.rgbToLayerMatrix ||
                characteristicCurveToes != recipe.characteristicCurves.channels.mapValues(\.toe) ||
                characteristicCurveGammas != recipe.characteristicCurves.channels.mapValues(\.gamma) ||
                characteristicCurveShoulders != recipe.characteristicCurves.channels.mapValues(\.shoulder)
        }

        fileprivate func trimmedDisplayName() -> String {
            displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        fileprivate func trimmedManufacturer() -> String {
            manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        fileprivate func trimmedSummary() -> String {
            summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        fileprivate func trimmedCaptureFilterType() -> String {
            captureFilterType.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        fileprivate func trimmedOutputColourSpace() -> String {
            outputColourSpace.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    package enum RecipeImportStatus: Equatable {
        case imported(name: String)
        case failed(name: String, issues: [RecipeValidationIssue])

        package var title: String {
            switch self {
            case .imported:
                return "Recipe imported"
            case .failed:
                return "Recipe import failed"
            }
        }

        package var message: String {
            switch self {
            case .imported(let name):
                return "\(name) is ready to edit and export."
            case .failed(let name, let issues):
                let issueText = issues.map(\.message).joined(separator: "\n")
                return "\(name) could not be imported.\n\(issueText)"
            }
        }
    }

    @Published package private(set) var project = FilmProject()
    @Published package private(set) var recipes: [FilmRecipe] = []
    @Published package private(set) var editableRecipeIDs: Set<String> = []
    @Published package private(set) var recipeImportStatus: RecipeImportStatus?
    @Published package var recipeDraft = RecipeDraft() {
        didSet {
            invalidateRecipeValidationCache()
        }
    }
    @Published package var selectedRecipeID: String? {
        didSet {
            syncRecipeDraftWithSelection()
            guard !isApplyingEditSnapshot, !suppressPreviewUpdates else {
                return
            }
            recordCurrentEditSnapshot(note: "Changed recipe")
            renderPreviewIfNeeded()
        }
    }

    @Published package private(set) var importedImageName: String?
    @Published package private(set) var originalPreviewImage: NSImage?
    @Published package private(set) var editedPreviewImage: NSImage?
    @Published package private(set) var histogramSummary: HistogramSummary?
    @Published package private(set) var pixelSample: PixelSample?
    @Published package private(set) var isRenderingPreview = false
    @Published package private(set) var previewRenderProgress = 0.0
    @Published package private(set) var previewRenderStatus = "Idle"
    @Published package private(set) var previewCacheHitCount = 0
    @Published package var isImporting = false
    @Published package var isImportingRecipe = false
    @Published package var isImportingCalibration = false
    @Published package var isOpeningProject = false
    @Published package var isRelinkingProjectPhoto = false
    @Published package var errorMessage: String?
    @Published package private(set) var projectItemNeedingRelinkID: UUID?
    private var pendingRelinkProjectItemID: UUID?

    @Published package var comparisonMode = PreviewComparisonMode.edited {
        didSet {
            guard oldValue != comparisonMode else {
                return
            }
            splitPositionInImage = nil
            clearPixelSample(cancelPendingTask: true)
        }
    }
    @Published package var previewZoom = 1.0
    @Published package var previewPanX = 0.0
    @Published package var previewPanY = 0.0
    @Published package var loupeEnabled = false
    @Published package var loupeZoom = 2.0
    @Published package var loupePlacement = LoupePlacement.nearSampler
    @Published package var splitPosition = 0.5 {
        didSet {
            guard abs(oldValue - splitPosition) > 0.0001 else {
                return
            }
            clearPixelSample(cancelPendingTask: true)
        }
    }
    @Published package private(set) var samplerX = 0.5
    @Published package private(set) var samplerY = 0.5
    /// The split divider converted into image-normalized X by the preview
    /// view; `splitPosition` itself is pane-normalized and only matches the
    /// sampler's image space when the image exactly fills the pane.
    @Published package private(set) var splitPositionInImage: Double?
    @Published package var histogramChannelMode = HistogramChannelMode.all
    @Published package var histogramClipWarningThreshold = 0.02
    @Published package var exportSettings = ExportSettings.defaults {
        didSet { handleExportSettingsChanged() }
    }
    @Published package var exportPresets = ExportPreset.defaults
    @Published package var selectedExportPresetID: UUID? {
        didSet {
            // Selecting a preset applies it; programmatic restoration (e.g.
            // opening a project) runs under suppressSettingsUpdates so it
            // cannot clobber the project's saved export settings.
            guard !suppressSettingsUpdates, oldValue != selectedExportPresetID else {
                return
            }
            applySelectedExportPreset()
        }
    }
    @Published package var exportPresetDraftName = "Custom Preset"
    @Published package var colorManagementSettings = ColorManagementSettings.defaults {
        didSet { handleColorManagementChanged() }
    }
    @Published package private(set) var calibrationDataStatus = CalibrationDataStatus.descriptiveOnly
    @Published package private(set) var batchExportState = BatchExportState()
    @Published package var selectedLocalAdjustmentID: UUID?
    @Published package var localMaskEditingEnabled = false
    @Published package var localAdjustments: [LocalAdjustmentLayer] = [] {
        didSet {
            guard !suppressPreviewUpdates else {
                return
            }
            recordCurrentEditSnapshot(note: "Changed local adjustments")
            updateCurrentProjectItem()
            renderPreviewIfNeeded()
        }
    }
    @Published package private(set) var editHistory: [EditSnapshot] = []
    @Published package private(set) var editHistoryIndex: Int?

    package var showOriginal: Bool {
        get { comparisonMode == .original }
        set { comparisonMode = newValue ? .original : .edited }
    }

    @Published package var intensity = RenderAdjustments.defaults.intensity {
        didSet { handleAdjustmentChanged(note: "Changed intensity") }
    }
    @Published package var exposureTrim = RenderAdjustments.defaults.exposureTrim {
        didSet { handleAdjustmentChanged(note: "Changed exposure") }
    }
    @Published package var contrastTrim = RenderAdjustments.defaults.contrastTrim {
        didSet { handleAdjustmentChanged(note: "Changed contrast") }
    }
    @Published package var saturationTrim = RenderAdjustments.defaults.saturationTrim {
        didSet { handleAdjustmentChanged(note: "Changed saturation") }
    }
    @Published package var grainEnabled = RenderAdjustments.defaults.grainEnabled {
        didSet { handleAdjustmentChanged(note: "Changed grain") }
    }

    private let recipeStore: RecipeStore
    private let projectStore: ProjectStore
    private let imageProcessor: ImageProcessor
    private let calibrationAssetParser: CalibrationAssetParser
    private let rendersSynchronouslyForTesting: Bool
    private let presentsPhotoImportPanel: Bool
    private var sourceImage: CIImage?
    private var sourceURL: URL?
    private var suppressPreviewUpdates = false
    private var isApplyingEditSnapshot = false
    private var previewRenderTask: Task<Void, Never>?
    private var previewRenderGeneration = 0
    private var pixelSampleTask: Task<Void, Never>?
    private var pixelSampleGeneration = 0
    private var previewRenderCache: [PreviewRenderCacheKey: PreviewRenderResult] = [:]
    private var previewRenderCacheAccessOrder: [PreviewRenderCacheKey] = []
    private let previewRenderCacheLimit = 8
    private let previewRenderCacheByteLimit = 256 * 1024 * 1024
    private var suppressSettingsUpdates = false
    private var cancelBatchExportRequested = false
    private var batchExportTask: Task<Void, Never>?
    private var activeLocalMaskPointIndex: Int?
    private var isAdjustmentGestureActive = false
    private var activeGestureSnapshotID: UUID?
    private let editHistoryLimit = 200
    private var hasLoadedBundledRecipes = false
    private var batchExportGeneration = 0

    package enum EditorStoreError: LocalizedError {
        case missingRecipe(itemName: String)

        package var errorDescription: String? {
            switch self {
            case .missingRecipe(let itemName):
                return "No matching recipe is available to render \(itemName)."
            }
        }
    }

    public init(recipeStore: RecipeStore) {
        self.recipeStore = recipeStore
        projectStore = ProjectStore()
        imageProcessor = ImageProcessor()
        calibrationAssetParser = CalibrationAssetParser()
        rendersSynchronouslyForTesting = false
        presentsPhotoImportPanel = true
    }

    package init(
        recipeStore: RecipeStore,
        projectStore: ProjectStore = ProjectStore(),
        imageProcessor: ImageProcessor,
        rendersSynchronouslyForTesting: Bool = true,
        presentsPhotoImportPanel: Bool = false
    ) {
        self.recipeStore = recipeStore
        self.projectStore = projectStore
        self.imageProcessor = imageProcessor
        calibrationAssetParser = CalibrationAssetParser()
        self.rendersSynchronouslyForTesting = rendersSynchronouslyForTesting
        self.presentsPhotoImportPanel = presentsPhotoImportPanel
    }

    package var selectedRecipe: FilmRecipe? {
        recipes.first { $0.id == selectedRecipeID }
    }

    package var selectedRecipeIsEditable: Bool {
        guard let selectedRecipeID else {
            return false
        }
        return editableRecipeIDs.contains(selectedRecipeID)
    }

    // Validation builds full recipe copies; cache the results because every
    // inspector body evaluation reads these several times.
    private var cachedRecipeDraftIssues: [RecipeValidationIssue]?
    private var cachedSelectedRecipeIssues: [RecipeValidationIssue]?

    private func invalidateRecipeValidationCache() {
        cachedRecipeDraftIssues = nil
        cachedSelectedRecipeIssues = nil
    }

    package var recipeDraftIssues: [RecipeValidationIssue] {
        if let cachedRecipeDraftIssues {
            return cachedRecipeDraftIssues
        }
        let issues = computeRecipeDraftIssues()
        cachedRecipeDraftIssues = issues
        return issues
    }

    private func computeRecipeDraftIssues() -> [RecipeValidationIssue] {
        guard let selectedRecipe else {
            return []
        }

        let draftRecipe = selectedRecipe.replacingMetadata(
            displayName: recipeDraft.trimmedDisplayName(),
            manufacturer: recipeDraft.trimmedManufacturer(),
            summary: recipeDraft.trimmedSummary()
        ).replacingEditableSettings(
            stockBoxSpeedIso: Int(recipeDraft.stockBoxSpeedIso.rounded()),
            exposureBoxSpeedIso: Int(recipeDraft.exposureBoxSpeedIso.rounded()),
            exposedAtIso: Int(recipeDraft.exposedAtIso.rounded()),
            exposureCompensationEv: recipeDraft.exposureCompensationEv,
            captureColourTemperatureK: Int(recipeDraft.captureColourTemperatureK.rounded()),
            captureFilterType: recipeDraft.trimmedCaptureFilterType(),
            captureFilterStrength: recipeDraft.captureFilterStrength,
            colourSaturation: recipeDraft.colourSaturation,
            colourWarmth: recipeDraft.colourWarmth,
            processPushPullStops: recipeDraft.processPushPullStops,
            processContrastMultiplier: recipeDraft.processContrastMultiplier,
            processGrainMultiplier: recipeDraft.processGrainMultiplier,
            grainEnabled: recipeDraft.grainEnabled,
            grainStrength: recipeDraft.grainStrength,
            grainSize: recipeDraft.grainSize,
            halationEnabled: recipeDraft.halationEnabled,
            halationStrength: recipeDraft.halationStrength,
            halationRadius: recipeDraft.halationRadius,
            sharpnessAcutance: recipeDraft.sharpnessAcutance,
            rendererContrast: recipeDraft.rendererContrast,
            rendererSaturation: recipeDraft.rendererSaturation,
            outputColourSpace: recipeDraft.trimmedOutputColourSpace(),
            outputBitDepth: Int(recipeDraft.outputBitDepth.rounded()),
            layerRGBToLayerMatrix: recipeDraft.layerRGBToLayerMatrix,
            characteristicCurveToes: recipeDraft.characteristicCurveToes,
            characteristicCurveGammas: recipeDraft.characteristicCurveGammas,
            characteristicCurveShoulders: recipeDraft.characteristicCurveShoulders
        )
        return FilmRecipeValidator.issues(for: draftRecipe)
    }

    package var selectedRecipeValidationIssues: [RecipeValidationIssue] {
        if let cachedSelectedRecipeIssues {
            return cachedSelectedRecipeIssues
        }
        guard let selectedRecipe else {
            return []
        }
        let issues = FilmRecipeValidator.issues(for: selectedRecipe)
        cachedSelectedRecipeIssues = issues
        return issues
    }

    package var previewRenderCacheSize: Int {
        previewRenderCache.count
    }

    package var canApplyRecipeDraft: Bool {
        guard let selectedRecipe, selectedRecipeIsEditable else {
            return false
        }
        return recipeDraft.hasChanges(comparedTo: selectedRecipe) && recipeDraftIssues.isEmpty
    }

    package var displayedPreviewImage: NSImage? {
        comparisonMode == .original ? originalPreviewImage : editedPreviewImage
    }

    package var hasImportedImage: Bool {
        sourceImage != nil
    }

    public var canExport: Bool {
        sourceImage != nil && selectedRecipe != nil
    }

    public var canExportCurrentSettings: Bool {
        canExport && exportNamingTemplateIssues.isEmpty
    }

    public var canBatchExport: Bool {
        !project.items.isEmpty && !recipes.isEmpty && !batchExportState.isExporting && exportNamingTemplateIssues.isEmpty
    }

    package var canSaveExportPreset: Bool {
        exportNamingTemplateIssues.isEmpty && exportPresetNameIssues.isEmpty
    }

    package var exportNamingTemplateIssues: [String] {
        Self.exportNamingTemplateIssues(for: exportSettings.namingTemplate)
    }

    package var exportPresetNameIssues: [String] {
        let trimmedName = exportPresetDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "Custom Preset" : trimmedName
        let duplicate = exportPresets.contains { preset in
            preset.id != selectedExportPresetID && preset.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        return duplicate ? ["A preset named \(name) already exists."] : []
    }

    package var selectedOutputProfile: ColorOutputProfile {
        ColorOutputProfile(rawProfileName: colorManagementSettings.outputColorSpace)
    }

    package var histogramClipWarningText: String? {
        guard let histogramSummary else {
            return nil
        }

        return Self.histogramClipWarningText(
            for: histogramSummary,
            threshold: histogramClipWarningThreshold
        )
    }

    private var pixelSampleUsesOriginalImage: Bool {
        switch comparisonMode {
        case .original:
            return true
        case .split:
            return samplerX <= (splitPositionInImage ?? splitPosition)
        case .edited:
            return false
        }
    }

    package func updateSplitDividerImagePosition(_ value: Double?) {
        splitPositionInImage = value
    }

    nonisolated package static func histogramClipWarningText(
        for summary: HistogramSummary,
        threshold: Double
    ) -> String? {
        let safeThreshold = min(max(threshold, 0), 1)
        let shadowPercent = Int((summary.shadowClippingRatio * 100).rounded())
        let highlightPercent = Int((summary.highlightClippingRatio * 100).rounded())
        if summary.shadowClippingRatio >= safeThreshold,
           summary.highlightClippingRatio >= safeThreshold {
            return "Shadow \(shadowPercent)% and highlight \(highlightPercent)% clipping exceed threshold."
        }
        if summary.shadowClippingRatio >= safeThreshold {
            return "Shadow \(shadowPercent)% clipping exceeds threshold."
        }
        if summary.highlightClippingRatio >= safeThreshold {
            return "Highlight \(highlightPercent)% clipping exceeds threshold."
        }
        return nil
    }

    package var exportFileNamePreview: String {
        let item = FilmProjectItem(
            displayName: importedImageName ?? "Sample Photo.png",
            originalURLPath: nil,
            selectedRecipeID: selectedRecipeID,
            adjustments: currentAdjustments
        )
        let recipe = selectedRecipe ?? recipes.first
        guard let recipe else {
            return "sample-photo-edited.\(exportSettings.fileFormat.preferredPathExtension)"
        }
        return Self.exportFileName(item: item, recipe: recipe, settings: exportSettings)
    }

    package var canUndoEdit: Bool {
        guard let editHistoryIndex else {
            return false
        }
        return editHistoryIndex > 0
    }

    package var canRedoEdit: Bool {
        guard let editHistoryIndex else {
            return false
        }
        return editHistoryIndex < editHistory.count - 1
    }

    package var canResetPreviewView: Bool {
        abs(previewZoom - 1.0) > 0.001 ||
            abs(previewPanX) > 0.001 ||
            abs(previewPanY) > 0.001 ||
            loupeEnabled
    }

    package var canEditLocalMaskOnPreview: Bool {
        hasImportedImage && selectedLocalAdjustmentID != nil && !localAdjustments.isEmpty
    }

    package var currentAdjustments: RenderAdjustments {
        RenderAdjustments(
            intensity: intensity,
            exposureTrim: exposureTrim,
            contrastTrim: contrastTrim,
            saturationTrim: saturationTrim,
            grainEnabled: grainEnabled
        )
    }

    public func loadRecipesIfNeeded() {
        guard !hasLoadedBundledRecipes else {
            return
        }

        do {
            let bundled = try recipeStore.loadRecipes()
            hasLoadedBundledRecipes = true
            // Keep custom recipes already restored from an opened project.
            var merged = recipes
            for recipe in bundled where !merged.contains(where: { $0.id == recipe.id }) {
                merged.append(recipe)
            }
            recipes = merged.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            if selectedRecipeID == nil {
                suppressPreviewUpdates = true
                selectedRecipeID = recipes.first?.id
                suppressPreviewUpdates = false
            }
            if editHistory.isEmpty {
                recordCurrentEditSnapshot(note: "Initial recipe")
            }
            renderPreviewIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func beginImport() {
        guard presentsPhotoImportPanel else {
            isImporting = true
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Import Photos"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true

        panel.begin { [weak self] response in
            guard response == .OK else {
                return
            }

            let urls = panel.urls
            Task { @MainActor in
                self?.importPhotos(from: urls)
            }
        }
    }

    public func beginRecipeImport() {
        isImportingRecipe = true
    }

    public func clearRecipeImportStatus() {
        recipeImportStatus = nil
    }

    public func beginCalibrationImport() {
        isImportingCalibration = true
    }

    public func beginProjectOpen() {
        isOpeningProject = true
    }

    public func beginRelinkProjectItem(id: UUID) {
        pendingRelinkProjectItemID = id
        isRelinkingProjectPhoto = true
    }

    package func handleImportResult(_ result: Result<URL, Error>) {
        isImporting = false
        switch result {
        case .success(let url):
            importPhoto(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    package func handleImportResults(_ result: Result<[URL], Error>) {
        isImporting = false
        switch result {
        case .success(let urls):
            importPhotos(from: urls)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    package func handleRecipeImportResults(_ result: Result<[URL], Error>) {
        isImportingRecipe = false
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }

            importRecipe(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    package func handleCalibrationImportResults(_ result: Result<[URL], Error>) {
        isImportingCalibration = false
        switch result {
        case .success(let urls):
            importCalibrationAssets(from: urls)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    package func handleProjectOpenResults(_ result: Result<[URL], Error>) {
        isOpeningProject = false
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }

            openProject(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    package func handleProjectRelinkResults(_ result: Result<[URL], Error>) {
        isRelinkingProjectPhoto = false
        switch result {
        case .success(let urls):
            guard let url = urls.first,
                  let pendingRelinkProjectItemID
            else {
                return
            }

            relinkProjectItem(id: pendingRelinkProjectItemID, to: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
        pendingRelinkProjectItemID = nil
    }

    public func resetControls() {
        suppressPreviewUpdates = true
        intensity = RenderAdjustments.defaults.intensity
        exposureTrim = RenderAdjustments.defaults.exposureTrim
        contrastTrim = RenderAdjustments.defaults.contrastTrim
        saturationTrim = RenderAdjustments.defaults.saturationTrim
        grainEnabled = RenderAdjustments.defaults.grainEnabled
        comparisonMode = .edited
        resetPreviewView()
        suppressPreviewUpdates = false
        recordCurrentEditSnapshot(note: "Reset adjustments")
        renderPreviewIfNeeded()
    }

    public func resetPreviewView() {
        previewZoom = 1.0
        previewPanX = 0
        previewPanY = 0
        loupeEnabled = false
    }

    public func panPreview(deltaX: Double, deltaY: Double) {
        guard previewZoom > 1.0 else {
            previewPanX = 0
            previewPanY = 0
            return
        }

        setPreviewPan(x: previewPanX + deltaX, y: previewPanY + deltaY)
    }

    public func setPreviewPan(x: Double, y: Double) {
        guard previewZoom > 1.0 else {
            previewPanX = 0
            previewPanY = 0
            return
        }

        let limit = previewPanLimit()
        previewPanX = min(max(x, -limit), limit)
        previewPanY = min(max(y, -limit), limit)
    }

    public func undoEdit() {
        guard let editHistoryIndex, editHistoryIndex > 0 else {
            return
        }

        applyEditSnapshot(at: editHistoryIndex - 1)
    }

    public func redoEdit() {
        guard let editHistoryIndex, editHistoryIndex < editHistory.count - 1 else {
            return
        }

        applyEditSnapshot(at: editHistoryIndex + 1)
    }

    public func captureVariant(note: String = "Captured variant") {
        recordCurrentEditSnapshot(note: note, force: true, pinned: true)
    }

    /// Coalesces continuous input (slider drags, mask painting) into a single
    /// history snapshot instead of one per tick.
    package func setAdjustmentGestureActive(_ active: Bool) {
        if !active {
            activeGestureSnapshotID = nil
        }
        isAdjustmentGestureActive = active
    }

    public func restoreVariant(id: UUID) {
        guard let index = editHistory.firstIndex(where: { $0.id == id }) else {
            return
        }

        applyEditSnapshot(at: index)
    }

    public func renameVariant(id: UUID, note: String) {
        guard let index = editHistory.firstIndex(where: { $0.id == id }) else {
            return
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        editHistory[index].note = trimmedNote.isEmpty ? "Untitled variant" : trimmedNote
        editHistory[index].isPinned = true
        updateCurrentProjectItem()
    }

    /// Stores the note exactly as typed; normalization happens on commit via
    /// `finalizeVariantNote` so typing isn't fought character by character.
    public func setVariantNote(id: UUID, note: String) {
        guard let index = editHistory.firstIndex(where: { $0.id == id }) else {
            return
        }

        editHistory[index].note = note
        editHistory[index].isPinned = true
        updateCurrentProjectItem()
    }

    public func finalizeVariantNote(id: UUID) {
        guard let index = editHistory.firstIndex(where: { $0.id == id }) else {
            return
        }

        let trimmedNote = editHistory[index].note.trimmingCharacters(in: .whitespacesAndNewlines)
        editHistory[index].note = trimmedNote.isEmpty ? "Untitled variant" : trimmedNote
        updateCurrentProjectItem()
    }

    public func duplicateVariant(id: UUID) {
        guard let index = editHistory.firstIndex(where: { $0.id == id }) else {
            return
        }

        let source = editHistory[index]
        let duplicate = EditSnapshot(
            recipeID: source.recipeID,
            adjustments: source.adjustments,
            localAdjustments: source.localAdjustments,
            note: uniqueVariantNote(base: "\(source.note) Copy"),
            isPinned: true
        )
        editHistory.insert(duplicate, at: index + 1)
        editHistoryIndex = index + 1
        updateCurrentProjectItem()
        applyEditSnapshot(at: index + 1)
    }

    public func deleteVariant(id: UUID) {
        guard editHistory.count > 1,
              let index = editHistory.firstIndex(where: { $0.id == id })
        else {
            return
        }

        editHistory.remove(at: index)
        let nextIndex: Int
        if let editHistoryIndex, editHistoryIndex > index {
            nextIndex = editHistoryIndex - 1
        } else if let editHistoryIndex, editHistoryIndex < editHistory.count {
            nextIndex = editHistoryIndex
        } else {
            nextIndex = max(0, editHistory.count - 1)
        }
        applyEditSnapshot(at: nextIndex)
    }

    public func duplicateSelectedRecipeForEditing() {
        guard let selectedRecipe else {
            return
        }

        let duplicateID = uniqueRecipeID(base: "\(selectedRecipe.id)-custom")
        let duplicateName = uniqueRecipeDisplayName(base: "\(selectedRecipe.name) Copy")
        let duplicate = selectedRecipe.replacingMetadata(
            profileId: duplicateID,
            displayName: duplicateName
        )

        recipes.append(duplicate)
        recipes.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        editableRecipeIDs.insert(duplicate.id)
        selectedRecipeID = duplicate.id
        recipeImportStatus = .imported(name: duplicate.name)
    }

    public func applyRecipeDraft() {
        guard let selectedRecipe, selectedRecipeIsEditable else {
            return
        }

        let updatedRecipe = selectedRecipe.replacingMetadata(
            displayName: recipeDraft.trimmedDisplayName(),
            manufacturer: recipeDraft.trimmedManufacturer(),
            summary: recipeDraft.trimmedSummary()
        ).replacingEditableSettings(
            stockBoxSpeedIso: Int(recipeDraft.stockBoxSpeedIso.rounded()),
            exposureBoxSpeedIso: Int(recipeDraft.exposureBoxSpeedIso.rounded()),
            exposedAtIso: Int(recipeDraft.exposedAtIso.rounded()),
            exposureCompensationEv: recipeDraft.exposureCompensationEv,
            captureColourTemperatureK: Int(recipeDraft.captureColourTemperatureK.rounded()),
            captureFilterType: recipeDraft.trimmedCaptureFilterType(),
            captureFilterStrength: recipeDraft.captureFilterStrength,
            colourSaturation: recipeDraft.colourSaturation,
            colourWarmth: recipeDraft.colourWarmth,
            processPushPullStops: recipeDraft.processPushPullStops,
            processContrastMultiplier: recipeDraft.processContrastMultiplier,
            processGrainMultiplier: recipeDraft.processGrainMultiplier,
            grainEnabled: recipeDraft.grainEnabled,
            grainStrength: recipeDraft.grainStrength,
            grainSize: recipeDraft.grainSize,
            halationEnabled: recipeDraft.halationEnabled,
            halationStrength: recipeDraft.halationStrength,
            halationRadius: recipeDraft.halationRadius,
            sharpnessAcutance: recipeDraft.sharpnessAcutance,
            rendererContrast: recipeDraft.rendererContrast,
            rendererSaturation: recipeDraft.rendererSaturation,
            outputColourSpace: recipeDraft.trimmedOutputColourSpace(),
            outputBitDepth: Int(recipeDraft.outputBitDepth.rounded()),
            layerRGBToLayerMatrix: recipeDraft.layerRGBToLayerMatrix,
            characteristicCurveToes: recipeDraft.characteristicCurveToes,
            characteristicCurveGammas: recipeDraft.characteristicCurveGammas,
            characteristicCurveShoulders: recipeDraft.characteristicCurveShoulders
        )

        let issues = FilmRecipeValidator.issues(for: updatedRecipe)
        guard issues.isEmpty else {
            recipeImportStatus = .failed(name: updatedRecipe.name, issues: issues)
            return
        }

        replaceRecipe(updatedRecipe)
        recipeImportStatus = .imported(name: updatedRecipe.name)
        recordCurrentEditSnapshot(note: "Edited recipe")
        renderPreviewIfNeeded()
    }

    public func applySelectedExportPreset() {
        guard let selectedExportPresetID,
              let preset = exportPresets.first(where: { $0.id == selectedExportPresetID })
        else {
            return
        }

        exportSettings = preset.settings
        exportPresetDraftName = preset.name
        project.exportSettings = exportSettings
        project.updatedAt = Date()
    }

    public func beginNewExportPreset() {
        selectedExportPresetID = nil
        exportPresetDraftName = uniqueExportPresetName(base: "Custom Preset")
    }

    public func saveExportPreset() {
        guard canSaveExportPreset else {
            return
        }

        let trimmedName = exportPresetDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "Custom Preset" : trimmedName

        if let selectedExportPresetID,
           let index = exportPresets.firstIndex(where: { $0.id == selectedExportPresetID }) {
            exportPresets[index].name = name
            exportPresets[index].settings = exportSettings
        } else {
            let preset = ExportPreset(name: uniqueExportPresetName(base: name), settings: exportSettings)
            exportPresets.append(preset)
            selectedExportPresetID = preset.id
        }

        syncExportPresetsToProject()
    }

    public func duplicateSelectedExportPreset() {
        let sourcePreset = selectedExportPresetID
            .flatMap { selectedID in exportPresets.first { $0.id == selectedID } } ??
            ExportPreset(name: "Current Settings", settings: exportSettings)
        let preset = ExportPreset(
            name: uniqueExportPresetName(base: "\(sourcePreset.name) Copy"),
            settings: sourcePreset.settings
        )
        exportPresets.append(preset)
        selectedExportPresetID = preset.id
        exportPresetDraftName = preset.name
        exportSettings = preset.settings
        syncExportPresetsToProject()
    }

    public func restoreDefaultExportPresets() {
        exportPresets = ExportPreset.defaults
        selectedExportPresetID = nil
        exportPresetDraftName = uniqueExportPresetName(base: "Custom Preset")
        syncExportPresetsToProject()
    }

    public func deleteSelectedExportPreset() {
        guard let selectedExportPresetID,
              exportPresets.count > 1
        else {
            return
        }

        exportPresets.removeAll { $0.id == selectedExportPresetID }
        self.selectedExportPresetID = exportPresets.first?.id
        exportPresetDraftName = exportPresets.first?.name ?? "Custom Preset"
        syncExportPresetsToProject()
    }

    public func resetRecipeDraft() {
        syncRecipeDraftWithSelection()
    }

    public func moveSampleMarker(x: Double, y: Double) {
        samplerX = clampedUnit(x)
        samplerY = clampedUnit(y)
        clearPixelSample()
    }

    public func schedulePreviewPixelSample(x: Double, y: Double) {
        clearPixelSample(cancelPendingTask: true)
        moveSampleMarker(x: x, y: y)
        pixelSampleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else {
                return
            }
            guard let self else {
                return
            }
            self.samplePreviewPixel(x: self.samplerX, y: self.samplerY)
        }
    }

    public func samplePreviewPixel(x: Double = 0.5, y: Double = 0.5) {
        moveSampleMarker(x: x, y: y)

        guard let sourceImage, let selectedRecipe else {
            return
        }

        let usesOriginal = pixelSampleUsesOriginalImage
        let adjustments = currentAdjustments
        let localAdjustments = self.localAdjustments
        let calibration = calibrationDataStatus
        let sampleX = samplerX
        let sampleY = samplerY

        if rendersSynchronouslyForTesting {
            do {
                pixelSample = try Self.computePixelSample(
                    imageProcessor: imageProcessor,
                    sourceImage: sourceImage,
                    recipe: selectedRecipe,
                    usesOriginal: usesOriginal,
                    adjustments: adjustments,
                    localAdjustments: localAdjustments,
                    calibration: calibration,
                    x: sampleX,
                    y: sampleY
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        // Sampling the edited side renders the full pipeline (and rasterizes
        // any brush masks); keep that off the main actor so clicks don't
        // stall the UI.
        pixelSampleGeneration += 1
        let generation = pixelSampleGeneration
        Task.detached(priority: .userInitiated) { [imageProcessor] in
            do {
                let sample = try Self.computePixelSample(
                    imageProcessor: imageProcessor,
                    sourceImage: sourceImage,
                    recipe: selectedRecipe,
                    usesOriginal: usesOriginal,
                    adjustments: adjustments,
                    localAdjustments: localAdjustments,
                    calibration: calibration,
                    x: sampleX,
                    y: sampleY
                )
                await MainActor.run {
                    guard generation == self.pixelSampleGeneration else {
                        return
                    }
                    self.pixelSample = sample
                }
            } catch {
                await MainActor.run {
                    guard generation == self.pixelSampleGeneration else {
                        return
                    }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    nonisolated private static func computePixelSample(
        imageProcessor: ImageProcessor,
        sourceImage: CIImage,
        recipe: FilmRecipe,
        usesOriginal: Bool,
        adjustments: RenderAdjustments,
        localAdjustments: [LocalAdjustmentLayer],
        calibration: CalibrationDataStatus,
        x: Double,
        y: Double
    ) throws -> PixelSample {
        let sampleSource: CIImage
        if usesOriginal {
            sampleSource = sourceImage
        } else {
            sampleSource = imageProcessor.renderedPreviewSource(
                from: sourceImage,
                recipe: recipe,
                adjustments: adjustments,
                localAdjustments: localAdjustments,
                calibration: calibration
            )
        }
        return try imageProcessor.samplePixel(
            from: sampleSource,
            normalisedX: x,
            normalisedY: y
        )
    }

    public func addLocalAdjustment() {
        let layer = LocalAdjustmentLayer(
            name: uniqueLocalAdjustmentName(base: "Local Layer"),
            exposureEV: 0.25,
            contrast: 0.05
        )
        localAdjustments.append(layer)
        selectedLocalAdjustmentID = layer.id
    }

    public func removeLocalAdjustments() {
        localAdjustments.removeAll()
        selectedLocalAdjustmentID = nil
        localMaskEditingEnabled = false
    }

    public func removeSelectedLocalAdjustment() {
        guard let selectedLocalAdjustmentID else {
            removeLocalAdjustments()
            return
        }

        localAdjustments.removeAll { $0.id == selectedLocalAdjustmentID }
        self.selectedLocalAdjustmentID = localAdjustments.first?.id
        localMaskEditingEnabled = self.selectedLocalAdjustmentID != nil
    }

    package func beginLocalMaskEditAtPreviewPoint(x: Double, y: Double) {
        guard let index = selectedLocalAdjustmentIndex() else {
            return
        }

        setAdjustmentGestureActive(true)
        let point = NormalizedMaskPoint(x: clampedUnit(x), y: clampedUnit(y))
        switch localAdjustments[index].mask {
        case .radial, .linear:
            localAdjustments[index].centerX = point.x
            localAdjustments[index].centerY = point.y
            activeLocalMaskPointIndex = nil
        case .brush:
            localAdjustments[index].pathPoints = [point]
            activeLocalMaskPointIndex = 0
        case .path:
            if localAdjustments[index].pathPoints.isEmpty {
                localAdjustments[index].pathPoints = LocalAdjustmentLayer.defaultPathPoints
            }
            activeLocalMaskPointIndex = nearestPathPointIndex(to: point, in: localAdjustments[index])
            updateActiveLocalMaskPathPoint(point, layerIndex: index)
        }
    }

    package func updateLocalMaskEditAtPreviewPoint(x: Double, y: Double) {
        guard let index = selectedLocalAdjustmentIndex() else {
            return
        }

        let point = NormalizedMaskPoint(x: clampedUnit(x), y: clampedUnit(y))
        switch localAdjustments[index].mask {
        case .radial, .linear:
            localAdjustments[index].centerX = point.x
            localAdjustments[index].centerY = point.y
        case .brush:
            appendBrushPointIfNeeded(point, layerIndex: index)
        case .path:
            updateActiveLocalMaskPathPoint(point, layerIndex: index)
        }
    }

    package func endLocalMaskEditAtPreviewPoint() {
        activeLocalMaskPointIndex = nil
        setAdjustmentGestureActive(false)
    }

    public func cancelBatchExport() {
        cancelBatchExportRequested = true
        batchExportTask?.cancel()
    }

    public func saveProject() {
        let panel = NSSavePanel()
        panel.title = "Save Film Chef Project"
        panel.allowedContentTypes = [.filmChefProject]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(project.name).filmchef"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            Task { @MainActor in
                self?.writeProject(to: url)
            }
        }
    }

    public func selectProjectItem(id: UUID) {
        updateCurrentProjectItem()

        guard let item = project.items.first(where: { $0.id == id }) else {
            return
        }

        project.selectedItemID = id
        applyProjectItem(item)
    }

    public func exportSelectedRecipe() {
        guard let selectedRecipe else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Film Recipe"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(selectedRecipe.id).json"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            Task { @MainActor in
                self?.writeRecipe(selectedRecipe, to: url)
            }
        }
    }

    public func exportEditedPhoto() {
        guard canExportCurrentSettings else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Edited Photo"
        panel.allowedContentTypes = [.jpeg, .png, .tiff]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedExportFileName()

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            Task { @MainActor in
                self?.writeExport(to: url)
            }
        }
    }

    public func exportProjectPhotos() {
        guard canBatchExport else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Export Project Photos"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            Task { @MainActor in
                self?.startProjectExportTask(to: url)
            }
        }
    }

    package func importPhotoForTesting(from url: URL) {
        importPhoto(from: url)
    }

    package func exportEditedPhotoForTesting(to url: URL) {
        writeExport(to: url)
    }

    package func exportProjectPhotosForTesting(to directory: URL) {
        writeProjectExports(to: directory)
    }

    package func startProjectExportTaskForTesting(to directory: URL) {
        startProjectExportTask(to: directory)
    }

    package func importRecipeForTesting(from url: URL) {
        importRecipe(from: url)
    }

    package func importCalibrationAssetsForTesting(from urls: [URL]) {
        importCalibrationAssets(from: urls)
    }

    package func openProjectForTesting(from url: URL) {
        openProject(from: url)
    }

    package func saveProjectForTesting(to url: URL) {
        writeProject(to: url)
    }

    package func relinkProjectItemForTesting(id: UUID, to url: URL) {
        relinkProjectItem(id: id, to: url)
    }

    package func exportSelectedRecipeForTesting(to url: URL) {
        guard let selectedRecipe else {
            return
        }
        writeRecipe(selectedRecipe, to: url)
    }

    package func suggestedExportFileNameForTesting() -> String {
        suggestedExportFileName()
    }

    package func triggerExportPanelForTesting() {
        exportEditedPhoto()
    }

    private func importPhoto(from url: URL) {
        importPhotos(from: [url])
    }

    private func importPhotos(from urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        var firstImportedID: UUID?
        for url in urls {
            if let itemID = importProjectItem(from: url) {
                firstImportedID = firstImportedID ?? itemID
            }
        }

        if let firstImportedID {
            selectProjectItem(id: firstImportedID)
        }
    }

    private func importProjectItem(from url: URL) -> UUID? {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try imageProcessor.validateReadableImage(at: url)
            let item = makeProjectItem(for: url)
            project.items.removeAll { $0.originalURLPath == url.path }
            project.items.append(item)
            project.items.sort {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            project.updatedAt = Date()
            return item.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func openProject(from url: URL) {
        do {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let loadedProject = try projectStore.loadProject(from: url)
            suppressSettingsUpdates = true
            project = loadedProject
            restoreCustomRecipes(loadedProject.customRecipes)
            editHistory = loadedProject.editHistory
            editHistoryIndex = loadedProject.editHistoryIndex
            exportSettings = loadedProject.exportSettings
            exportPresets = loadedProject.exportPresets.isEmpty ? ExportPreset.defaults : loadedProject.exportPresets
            selectedExportPresetID = exportPresets.first?.id
            exportPresetDraftName = exportPresets.first?.name ?? "Custom Preset"
            colorManagementSettings = loadedProject.colorManagementSettings
            calibrationDataStatus = loadedProject.calibrationDataStatus
            suppressSettingsUpdates = false

            if let selectedItem = loadedProject.items.first(where: { $0.id == loadedProject.selectedItemID }) ?? loadedProject.items.first {
                project.selectedItemID = selectedItem.id
                applyProjectItem(selectedItem)
            } else {
                project.selectedItemID = nil
                clearActiveProjectItemState()
            }
        } catch {
            suppressSettingsUpdates = false
            errorMessage = error.localizedDescription
        }
    }

    private func restoreCustomRecipes(_ customRecipes: [FilmRecipe]) {
        guard !customRecipes.isEmpty else {
            return
        }

        var validationMessages: [String] = []
        for recipe in customRecipes {
            do {
                try FilmRecipeValidator.validate(recipe)
                editableRecipeIDs.insert(recipe.id)
                replaceRecipe(recipe)
            } catch {
                validationMessages.append(error.localizedDescription)
            }
        }

        if !validationMessages.isEmpty {
            errorMessage = validationMessages.joined(separator: "\n")
        }
    }

    private func writeProject(to url: URL) {
        updateCurrentProjectItem()
        project.editHistory = editHistory
        project.editHistoryIndex = editHistoryIndex
        project.customRecipes = recipes.filter { editableRecipeIDs.contains($0.id) }
        project.exportSettings = exportSettings
        project.exportPresets = exportPresets
        project.colorManagementSettings = colorManagementSettings
        project.calibrationDataStatus = calibrationDataStatus
        project.updatedAt = Date()

        do {
            try projectStore.writeProject(project, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func relinkProjectItem(id: UUID, to url: URL) {
        guard let itemIndex = project.items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try imageProcessor.validateReadableImage(at: url)
            project.items[itemIndex].displayName = url.lastPathComponent
            project.items[itemIndex].originalURLPath = url.path
            project.items[itemIndex].originalBookmarkData = projectStore.bookmarkData(for: url)
            project.items[itemIndex].updatedAt = Date()
            project.updatedAt = Date()
            projectItemNeedingRelinkID = nil
            selectProjectItem(id: id)
        } catch {
            errorMessage = error.localizedDescription
            projectItemNeedingRelinkID = id
        }
    }

    private func importRecipe(from url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let importedRecipe = try recipeStore.loadRecipe(from: url)
            replaceRecipe(importedRecipe)
            editableRecipeIDs.insert(importedRecipe.id)
            selectedRecipeID = importedRecipe.id
            recipeImportStatus = .imported(name: importedRecipe.name)
        } catch {
            recipeImportStatus = recipeImportStatus(for: error, url: url)
            errorMessage = error.localizedDescription
        }
    }

    private func syncExportPresetsToProject() {
        project.exportPresets = exportPresets
        project.updatedAt = Date()
    }

    private func uniqueExportPresetName(base: String) -> String {
        var candidate = base
        var index = 2
        let existingNames = Set(exportPresets.map(\.name))

        while existingNames.contains(candidate) {
            candidate = "\(base) \(index)"
            index += 1
        }

        return candidate
    }

    private func uniqueVariantNote(base: String) -> String {
        var candidate = base
        var index = 2
        let existingNotes = Set(editHistory.map(\.note))

        while existingNotes.contains(candidate) {
            candidate = "\(base) \(index)"
            index += 1
        }

        return candidate
    }

    private func selectedLocalAdjustmentIndex() -> Int? {
        guard let selectedLocalAdjustmentID else {
            return nil
        }
        return localAdjustments.firstIndex { $0.id == selectedLocalAdjustmentID }
    }

    private func clearPixelSample(cancelPendingTask: Bool = false) {
        if cancelPendingTask {
            pixelSampleTask?.cancel()
            pixelSampleTask = nil
        }
        // Invalidate any in-flight async sample so it cannot land after the
        // sample was cleared.
        pixelSampleGeneration += 1
        pixelSample = nil
    }

    private func previewPanLimit() -> Double {
        max(0, (previewZoom - 1.0) * 220)
    }

    private func nearestPathPointIndex(to point: NormalizedMaskPoint, in layer: LocalAdjustmentLayer) -> Int? {
        layer.pathPoints.indices.min { lhs, rhs in
            squaredDistance(from: layer.pathPoints[lhs], to: point) < squaredDistance(from: layer.pathPoints[rhs], to: point)
        }
    }

    private func updateActiveLocalMaskPathPoint(_ point: NormalizedMaskPoint, layerIndex: Int) {
        guard let activeLocalMaskPointIndex,
              localAdjustments[layerIndex].pathPoints.indices.contains(activeLocalMaskPointIndex)
        else {
            return
        }

        localAdjustments[layerIndex].pathPoints[activeLocalMaskPointIndex] = point
    }

    private func appendBrushPointIfNeeded(_ point: NormalizedMaskPoint, layerIndex: Int) {
        guard let last = localAdjustments[layerIndex].pathPoints.last else {
            localAdjustments[layerIndex].pathPoints = [point]
            return
        }

        if squaredDistance(from: last, to: point) >= 0.0004 {
            localAdjustments[layerIndex].pathPoints.append(point)
        }
    }

    private func squaredDistance(from lhs: NormalizedMaskPoint, to rhs: NormalizedMaskPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx) + (dy * dy)
    }

    private func importCalibrationAssets(from urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        }

        do {
            let parsed = try calibrationAssetParser.parse(urls: urls)
            calibrationDataStatus = parsed
            project.calibrationDataStatus = calibrationDataStatus
            project.updatedAt = Date()
            clearPreviewCache()
            renderPreviewIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func writeRecipe(_ recipe: FilmRecipe, to url: URL) {
        do {
            try recipeStore.writeRecipe(recipe, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceRecipe(_ recipe: FilmRecipe) {
        recipes.removeAll { $0.id == recipe.id }
        recipes.append(recipe)
        recipes.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        invalidateRecipeValidationCache()
        if selectedRecipeID == recipe.id {
            syncRecipeDraftWithSelection()
        }
    }

    private func syncRecipeDraftWithSelection() {
        guard let selectedRecipe else {
            recipeDraft = RecipeDraft()
            return
        }

        let nextDraft = RecipeDraft(recipe: selectedRecipe)
        if recipeDraft != nextDraft {
            recipeDraft = nextDraft
        }
    }

    private func recipeImportStatus(for error: Error, url: URL) -> RecipeImportStatus {
        let name = url.lastPathComponent
        if case FilmRecipeValidationError.invalidRecipe(_, let issues) = error {
            return .failed(name: name, issues: issues)
        }

        return .failed(name: name, issues: [RecipeValidationIssue(error.localizedDescription)])
    }

    private func uniqueRecipeID(base: String) -> String {
        let sanitized = base
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let root = sanitized.isEmpty ? "custom-recipe" : sanitized
        var candidate = root
        var index = 2
        let existingIDs = Set(recipes.map(\.id))

        while existingIDs.contains(candidate) {
            candidate = "\(root)-\(index)"
            index += 1
        }

        return candidate
    }

    private func uniqueRecipeDisplayName(base: String) -> String {
        let root = base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Recipe" : base
        var candidate = root
        var index = 2
        let existingNames = Set(recipes.map(\.name))

        while existingNames.contains(candidate) {
            candidate = "\(root) \(index)"
            index += 1
        }

        return candidate
    }

    private func writeExport(to url: URL) {
        guard let sourceImage, let selectedRecipe else {
            return
        }

        do {
            try imageProcessor.writeRenderedImage(
                from: sourceImage,
                recipe: selectedRecipe,
                adjustments: currentAdjustments,
                to: url,
                settings: exportSettings,
                localAdjustments: localAdjustments,
                calibration: calibrationDataStatus,
                colorSettings: colorManagementSettings,
                sourceMetadataURL: sourceURL
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startProjectExportTask(to directory: URL) {
        updateCurrentProjectItem()
        let request = makeBatchExportRequest(directory: directory)
        cancelBatchExportRequested = false
        batchExportTask?.cancel()
        // A superseded run must not write progress state that now belongs to a
        // newer run, or clear the newer run's task handle.
        batchExportGeneration += 1
        let generation = batchExportGeneration
        batchExportState = BatchExportState(
            isExporting: true,
            completedCount: 0,
            totalCount: request.items.count,
            outputDirectoryPath: request.directory.path
        )

        batchExportTask = Task.detached(priority: .userInitiated) { [imageProcessor] in
            var exportedNames: [String] = []
            var failures: [BatchExportFailure] = []

            do {
                try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)

                for (index, item) in request.items.enumerated() {
                    if Task.isCancelled {
                        let cancelledState = Self.batchFinishedState(
                            request: request,
                            completedCount: index,
                            wasCancelled: true,
                            exportedNames: exportedNames,
                            failures: failures
                        )
                        await MainActor.run {
                            guard generation == self.batchExportGeneration else {
                                return
                            }
                            self.batchExportState = cancelledState
                            self.batchExportTask = nil
                        }
                        return
                    }

                    let progressState = Self.batchProgressState(
                        request: request,
                        completedCount: index,
                        currentItemName: item.displayName,
                        exportedNames: exportedNames,
                        failures: failures
                    )
                    await MainActor.run {
                        guard generation == self.batchExportGeneration else {
                            return
                        }
                        self.batchExportState = progressState
                    }

                    do {
                        let exportedURL = try Self.writeProjectExport(
                            for: item,
                            request: request,
                            imageProcessor: imageProcessor
                        )
                        exportedNames.append(exportedURL.lastPathComponent)
                    } catch {
                        failures.append(BatchExportFailure(itemName: item.displayName, message: error.localizedDescription))
                    }
                }

                let finishedState = Self.batchFinishedState(
                    request: request,
                    completedCount: request.items.count,
                    exportedNames: exportedNames,
                    failures: failures
                )
                await MainActor.run {
                    guard generation == self.batchExportGeneration else {
                        return
                    }
                    self.batchExportState = finishedState
                    if !finishedState.failures.isEmpty {
                        self.errorMessage = Self.batchFailureMessage(finishedState.failures)
                    }
                    self.batchExportTask = nil
                }
            } catch {
                await MainActor.run {
                    guard generation == self.batchExportGeneration else {
                        return
                    }
                    self.batchExportState.isExporting = false
                    self.errorMessage = error.localizedDescription
                    self.batchExportTask = nil
                }
            }
        }
    }

    private func writeProjectExports(to directory: URL) {
        updateCurrentProjectItem()
        cancelBatchExportRequested = false
        let request = makeBatchExportRequest(directory: directory)
        batchExportState = BatchExportState(
            isExporting: true,
            completedCount: 0,
            totalCount: request.items.count,
            outputDirectoryPath: request.directory.path
        )

        do {
            try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)
            var exportedNames: [String] = []
            var failures: [BatchExportFailure] = []
            for (index, item) in request.items.enumerated() {
                if cancelBatchExportRequested {
                    batchExportState = Self.batchFinishedState(
                        request: request,
                        completedCount: index,
                        wasCancelled: true,
                        exportedNames: exportedNames,
                        failures: failures
                    )
                    return
                }

                batchExportState = Self.batchProgressState(
                    request: request,
                    completedCount: index,
                    currentItemName: item.displayName,
                    exportedNames: exportedNames,
                    failures: failures
                )
                do {
                    let exportedURL = try writeProjectExport(for: item, request: request)
                    exportedNames.append(exportedURL.lastPathComponent)
                } catch {
                    failures.append(BatchExportFailure(itemName: item.displayName, message: error.localizedDescription))
                }
            }
            batchExportState = Self.batchFinishedState(
                request: request,
                completedCount: request.items.count,
                exportedNames: exportedNames,
                failures: failures
            )
            if !failures.isEmpty {
                errorMessage = Self.batchFailureMessage(failures)
            }
        } catch {
            batchExportState.isExporting = false
            errorMessage = error.localizedDescription
        }
    }

    nonisolated private static func batchProgressState(
        request: BatchExportRequest,
        completedCount: Int,
        currentItemName: String?,
        exportedNames: [String],
        failures: [BatchExportFailure]
    ) -> BatchExportState {
        BatchExportState(
            isExporting: true,
            completedCount: completedCount,
            totalCount: request.items.count,
            currentItemName: currentItemName,
            exportedFileNames: exportedNames,
            failures: failures,
            outputDirectoryPath: request.directory.path
        )
    }

    nonisolated private static func batchFinishedState(
        request: BatchExportRequest,
        completedCount: Int,
        wasCancelled: Bool = false,
        exportedNames: [String],
        failures: [BatchExportFailure]
    ) -> BatchExportState {
        BatchExportState(
            isExporting: false,
            completedCount: completedCount,
            totalCount: request.items.count,
            wasCancelled: wasCancelled,
            exportedFileNames: exportedNames,
            failures: failures,
            outputDirectoryPath: request.directory.path
        )
    }

    nonisolated private static func batchFailureMessage(_ failures: [BatchExportFailure]) -> String {
        "\(failures.count) batch export item\(failures.count == 1 ? "" : "s") failed."
    }

    private func makeBatchExportRequest(directory: URL) -> BatchExportRequest {
        BatchExportRequest(
            directory: directory,
            items: project.items,
            recipes: recipes,
            fallbackRecipeID: selectedRecipeID,
            exportSettings: exportSettings,
            calibration: calibrationDataStatus,
            colorSettings: colorManagementSettings
        )
    }

    private func writeProjectExport(for item: FilmProjectItem, request: BatchExportRequest) throws -> URL {
        try Self.writeProjectExport(for: item, request: request, imageProcessor: imageProcessor)
    }

    nonisolated private static func writeProjectExport(
        for item: FilmProjectItem,
        request: BatchExportRequest,
        imageProcessor: ImageProcessor
    ) throws -> URL {
        let sourceURL = try ProjectStore().resolvePhotoURL(for: item)
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let source = try imageProcessor.loadSourceImage(from: sourceURL, colorSettings: request.colorSettings)
        // An item whose recipe cannot be resolved is a failure, not a request
        // to silently render with whatever recipe happens to be selected.
        let resolvedRecipe: FilmRecipe?
        if let selectedID = item.selectedRecipeID {
            resolvedRecipe = request.recipes.first { $0.id == selectedID }
        } else {
            resolvedRecipe = request.recipes.first { $0.id == request.fallbackRecipeID } ?? request.recipes.first
        }
        guard let recipe = resolvedRecipe else {
            throw EditorStoreError.missingRecipe(itemName: item.displayName)
        }
        let exportURL = Self.uniqueExportURL(
            in: request.directory,
            item: item,
            recipe: recipe,
            settings: request.exportSettings
        )
        try imageProcessor.writeRenderedImage(
            from: source,
            recipe: recipe,
            adjustments: item.adjustments,
            to: exportURL,
            settings: request.exportSettings,
            localAdjustments: item.localAdjustments,
            calibration: request.calibration,
            colorSettings: request.colorSettings,
            sourceMetadataURL: sourceURL
        )
        return exportURL
    }

    private func renderPreviewIfNeeded() {
        guard !suppressPreviewUpdates,
              let sourceImage,
              let selectedRecipe
        else {
            return
        }

        clearPixelSample(cancelPendingTask: true)
        previewRenderGeneration += 1
        let generation = previewRenderGeneration
        let adjustments = currentAdjustments
        let localAdjustments = self.localAdjustments
        let calibration = calibrationDataStatus
        let cacheKey = previewCacheKey(
            sourceImage: sourceImage,
            recipe: selectedRecipe,
            adjustments: adjustments,
            localAdjustments: localAdjustments,
            calibration: calibration
        )

        if let cached = previewRenderCache[cacheKey] {
            markPreviewCacheKeyUsed(cacheKey)
            editedPreviewImage = cached.image
            histogramSummary = cached.histogram
            previewCacheHitCount += 1
            isRenderingPreview = false
            previewRenderProgress = 1.0
            clearRecipeResolutionErrorIfNeeded()
            previewRenderStatus = "Loaded cached preview"
            return
        }

        if rendersSynchronouslyForTesting {
            renderPreviewSynchronously(
                sourceImage: sourceImage,
                recipe: selectedRecipe,
                adjustments: adjustments,
                localAdjustments: localAdjustments,
                calibration: calibration,
                cacheKey: cacheKey,
                generation: generation
            )
            return
        }

        previewRenderTask?.cancel()
        isRenderingPreview = true
        previewRenderProgress = 0.15
        previewRenderStatus = "Preparing preview"
        previewRenderTask = Task { [imageProcessor] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, generation == self.previewRenderGeneration else {
                return
            }

            self.previewRenderProgress = 0.45
            self.previewRenderStatus = "Rendering look"

            do {
                // Rasterizing the preview and histogram is expensive; keep it off the main actor.
                let result = try await Task.detached(priority: .userInitiated) {
                    let renderedSource = imageProcessor.renderedPreviewSource(
                        from: sourceImage,
                        recipe: selectedRecipe,
                        adjustments: adjustments,
                        localAdjustments: localAdjustments,
                        calibration: calibration
                    )
                    let (previewImage, histogram) = try imageProcessor.makeNSImageAndHistogramSummary(from: renderedSource)
                    return PreviewRenderResult(image: previewImage, histogram: histogram)
                }.value

                guard generation == self.previewRenderGeneration else {
                    return
                }
                self.editedPreviewImage = result.image
                self.histogramSummary = result.histogram
                self.storePreviewRenderResult(result, for: cacheKey)
                self.isRenderingPreview = false
                self.previewRenderProgress = 1.0
                self.clearRecipeResolutionErrorIfNeeded()
                self.previewRenderStatus = "Preview ready"
            } catch {
                guard generation == self.previewRenderGeneration else {
                    return
                }
                self.errorMessage = error.localizedDescription
                self.isRenderingPreview = false
                self.previewRenderProgress = 0
                self.previewRenderStatus = "Preview failed"
            }
        }
    }

    private func renderPreviewSynchronously(
        sourceImage: CIImage,
        recipe: FilmRecipe,
        adjustments: RenderAdjustments,
        localAdjustments: [LocalAdjustmentLayer],
        calibration: CalibrationDataStatus,
        cacheKey: PreviewRenderCacheKey,
        generation: Int
    ) {
        isRenderingPreview = true
        previewRenderProgress = 0.2
        previewRenderStatus = "Rendering preview"

        do {
            let renderedSource = imageProcessor.renderedPreviewSource(
                from: sourceImage,
                recipe: recipe,
                adjustments: adjustments,
                localAdjustments: localAdjustments,
                calibration: calibration
            )
            let (previewImage, histogram) = try imageProcessor.makeNSImageAndHistogramSummary(from: renderedSource)
            editedPreviewImage = previewImage
            histogramSummary = histogram
            if let editedPreviewImage, let histogramSummary {
                storePreviewRenderResult(
                    PreviewRenderResult(image: editedPreviewImage, histogram: histogramSummary),
                    for: cacheKey
                )
            }
            if generation == previewRenderGeneration {
                isRenderingPreview = false
                previewRenderProgress = 1.0
                clearRecipeResolutionErrorIfNeeded()
                previewRenderStatus = "Preview ready"
            }
        } catch {
            errorMessage = error.localizedDescription
            isRenderingPreview = false
            previewRenderProgress = 0
            previewRenderStatus = "Preview failed"
        }
    }

    private func previewCacheKey(
        sourceImage: CIImage,
        recipe: FilmRecipe,
        adjustments: RenderAdjustments,
        localAdjustments: [LocalAdjustmentLayer],
        calibration: CalibrationDataStatus
    ) -> PreviewRenderCacheKey {
        PreviewRenderCacheKey(
            projectItemID: project.selectedItemID,
            sourceIdentifier: sourceURL?.path ?? importedImageName ?? "memory-source",
            sourceWidth: Int(sourceImage.extent.width.rounded()),
            sourceHeight: Int(sourceImage.extent.height.rounded()),
            recipe: recipe,
            adjustments: adjustments,
            localAdjustments: localAdjustments,
            calibration: calibration
        )
    }

    private func storePreviewRenderResult(_ result: PreviewRenderResult, for key: PreviewRenderCacheKey) {
        markPreviewCacheKeyUsed(key)
        previewRenderCache[key] = result

        var totalCost = previewRenderCache.values.reduce(0) { $0 + previewCacheCost($1) }
        while previewRenderCache.count > 1,
              previewRenderCache.count > previewRenderCacheLimit || totalCost > previewRenderCacheByteLimit,
              let oldestKey = previewRenderCacheAccessOrder.first,
              oldestKey != key {
            if let removed = previewRenderCache.removeValue(forKey: oldestKey) {
                totalCost -= previewCacheCost(removed)
            }
            previewRenderCacheAccessOrder.removeFirst()
        }
    }

    private func previewCacheCost(_ result: PreviewRenderResult) -> Int {
        let size = result.image.size
        return max(1, Int(size.width) * Int(size.height) * 4)
    }

    private func markPreviewCacheKeyUsed(_ key: PreviewRenderCacheKey) {
        previewRenderCacheAccessOrder.removeAll { $0 == key }
        previewRenderCacheAccessOrder.append(key)
    }

    private func clearPreviewCache() {
        previewRenderCache.removeAll()
        previewRenderCacheAccessOrder.removeAll()
    }

    private func handleAdjustmentChanged(note: String) {
        guard !suppressPreviewUpdates, !isApplyingEditSnapshot else {
            return
        }

        recordCurrentEditSnapshot(note: note)
        renderPreviewIfNeeded()
    }

    private func handleExportSettingsChanged() {
        guard !suppressSettingsUpdates else {
            return
        }
        project.exportSettings = exportSettings
        project.updatedAt = Date()
    }

    private func handleColorManagementChanged() {
        guard !suppressSettingsUpdates else {
            return
        }

        project.colorManagementSettings = colorManagementSettings
        project.updatedAt = Date()
        reloadCurrentSourceForColorSettings()
    }

    private func reloadCurrentSourceForColorSettings() {
        guard let sourceURL else {
            return
        }

        do {
            let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let loadedImage = try imageProcessor.loadSourceImage(from: sourceURL, colorSettings: colorManagementSettings)
            sourceImage = loadedImage
            originalPreviewImage = try imageProcessor.makePreviewImage(from: loadedImage)
            clearPreviewCache()
            renderPreviewIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordCurrentEditSnapshot(note: String, force: Bool = false, pinned: Bool = false) {
        let snapshot = EditSnapshot(
            recipeID: selectedRecipeID,
            adjustments: currentAdjustments,
            localAdjustments: localAdjustments,
            note: note,
            isPinned: pinned
        )

        // Compare against the snapshot the editor is currently sitting on,
        // not the history tail; after an undo those are different entries.
        let currentSnapshot: EditSnapshot?
        if let editHistoryIndex, editHistory.indices.contains(editHistoryIndex) {
            currentSnapshot = editHistory[editHistoryIndex]
        } else {
            currentSnapshot = editHistory.last
        }

        if !force,
           let currentSnapshot,
           currentSnapshot.recipeID == snapshot.recipeID,
           currentSnapshot.adjustments == snapshot.adjustments,
           currentSnapshot.localAdjustments == snapshot.localAdjustments {
            return
        }

        if isAdjustmentGestureActive, !force,
           let gestureID = activeGestureSnapshotID,
           let index = editHistoryIndex,
           editHistory.indices.contains(index),
           editHistory[index].id == gestureID,
           !editHistory[index].isPinned {
            editHistory[index] = EditSnapshot(
                id: gestureID,
                recipeID: snapshot.recipeID,
                adjustments: snapshot.adjustments,
                localAdjustments: snapshot.localAdjustments,
                note: note,
                createdAt: editHistory[index].createdAt
            )
            updateCurrentProjectItem()
            return
        }

        if let editHistoryIndex, editHistoryIndex < editHistory.count - 1 {
            let retainedVariants = editHistory[(editHistoryIndex + 1)...].filter(\.isPinned)
            editHistory = Array(editHistory.prefix(editHistoryIndex + 1)) + retainedVariants
        }

        editHistory.append(snapshot)
        editHistoryIndex = editHistory.count - 1
        if isAdjustmentGestureActive {
            activeGestureSnapshotID = snapshot.id
        }
        trimEditHistoryIfNeeded()
        updateCurrentProjectItem()
    }

    private func trimEditHistoryIfNeeded() {
        guard editHistory.count > editHistoryLimit else {
            return
        }

        var index = 0
        while editHistory.count > editHistoryLimit, index < editHistory.count {
            if editHistory[index].isPinned || index == editHistoryIndex {
                index += 1
                continue
            }
            editHistory.remove(at: index)
            if let current = editHistoryIndex, current > index {
                editHistoryIndex = current - 1
            }
        }
    }

    private func applyEditSnapshot(at index: Int) {
        guard editHistory.indices.contains(index) else {
            return
        }

        let snapshot = editHistory[index]
        isApplyingEditSnapshot = true
        suppressPreviewUpdates = true
        selectedRecipeID = snapshot.recipeID
        intensity = snapshot.adjustments.intensity
        exposureTrim = snapshot.adjustments.exposureTrim
        contrastTrim = snapshot.adjustments.contrastTrim
        saturationTrim = snapshot.adjustments.saturationTrim
        grainEnabled = snapshot.adjustments.grainEnabled
        localAdjustments = snapshot.localAdjustments
        selectedLocalAdjustmentID = localAdjustments.first?.id
        suppressPreviewUpdates = false
        isApplyingEditSnapshot = false
        editHistoryIndex = index
        updateCurrentProjectItem()
        renderPreviewIfNeeded()
    }

    private func makeProjectItem(for url: URL) -> FilmProjectItem {
        FilmProjectItem(
            displayName: url.lastPathComponent,
            originalURLPath: url.path,
            originalBookmarkData: projectStore.bookmarkData(for: url),
            selectedRecipeID: selectedRecipeID,
            adjustments: currentAdjustments,
            localAdjustments: localAdjustments,
            variants: [
                EditSnapshot(
                    recipeID: selectedRecipeID,
                    adjustments: currentAdjustments,
                    localAdjustments: localAdjustments,
                    note: "Imported photo"
                )
            ]
        )
    }

    private func updateCurrentProjectItem() {
        guard let selectedItemID = project.selectedItemID,
              let itemIndex = project.items.firstIndex(where: { $0.id == selectedItemID })
        else {
            return
        }

        project.items[itemIndex].selectedRecipeID = selectedRecipeID
        project.items[itemIndex].adjustments = currentAdjustments
        project.items[itemIndex].localAdjustments = localAdjustments
        project.items[itemIndex].variants = editHistory
        project.items[itemIndex].variantIndex = editHistoryIndex
        project.items[itemIndex].updatedAt = Date()
        project.updatedAt = Date()
    }

    private func restoreEditHistory(for item: FilmProjectItem) {
        editHistory = item.variants
        if let variantIndex = item.variantIndex, editHistory.indices.contains(variantIndex) {
            editHistoryIndex = variantIndex
        } else {
            editHistoryIndex = editHistory.isEmpty ? nil : editHistory.count - 1
        }
    }

    private func applyProjectItem(_ item: FilmProjectItem) {
        applyProjectItemEditState(item)

        do {
            let url = try resolveAndRefreshPhotoURL(for: item)
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let loadedImage = try imageProcessor.loadSourceImage(from: url, colorSettings: colorManagementSettings)
            sourceImage = loadedImage
            sourceURL = url
            importedImageName = item.displayName
            originalPreviewImage = try imageProcessor.makePreviewImage(from: loadedImage)
            comparisonMode = .edited

            if projectItemNeedingRelinkID == item.id {
                projectItemNeedingRelinkID = nil
            }

            guard selectedRecipe != nil else {
                clearRenderedPreviewState(
                    status: item.selectedRecipeID == nil ? "Select a recipe" : "Missing recipe"
                )
                if item.selectedRecipeID != nil {
                    errorMessage = EditorStoreError.missingRecipe(itemName: item.displayName).localizedDescription
                }
                return
            }

            renderPreviewIfNeeded()
        } catch {
            // Clear the previous photo's state so exports and previews cannot
            // operate on a source that no longer matches the selected item.
            sourceImage = nil
            sourceURL = nil
            importedImageName = nil
            clearLoadedPhotoState(previewStatus: "Photo needs relinking")
            projectItemNeedingRelinkID = item.id
            errorMessage = error.localizedDescription
        }
    }

    private func applyProjectItemEditState(_ item: FilmProjectItem) {
        suppressPreviewUpdates = true
        selectedRecipeID = item.selectedRecipeID
        intensity = item.adjustments.intensity
        exposureTrim = item.adjustments.exposureTrim
        contrastTrim = item.adjustments.contrastTrim
        saturationTrim = item.adjustments.saturationTrim
        grainEnabled = item.adjustments.grainEnabled
        localAdjustments = item.localAdjustments
        selectedLocalAdjustmentID = localAdjustments.first?.id
        suppressPreviewUpdates = false
        restoreEditHistory(for: item)
    }

    private func clearActiveProjectItemState() {
        suppressPreviewUpdates = true
        selectedRecipeID = nil
        intensity = RenderAdjustments.defaults.intensity
        exposureTrim = RenderAdjustments.defaults.exposureTrim
        contrastTrim = RenderAdjustments.defaults.contrastTrim
        saturationTrim = RenderAdjustments.defaults.saturationTrim
        grainEnabled = RenderAdjustments.defaults.grainEnabled
        localAdjustments = []
        selectedLocalAdjustmentID = nil
        suppressPreviewUpdates = false
        editHistory = []
        editHistoryIndex = nil
        sourceImage = nil
        sourceURL = nil
        importedImageName = nil
        projectItemNeedingRelinkID = nil
        clearLoadedPhotoState(previewStatus: "Idle")
    }

    private func clearRenderedPreviewState(status: String) {
        editedPreviewImage = nil
        histogramSummary = nil
        previewRenderTask?.cancel()
        previewRenderGeneration += 1
        isRenderingPreview = false
        previewRenderProgress = 0
        previewRenderStatus = status
        clearPixelSample(cancelPendingTask: true)
    }

    private func clearRecipeResolutionErrorIfNeeded() {
        if previewRenderStatus == "Missing recipe" || previewRenderStatus == "Select a recipe" {
            errorMessage = nil
            return
        }

        guard let importedImageName,
              errorMessage == EditorStoreError.missingRecipe(itemName: importedImageName).localizedDescription
        else {
            return
        }
        errorMessage = nil
    }

    private func clearLoadedPhotoState(previewStatus: String) {
        originalPreviewImage = nil
        clearRenderedPreviewState(status: previewStatus)
        localMaskEditingEnabled = false
        activeLocalMaskPointIndex = nil
        clearPreviewCache()
        resetPreviewView()
    }

    private func resolveAndRefreshPhotoURL(for item: FilmProjectItem) throws -> URL {
        let reference = try projectStore.resolvePhotoReference(for: item)
        if let refreshedBookmarkData = reference.refreshedBookmarkData,
           let itemIndex = project.items.firstIndex(where: { $0.id == item.id }) {
            project.items[itemIndex].originalBookmarkData = refreshedBookmarkData
            project.items[itemIndex].originalURLPath = reference.url.path
            project.items[itemIndex].updatedAt = Date()
            project.updatedAt = Date()
        }
        return reference.url
    }

    private func uniqueLocalAdjustmentName(base: String) -> String {
        var candidate = base
        var index = 2
        let existingNames = Set(localAdjustments.map(\.name))

        while existingNames.contains(candidate) {
            candidate = "\(base) \(index)"
            index += 1
        }

        return candidate
    }

    private func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func suggestedExportFileName() -> String {
        // The save panel must suggest the same name the naming-template
        // preview shows; the template is validated before export is enabled.
        guard exportNamingTemplateIssues.isEmpty else {
            let base = URL(fileURLWithPath: importedImageName ?? "film-chef-photo")
                .deletingPathExtension()
                .lastPathComponent
            return "\(Self.sanitizedFileComponent(base))-edited.\(exportSettings.fileFormat.preferredPathExtension)"
        }

        return exportFileNamePreview
    }
}
