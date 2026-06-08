import AppKit
import CoreImage
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class EditorStore: ObservableObject {
    private struct PreviewRenderCacheKey: Hashable {
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

    package struct RecipeDraft: Equatable {
        package var displayName: String
        package var manufacturer: String
        package var summary: String

        package init(
            displayName: String = "",
            manufacturer: String = "",
            summary: String = ""
        ) {
            self.displayName = displayName
            self.manufacturer = manufacturer
            self.summary = summary
        }

        package init(recipe: FilmRecipe) {
            displayName = recipe.displayName
            manufacturer = recipe.manufacturer
            summary = recipe.summary
        }

        package func hasChanges(comparedTo recipe: FilmRecipe) -> Bool {
            displayName != recipe.displayName ||
                manufacturer != recipe.manufacturer ||
                summary != recipe.summary
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
    @Published package var recipeDraft = RecipeDraft()
    @Published package var selectedRecipeID: String? {
        didSet {
            syncRecipeDraftWithSelection()
            guard !isApplyingEditSnapshot else {
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
    @Published package var errorMessage: String?

    @Published package var comparisonMode = PreviewComparisonMode.edited
    @Published package var previewZoom = 1.0
    @Published package var previewPanX = 0.0
    @Published package var previewPanY = 0.0
    @Published package var loupeEnabled = false
    @Published package var loupeZoom = 2.0
    @Published package var splitPosition = 0.5
    @Published package private(set) var samplerX = 0.5
    @Published package private(set) var samplerY = 0.5
    @Published package var histogramChannelMode = HistogramChannelMode.all
    @Published package var exportSettings = ExportSettings.defaults
    @Published package var exportPresets = ExportPreset.defaults
    @Published package var selectedExportPresetID: UUID?
    @Published package var exportPresetDraftName = "Custom Preset"
    @Published package var colorManagementSettings = ColorManagementSettings.defaults
    @Published package private(set) var calibrationDataStatus = CalibrationDataStatus.descriptiveOnly
    @Published package var localAdjustments: [LocalAdjustmentLayer] = [] {
        didSet {
            guard !suppressPreviewUpdates else {
                return
            }
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
    private let rendersSynchronouslyForTesting: Bool
    private let presentsPhotoImportPanel: Bool
    private var sourceImage: CIImage?
    private var sourceURL: URL?
    private var suppressPreviewUpdates = false
    private var isApplyingEditSnapshot = false
    private var previewRenderTask: Task<Void, Never>?
    private var previewRenderGeneration = 0
    private var previewRenderCache: [PreviewRenderCacheKey: PreviewRenderResult] = [:]
    private let previewRenderCacheLimit = 8

    public init(recipeStore: RecipeStore) {
        self.recipeStore = recipeStore
        projectStore = ProjectStore()
        imageProcessor = ImageProcessor()
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

    package var recipeDraftIssues: [RecipeValidationIssue] {
        guard let selectedRecipe else {
            return []
        }

        let draftRecipe = selectedRecipe.replacingMetadata(
            displayName: recipeDraft.trimmedDisplayName(),
            manufacturer: recipeDraft.trimmedManufacturer(),
            summary: recipeDraft.trimmedSummary()
        )
        return FilmRecipeValidator.issues(for: draftRecipe)
    }

    package var selectedRecipeValidationIssues: [RecipeValidationIssue] {
        guard let selectedRecipe else {
            return []
        }
        return FilmRecipeValidator.issues(for: selectedRecipe)
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

    public var canBatchExport: Bool {
        !project.items.isEmpty && !recipes.isEmpty
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
        guard recipes.isEmpty else {
            return
        }

        do {
            recipes = try recipeStore.loadRecipes()
            selectedRecipeID = recipes.first?.id
            if editHistory.isEmpty {
                recordCurrentEditSnapshot(note: "Initial recipe")
            }
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

    package func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importPhoto(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    package func handleImportResults(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importPhotos(from: urls)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    package func handleRecipeImportResults(_ result: Result<[URL], Error>) {
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
        switch result {
        case .success(let urls):
            importCalibrationAssets(from: urls)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    package func handleProjectOpenResults(_ result: Result<[URL], Error>) {
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

        let limit = (previewZoom - 1.0) * 160
        previewPanX = min(max(previewPanX + deltaX, -limit), limit)
        previewPanY = min(max(previewPanY + deltaY, -limit), limit)
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
        recordCurrentEditSnapshot(note: note, force: true)
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
        )

        let issues = FilmRecipeValidator.issues(for: updatedRecipe)
        guard issues.isEmpty else {
            recipeImportStatus = .failed(name: updatedRecipe.name, issues: issues)
            return
        }

        replaceRecipe(updatedRecipe)
        recipeImportStatus = .imported(name: updatedRecipe.name)
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

    public func saveExportPreset() {
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

    public func samplePreviewPixel(x: Double = 0.5, y: Double = 0.5) {
        samplerX = clampedUnit(x)
        samplerY = clampedUnit(y)

        guard let sourceImage, let selectedRecipe else {
            return
        }

        do {
            let rendered = imageProcessor.renderedPreviewSource(
                from: sourceImage,
                recipe: selectedRecipe,
                adjustments: currentAdjustments,
                localAdjustments: localAdjustments,
                calibration: calibrationDataStatus
            )
            pixelSample = try imageProcessor.samplePixel(
                from: rendered,
                normalisedX: samplerX,
                normalisedY: samplerY
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addLocalAdjustment() {
        localAdjustments.append(.centeredDodge)
    }

    public func removeLocalAdjustments() {
        localAdjustments.removeAll()
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
        guard let item = project.items.first(where: { $0.id == id }) else {
            return
        }

        updateCurrentProjectItem()
        project.selectedItemID = id
        editHistory = item.variants
        editHistoryIndex = editHistory.isEmpty ? nil : editHistory.count - 1
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
        guard canExport else {
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
                self?.writeProjectExports(to: url)
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
            _ = try imageProcessor.loadSourceImage(from: url, colorSettings: colorManagementSettings)
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
            let loadedProject = try projectStore.loadProject(from: url)
            project = loadedProject
            editHistory = loadedProject.editHistory
            editHistoryIndex = loadedProject.editHistoryIndex
            exportSettings = loadedProject.exportSettings
            exportPresets = loadedProject.exportPresets.isEmpty ? ExportPreset.defaults : loadedProject.exportPresets
            selectedExportPresetID = exportPresets.first?.id
            exportPresetDraftName = exportPresets.first?.name ?? "Custom Preset"
            colorManagementSettings = loadedProject.colorManagementSettings
            calibrationDataStatus = loadedProject.calibrationDataStatus

            if let selectedItem = loadedProject.items.first(where: { $0.id == loadedProject.selectedItemID }) ?? loadedProject.items.first {
                applyProjectItem(selectedItem)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func writeProject(to url: URL) {
        updateCurrentProjectItem()
        project.editHistory = editHistory
        project.editHistoryIndex = editHistoryIndex
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

    private func importRecipe(from url: URL) {
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

    private func importCalibrationAssets(from urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        let names = urls.map(\.lastPathComponent).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let lowercasedNames = names.map { $0.lowercased() }
        let supportsSpectralCurves = lowercasedNames.contains { $0.contains("spectral") || $0.contains("spectrum") }
        let supportsMeasuredDensityCurves = lowercasedNames.contains { $0.contains("density") || $0.contains("hd") || $0.contains("h-d") }
        let supportsGrainSpectra = lowercasedNames.contains { $0.contains("grain") || $0.contains("granularity") }
        let lutScale = calibrationScale(from: urls)
        let spectralSignal = calibrationSignal(from: urls, matching: ["spectral", "spectrum"])
        let densitySignal = calibrationSignal(from: urls, matching: ["density", "hd", "h-d"])
        let grainSignal = calibrationSignal(from: urls, matching: ["grain", "granularity"])
        let spectralBias = supportsSpectralCurves ? 0.025 + (spectralSignal * 0.02) : 0
        calibrationDataStatus = CalibrationDataStatus(
            supportsSpectralCurves: supportsSpectralCurves,
            supportsMeasuredDensityCurves: supportsMeasuredDensityCurves,
            supportsGrainSpectra: supportsGrainSpectra,
            supportsThreeDimensionalLUTs: lowercasedNames.contains { $0.hasSuffix(".cube") || $0.contains("lut") },
            importedAssetNames: names,
            redScale: lutScale.red * (1.0 + spectralBias),
            greenScale: lutScale.green,
            blueScale: lutScale.blue * (1.0 - spectralBias),
            densityGamma: supportsMeasuredDensityCurves ? 1.0 + (densitySignal * 0.08) : 1.0,
            grainAmount: supportsGrainSpectra ? 0.035 + (grainSignal * 0.045) : 0.0,
            note: "Imported \(names.count) calibration asset\(names.count == 1 ? "" : "s") with render calibration."
        )
        project.calibrationDataStatus = calibrationDataStatus
        project.updatedAt = Date()
        renderPreviewIfNeeded()
    }

    private func calibrationScale(from urls: [URL]) -> (red: Double, green: Double, blue: Double) {
        var redTotal = 0.0
        var greenTotal = 0.0
        var blueTotal = 0.0
        var count = 0.0

        for url in urls where url.pathExtension.lowercased() == "cube" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }

            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                    continue
                }

                let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap(Double.init)
                guard parts.count == 3 else {
                    continue
                }

                redTotal += parts[0]
                greenTotal += parts[1]
                blueTotal += parts[2]
                count += 1
            }
        }

        guard count > 0 else {
            return (1.0, 1.0, 1.0)
        }

        let redAverage = redTotal / count
        let greenAverage = greenTotal / count
        let blueAverage = blueTotal / count
        let neutralAverage = max((redAverage + greenAverage + blueAverage) / 3.0, 0.001)
        return (
            red: redAverage / neutralAverage,
            green: greenAverage / neutralAverage,
            blue: blueAverage / neutralAverage
        )
    }

    private func calibrationSignal(from urls: [URL], matching tokens: [String]) -> Double {
        var total = 0.0
        var count = 0.0

        for url in urls {
            let name = url.lastPathComponent.lowercased()
            guard tokens.contains(where: { name.contains($0) }),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else {
                continue
            }

            let values = text
                .components(separatedBy: CharacterSet(charactersIn: "0123456789.-+eE").inverted)
                .compactMap(Double.init)

            for value in values where value.isFinite {
                total += abs(value)
                count += 1
            }
        }

        guard count > 0 else {
            return 0.5
        }

        return min(max((total / count).truncatingRemainder(dividingBy: 1.0), 0), 1)
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
                colorSettings: colorManagementSettings
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func writeProjectExports(to directory: URL) {
        updateCurrentProjectItem()

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for item in project.items {
                try writeProjectExport(for: item, to: directory)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func writeProjectExport(for item: FilmProjectItem, to directory: URL) throws {
        let sourceURL = try projectStore.resolvePhotoURL(for: item)
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let source = try imageProcessor.loadSourceImage(from: sourceURL, colorSettings: colorManagementSettings)
        let recipe = recipes.first { $0.id == item.selectedRecipeID } ?? selectedRecipe ?? recipes[0]
        let exportURL = uniqueExportURL(
            in: directory,
            item: item,
            recipe: recipe
        )
        try imageProcessor.writeRenderedImage(
            from: source,
            recipe: recipe,
            adjustments: item.adjustments,
            to: exportURL,
            settings: exportSettings,
            localAdjustments: item.localAdjustments,
            calibration: calibrationDataStatus,
            colorSettings: colorManagementSettings
        )
    }

    private func renderPreviewIfNeeded() {
        guard !suppressPreviewUpdates,
              let sourceImage,
              let selectedRecipe
        else {
            return
        }

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
            editedPreviewImage = cached.image
            histogramSummary = cached.histogram
            previewCacheHitCount += 1
            isRenderingPreview = false
            previewRenderProgress = 1.0
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
            guard !Task.isCancelled else {
                return
            }

            do {
                await MainActor.run {
                    guard generation == self.previewRenderGeneration else {
                        return
                    }
                    self.previewRenderProgress = 0.45
                    self.previewRenderStatus = "Rendering look"
                }
                let renderedSource = imageProcessor.renderedPreviewSource(
                    from: sourceImage,
                    recipe: selectedRecipe,
                    adjustments: adjustments,
                    localAdjustments: localAdjustments,
                    calibration: calibration
                )
                await MainActor.run {
                    guard generation == self.previewRenderGeneration else {
                        return
                    }
                    self.previewRenderProgress = 0.75
                    self.previewRenderStatus = "Building scopes"
                }
                let previewImage = try imageProcessor.makeNSImageForTesting(from: renderedSource)
                let histogram = try imageProcessor.makeHistogramSummary(from: renderedSource)

                await MainActor.run {
                    guard generation == self.previewRenderGeneration else {
                        return
                    }
                    self.editedPreviewImage = previewImage
                    self.histogramSummary = histogram
                    self.storePreviewRenderResult(
                        PreviewRenderResult(image: previewImage, histogram: histogram),
                        for: cacheKey
                    )
                    self.isRenderingPreview = false
                    self.previewRenderProgress = 1.0
                    self.previewRenderStatus = "Preview ready"
                }
            } catch {
                await MainActor.run {
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
            editedPreviewImage = try imageProcessor.makeNSImageForTesting(from: renderedSource)
            histogramSummary = try imageProcessor.makeHistogramSummary(from: renderedSource)
            if let editedPreviewImage, let histogramSummary {
                storePreviewRenderResult(
                    PreviewRenderResult(image: editedPreviewImage, histogram: histogramSummary),
                    for: cacheKey
                )
            }
            if generation == previewRenderGeneration {
                isRenderingPreview = false
                previewRenderProgress = 1.0
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
        if previewRenderCache.count >= previewRenderCacheLimit,
           let firstKey = previewRenderCache.keys.first {
            previewRenderCache.removeValue(forKey: firstKey)
        }
        previewRenderCache[key] = result
    }

    private func handleAdjustmentChanged(note: String) {
        guard !suppressPreviewUpdates, !isApplyingEditSnapshot else {
            return
        }

        recordCurrentEditSnapshot(note: note)
        renderPreviewIfNeeded()
    }

    private func recordCurrentEditSnapshot(note: String, force: Bool = false) {
        let snapshot = EditSnapshot(
            recipeID: selectedRecipeID,
            adjustments: currentAdjustments,
            note: note
        )

        if !force, editHistory.last?.recipeID == snapshot.recipeID, editHistory.last?.adjustments == snapshot.adjustments {
            return
        }

        if let editHistoryIndex, editHistoryIndex < editHistory.count - 1 {
            editHistory = Array(editHistory.prefix(editHistoryIndex + 1))
        }

        editHistory.append(snapshot)
        editHistoryIndex = editHistory.count - 1
        updateCurrentProjectItem()
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
        project.items[itemIndex].updatedAt = Date()
        project.updatedAt = Date()
    }

    private func applyProjectItem(_ item: FilmProjectItem) {
        do {
            let url = try projectStore.resolvePhotoURL(for: item)
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

            suppressPreviewUpdates = true
            selectedRecipeID = item.selectedRecipeID
            intensity = item.adjustments.intensity
            exposureTrim = item.adjustments.exposureTrim
            contrastTrim = item.adjustments.contrastTrim
            saturationTrim = item.adjustments.saturationTrim
            grainEnabled = item.adjustments.grainEnabled
            localAdjustments = item.localAdjustments
            suppressPreviewUpdates = false
            comparisonMode = .edited

            editHistory = item.variants
            editHistoryIndex = editHistory.isEmpty ? nil : editHistory.count - 1

            renderPreviewIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uniqueExportURL(
        in directory: URL,
        item: FilmProjectItem,
        recipe: FilmRecipe
    ) -> URL {
        let baseName = sanitizedFileComponent(
            exportSettings.namingTemplate
                .replacingOccurrences(
                    of: "{photo}",
                    with: URL(fileURLWithPath: item.displayName).deletingPathExtension().lastPathComponent
                )
                .replacingOccurrences(of: "{recipe}", with: recipe.name)
                .replacingOccurrences(of: "{format}", with: exportSettings.fileFormat.label)
        )
        let fileExtension = exportSettings.fileFormat.preferredPathExtension
        var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).\(fileExtension)")
            suffix += 1
        }

        return candidate
    }

    private func sanitizedFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = value
            .components(separatedBy: allowed.inverted)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()

        return cleaned.isEmpty ? "photo" : cleaned
    }

    private func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func suggestedExportFileName() -> String {
        let baseName = sourceURL?
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let safeBaseName = baseName?.isEmpty == false ? baseName! : "film-chef-photo"
        let recipeSlug = selectedRecipe?.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "+", with: "plus")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()

        if let recipeSlug, !recipeSlug.isEmpty {
            return "\(safeBaseName)-\(recipeSlug).\(exportSettings.fileFormat.preferredPathExtension)"
        }

        return "\(safeBaseName)-edited.\(exportSettings.fileFormat.preferredPathExtension)"
    }
}
