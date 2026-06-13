import Foundation

private func valuesWithUniqueIDs<Value>(
    _ values: [Value],
    id: (Value) -> UUID,
    replacingDuplicateWith makeFreshValue: (Value) -> Value
) -> [Value] {
    var seenIDs: Set<UUID> = []
    return values.map { value in
        guard !seenIDs.insert(id(value)).inserted else {
            return value
        }

        var repairedValue = makeFreshValue(value)
        while !seenIDs.insert(id(repairedValue)).inserted {
            repairedValue = makeFreshValue(value)
        }
        return repairedValue
    }
}

private func fallbackDisplayName(for originalURLPath: String?) -> String {
    guard let originalURLPath,
          !originalURLPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return "Missing Photo"
    }

    let fallbackName = URL(fileURLWithPath: originalURLPath).lastPathComponent
    return fallbackName.isEmpty ? "Missing Photo" : fallbackName
}

private func restoredName(_ decodedName: String?, fallback: String) -> String {
    guard let decodedName else {
        return fallback
    }

    let trimmedName = decodedName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedName.isEmpty ? fallback : trimmedName
}

package struct FilmProject: Codable, Equatable {
    package var schemaVersion: Int
    package var id: UUID
    package var name: String
    package var items: [FilmProjectItem]
    package var selectedItemID: UUID?
    package var editHistory: [EditSnapshot]
    package var editHistoryIndex: Int?
    /// Custom and imported recipes referenced by project items; bundled
    /// recipes are resolved from the app and are not stored here.
    package var customRecipes: [FilmRecipe]
    package var exportSettings: ExportSettings
    package var exportPresets: [ExportPreset]
    package var colorManagementSettings: ColorManagementSettings
    package var calibrationDataStatus: CalibrationDataStatus
    package var createdAt: Date
    package var updatedAt: Date

    package init(
        schemaVersion: Int = 1,
        id: UUID = UUID(),
        name: String = "Untitled Film Chef Project",
        items: [FilmProjectItem] = [],
        selectedItemID: UUID? = nil,
        editHistory: [EditSnapshot] = [],
        editHistoryIndex: Int? = nil,
        customRecipes: [FilmRecipe] = [],
        exportSettings: ExportSettings = .defaults,
        exportPresets: [ExportPreset] = ExportPreset.defaults,
        colorManagementSettings: ColorManagementSettings = .defaults,
        calibrationDataStatus: CalibrationDataStatus = .descriptiveOnly,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.items = items
        self.selectedItemID = selectedItemID
        self.editHistory = editHistory
        self.editHistoryIndex = editHistoryIndex
        self.customRecipes = customRecipes
        self.exportSettings = exportSettings
        self.exportPresets = exportPresets
        self.colorManagementSettings = colorManagementSettings
        self.calibrationDataStatus = calibrationDataStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Film Chef Project"
        let trimmedName = decodedName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmedName.isEmpty ? "Untitled Film Chef Project" : trimmedName
        items = Self.normalizedProjectItems(
            try container.decodeIfPresent([FilmProjectItem].self, forKey: .items) ?? []
        )
        selectedItemID = try container.decodeIfPresent(UUID.self, forKey: .selectedItemID)
        editHistory = EditSnapshot.normalizedIDs(
            try container.decodeIfPresent([EditSnapshot].self, forKey: .editHistory) ?? []
        )
        editHistoryIndex = try container.decodeIfPresent(Int.self, forKey: .editHistoryIndex)
        customRecipes = try container.decodeIfPresent([FilmRecipe].self, forKey: .customRecipes) ?? []
        exportSettings = try container.decodeIfPresent(ExportSettings.self, forKey: .exportSettings) ?? .defaults
        exportPresets = ExportPreset.normalizedIDs(
            try container.decodeIfPresent([ExportPreset].self, forKey: .exportPresets) ?? ExportPreset.defaults
        )
        colorManagementSettings = try container.decodeIfPresent(ColorManagementSettings.self, forKey: .colorManagementSettings) ?? .defaults
        calibrationDataStatus = try container.decodeIfPresent(CalibrationDataStatus.self, forKey: .calibrationDataStatus) ?? .descriptiveOnly
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    private static func normalizedProjectItems(_ items: [FilmProjectItem]) -> [FilmProjectItem] {
        valuesWithUniqueIDs(items, id: { $0.id }) { item in
            var repairedItem = item
            repairedItem.id = UUID()
            return repairedItem
        }
    }
}

package struct FilmProjectItem: Codable, Equatable, Identifiable {
    package var id: UUID
    package var displayName: String
    package var originalURLPath: String?
    package var originalBookmarkData: Data?
    package var selectedRecipeID: String?
    package var adjustments: RenderAdjustments
    package var localAdjustments: [LocalAdjustmentLayer]
    package var variants: [EditSnapshot]
    package var variantIndex: Int?
    package var createdAt: Date
    package var updatedAt: Date

    package init(
        id: UUID = UUID(),
        displayName: String,
        originalURLPath: String?,
        originalBookmarkData: Data? = nil,
        selectedRecipeID: String?,
        adjustments: RenderAdjustments,
        localAdjustments: [LocalAdjustmentLayer] = [],
        variants: [EditSnapshot] = [],
        variantIndex: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.originalURLPath = originalURLPath
        self.originalBookmarkData = originalBookmarkData
        self.selectedRecipeID = selectedRecipeID
        self.adjustments = adjustments
        self.localAdjustments = localAdjustments
        self.variants = variants
        self.variantIndex = variantIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalURLPath = try container.decodeIfPresent(String.self, forKey: .originalURLPath)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName = restoredName(
            try container.decodeIfPresent(String.self, forKey: .displayName),
            fallback: fallbackDisplayName(for: originalURLPath)
        )
        originalBookmarkData = try container.decodeIfPresent(Data.self, forKey: .originalBookmarkData)
        selectedRecipeID = try container.decodeIfPresent(String.self, forKey: .selectedRecipeID)
        adjustments = try container.decodeIfPresent(RenderAdjustments.self, forKey: .adjustments) ?? .defaults
        localAdjustments = LocalAdjustmentLayer.normalizedIDs(
            try container.decodeIfPresent([LocalAdjustmentLayer].self, forKey: .localAdjustments) ?? []
        )
        variants = EditSnapshot.normalizedIDs(
            try container.decodeIfPresent([EditSnapshot].self, forKey: .variants) ?? []
        )
        variantIndex = try container.decodeIfPresent(Int.self, forKey: .variantIndex)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

package struct EditSnapshot: Codable, Equatable, Identifiable {
    package var id: UUID
    package var recipeID: String?
    package var adjustments: RenderAdjustments
    package var localAdjustments: [LocalAdjustmentLayer]
    package var note: String
    /// Pinned snapshots are user-curated variants (captured, renamed, or
    /// duplicated) and survive redo-branch truncation and history trimming.
    package var isPinned: Bool
    package var createdAt: Date

    package init(
        id: UUID = UUID(),
        recipeID: String?,
        adjustments: RenderAdjustments,
        localAdjustments: [LocalAdjustmentLayer] = [],
        note: String,
        isPinned: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recipeID = recipeID
        self.adjustments = adjustments
        self.localAdjustments = localAdjustments
        self.note = note
        self.isPinned = isPinned
        self.createdAt = createdAt
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        recipeID = try container.decodeIfPresent(String.self, forKey: .recipeID)
        adjustments = try container.decodeIfPresent(RenderAdjustments.self, forKey: .adjustments) ?? .defaults
        localAdjustments = LocalAdjustmentLayer.normalizedIDs(
            try container.decodeIfPresent([LocalAdjustmentLayer].self, forKey: .localAdjustments) ?? []
        )
        note = restoredName(
            try container.decodeIfPresent(String.self, forKey: .note),
            fallback: "Restored edit"
        )
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

extension EditSnapshot {
    fileprivate static func normalizedIDs(_ snapshots: [EditSnapshot]) -> [EditSnapshot] {
        valuesWithUniqueIDs(snapshots, id: { $0.id }) { snapshot in
            var repairedSnapshot = snapshot
            repairedSnapshot.id = UUID()
            return repairedSnapshot
        }
    }
}

package enum LocalAdjustmentMask: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case radial
    case linear
    case brush
    case path

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .radial:
            return "Radial"
        case .linear:
            return "Linear"
        case .brush:
            return "Brush"
        case .path:
            return "Path"
        }
    }
}

package struct NormalizedMaskPoint: Codable, Equatable, Hashable {
    package var x: Double
    package var y: Double

    package init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

package struct LocalAdjustmentLayer: Codable, Equatable, Hashable, Identifiable {
    package var id: UUID
    package var name: String
    package var isEnabled: Bool
    package var mask: LocalAdjustmentMask
    package var centerX: Double
    package var centerY: Double
    package var radius: Double
    package var feather: Double
    package var brushSize: Double
    package var pathPoints: [NormalizedMaskPoint]
    package var exposureEV: Double
    package var contrast: Double
    package var saturation: Double

    package init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        mask: LocalAdjustmentMask = .radial,
        centerX: Double = 0.5,
        centerY: Double = 0.5,
        radius: Double = 0.35,
        feather: Double = 0.25,
        brushSize: Double = 0.12,
        pathPoints: [NormalizedMaskPoint] = LocalAdjustmentLayer.defaultPathPoints,
        exposureEV: Double = 0,
        contrast: Double = 0,
        saturation: Double = 0
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.mask = mask
        self.centerX = Self.clamped(centerX, lower: 0, upper: 1)
        self.centerY = Self.clamped(centerY, lower: 0, upper: 1)
        self.radius = Self.clamped(radius, lower: 0.05, upper: 1)
        self.feather = Self.clamped(feather, lower: 0, upper: 1)
        self.brushSize = Self.clamped(brushSize, lower: 0.02, upper: 0.5)
        self.pathPoints = pathPoints.map { point in
            NormalizedMaskPoint(
                x: Self.clamped(point.x, lower: 0, upper: 1),
                y: Self.clamped(point.y, lower: 0, upper: 1)
            )
        }
        self.exposureEV = Self.clamped(exposureEV, lower: -1, upper: 1)
        self.contrast = Self.clamped(contrast, lower: -0.5, upper: 0.5)
        self.saturation = Self.clamped(saturation, lower: -0.75, upper: 0.75)
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = restoredName(
            try container.decodeIfPresent(String.self, forKey: .name),
            fallback: "Local Adjustment"
        )
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mask = (try? container.decodeIfPresent(LocalAdjustmentMask.self, forKey: .mask)) ?? .radial
        centerX = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .centerX) ?? 0.5,
            lower: 0,
            upper: 1
        )
        centerY = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .centerY) ?? 0.5,
            lower: 0,
            upper: 1
        )
        radius = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .radius) ?? 0.35,
            lower: 0.05,
            upper: 1
        )
        feather = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .feather) ?? 0.25,
            lower: 0,
            upper: 1
        )
        brushSize = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .brushSize) ?? 0.12,
            lower: 0.02,
            upper: 0.5
        )
        let decodedPathPoints = try container.decodeIfPresent([NormalizedMaskPoint].self, forKey: .pathPoints)
            ?? Self.defaultPathPoints
        pathPoints = decodedPathPoints.map { point in
            NormalizedMaskPoint(
                x: Self.clamped(point.x, lower: 0, upper: 1),
                y: Self.clamped(point.y, lower: 0, upper: 1)
            )
        }
        exposureEV = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .exposureEV) ?? 0,
            lower: -1,
            upper: 1
        )
        contrast = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            lower: -0.5,
            upper: 0.5
        )
        saturation = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            lower: -0.75,
            upper: 0.75
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mask, forKey: .mask)
        try container.encode(centerX, forKey: .centerX)
        try container.encode(centerY, forKey: .centerY)
        try container.encode(radius, forKey: .radius)
        try container.encode(feather, forKey: .feather)
        try container.encode(brushSize, forKey: .brushSize)
        try container.encode(pathPoints, forKey: .pathPoints)
        try container.encode(exposureEV, forKey: .exposureEV)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(saturation, forKey: .saturation)
    }

    package static let centeredDodge = LocalAdjustmentLayer(
        name: "Center Dodge",
        exposureEV: 0.25,
        contrast: 0.05
    )

    package static let defaultPathPoints = [
        NormalizedMaskPoint(x: 0.35, y: 0.35),
        NormalizedMaskPoint(x: 0.65, y: 0.35),
        NormalizedMaskPoint(x: 0.62, y: 0.68),
        NormalizedMaskPoint(x: 0.38, y: 0.72)
    ]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case mask
        case centerX
        case centerY
        case radius
        case feather
        case brushSize
        case pathPoints
        case exposureEV
        case contrast
        case saturation
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

extension LocalAdjustmentLayer {
    fileprivate static func normalizedIDs(_ layers: [LocalAdjustmentLayer]) -> [LocalAdjustmentLayer] {
        valuesWithUniqueIDs(layers, id: { $0.id }) { layer in
            var repairedLayer = layer
            repairedLayer.id = UUID()
            return repairedLayer
        }
    }
}

package enum PreviewComparisonMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case edited
    case original
    case split

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .edited:
            return "Processed"
        case .original:
            return "Original"
        case .split:
            return "Split"
        }
    }
}

package enum LoupePlacement: String, CaseIterable, Codable, Equatable, Identifiable {
    case nearSampler
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .nearSampler:
            return "Near Sample"
        case .topLeft:
            return "Top Left"
        case .topRight:
            return "Top Right"
        case .bottomLeft:
            return "Bottom Left"
        case .bottomRight:
            return "Bottom Right"
        }
    }
}

package enum ExportFileFormat: String, CaseIterable, Codable, Equatable, Identifiable {
    case jpeg
    case png
    case tiff

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .jpeg:
            return "JPEG"
        case .png:
            return "PNG"
        case .tiff:
            return "TIFF"
        }
    }

    package var preferredPathExtension: String {
        switch self {
        case .jpeg:
            return "jpg"
        case .png:
            return "png"
        case .tiff:
            return "tiff"
        }
    }
}

package struct ExportSettings: Codable, Equatable, Hashable {
    package var fileFormat: ExportFileFormat
    package var jpegQuality: Double
    package var scale: Double
    package var preserveMetadata: Bool
    package var embedColorProfile: Bool
    package var namingTemplate: String

    package init(
        fileFormat: ExportFileFormat = .jpeg,
        jpegQuality: Double = 0.92,
        scale: Double = 1.0,
        preserveMetadata: Bool = true,
        embedColorProfile: Bool = true,
        namingTemplate: String = "{photo}-{recipe}"
    ) {
        self.fileFormat = fileFormat
        self.jpegQuality = Self.clamped(jpegQuality, lower: 0.1, upper: 1.0)
        self.scale = Self.clamped(scale, lower: 0.25, upper: 2.0)
        self.preserveMetadata = preserveMetadata
        self.embedColorProfile = embedColorProfile
        self.namingTemplate = namingTemplate
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileFormat = try container.decodeIfPresent(ExportFileFormat.self, forKey: .fileFormat) ?? .jpeg
        jpegQuality = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? 0.92,
            lower: 0.1,
            upper: 1.0
        )
        scale = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0,
            lower: 0.25,
            upper: 2.0
        )
        preserveMetadata = try container.decodeIfPresent(Bool.self, forKey: .preserveMetadata) ?? true
        embedColorProfile = try container.decodeIfPresent(Bool.self, forKey: .embedColorProfile) ?? true
        namingTemplate = try container.decodeIfPresent(String.self, forKey: .namingTemplate) ?? "{photo}-{recipe}"
    }

    package static let defaults = ExportSettings()

    private enum CodingKeys: String, CodingKey {
        case fileFormat
        case jpegQuality
        case scale
        case preserveMetadata
        case embedColorProfile
        case namingTemplate
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

package struct ExportPreset: Codable, Equatable, Hashable, Identifiable {
    package var id: UUID
    package var name: String
    package var settings: ExportSettings

    package init(
        id: UUID = UUID(),
        name: String,
        settings: ExportSettings
    ) {
        self.id = id
        self.name = name
        self.settings = settings
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? "Custom Preset"
        let trimmedName = decodedName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmedName.isEmpty ? "Custom Preset" : trimmedName
        settings = try container.decodeIfPresent(ExportSettings.self, forKey: .settings) ?? .defaults
    }

    package static let defaults = [
        ExportPreset(name: "Web JPEG", settings: ExportSettings(fileFormat: .jpeg, jpegQuality: 0.86, scale: 1.0, preserveMetadata: false, embedColorProfile: true, namingTemplate: "{photo}-{recipe}")),
        ExportPreset(name: "Archive TIFF", settings: ExportSettings(fileFormat: .tiff, jpegQuality: 1.0, scale: 1.0, preserveMetadata: true, embedColorProfile: true, namingTemplate: "{photo}-{recipe}-archive")),
        ExportPreset(name: "Review PNG", settings: ExportSettings(fileFormat: .png, jpegQuality: 1.0, scale: 0.5, preserveMetadata: false, embedColorProfile: true, namingTemplate: "{photo}-{recipe}-review"))
    ]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case settings
    }
}

extension ExportPreset {
    fileprivate static func normalizedIDs(_ presets: [ExportPreset]) -> [ExportPreset] {
        valuesWithUniqueIDs(presets, id: { $0.id }) { preset in
            var repairedPreset = preset
            repairedPreset.id = UUID()
            return repairedPreset
        }
    }
}

package struct HistogramSummary: Codable, Equatable {
    package var red: [Double]
    package var green: [Double]
    package var blue: [Double]
    package var luminance: [Double]
    package var redParade: [Double]
    package var greenParade: [Double]
    package var blueParade: [Double]
    package var sampleCount: Int
    package var shadowClippingRatio: Double
    package var highlightClippingRatio: Double

    package init(
        red: [Double],
        green: [Double],
        blue: [Double],
        luminance: [Double],
        redParade: [Double] = [],
        greenParade: [Double] = [],
        blueParade: [Double] = [],
        sampleCount: Int,
        shadowClippingRatio: Double = 0,
        highlightClippingRatio: Double = 0
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luminance = luminance
        self.redParade = redParade
        self.greenParade = greenParade
        self.blueParade = blueParade
        self.sampleCount = sampleCount
        self.shadowClippingRatio = shadowClippingRatio
        self.highlightClippingRatio = highlightClippingRatio
    }
}

package enum HistogramChannelMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case luminance
    case rgb
    case parade
    case all

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .luminance:
            return "Luma"
        case .rgb:
            return "RGB"
        case .parade:
            return "Parade"
        case .all:
            return "All"
        }
    }
}

package struct PixelSample: Codable, Equatable, Hashable {
    package var x: Double
    package var y: Double
    package var red: Double
    package var green: Double
    package var blue: Double
    package var luminance: Double

    package init(
        x: Double,
        y: Double,
        red: Double,
        green: Double,
        blue: Double,
        luminance: Double
    ) {
        self.x = x
        self.y = y
        self.red = red
        self.green = green
        self.blue = blue
        self.luminance = luminance
    }
}

package struct BatchExportFailure: Codable, Equatable, Hashable, Identifiable {
    package var id: String { "\(itemName)|\(message)" }
    package var itemName: String
    package var message: String

    package init(itemName: String, message: String) {
        self.itemName = itemName
        self.message = message
    }
}

package struct BatchExportDiagnostics: Equatable, Hashable {
    package var outputDirectoryPath: String?
    package var summary: String
    package var exportedFileNames: [String]
    package var failures: [BatchExportFailure]

    package var retryableFailureCount: Int {
        failures.count
    }
}

package struct BatchExportState: Codable, Equatable, Hashable {
    package var isExporting: Bool
    package var completedCount: Int
    package var totalCount: Int
    package var currentItemName: String?
    package var wasCancelled: Bool
    package var exportedFileNames: [String]
    package var failures: [BatchExportFailure]
    package var outputDirectoryPath: String?

    package init(
        isExporting: Bool = false,
        completedCount: Int = 0,
        totalCount: Int = 0,
        currentItemName: String? = nil,
        wasCancelled: Bool = false,
        exportedFileNames: [String] = [],
        failures: [BatchExportFailure] = [],
        outputDirectoryPath: String? = nil
    ) {
        self.isExporting = isExporting
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.currentItemName = currentItemName
        self.wasCancelled = wasCancelled
        self.exportedFileNames = exportedFileNames
        self.failures = failures
        self.outputDirectoryPath = outputDirectoryPath
    }

    package var progress: Double {
        guard totalCount > 0 else {
            return isExporting ? 0 : 1
        }
        return min(max(Double(completedCount) / Double(totalCount), 0), 1)
    }

    package var statusText: String {
        if wasCancelled {
            return "Batch export cancelled after \(completedCount) of \(totalCount)."
        }
        if isExporting {
            if let currentItemName {
                return "Exporting \(currentItemName) (\(completedCount + 1) of \(totalCount))"
            }
            return "Preparing batch export"
        }
        if totalCount > 0 {
            if !failures.isEmpty {
                return "Exported \(exportedFileNames.count) of \(totalCount); \(failures.count) failed."
            }
            return "Exported \(completedCount) of \(totalCount)."
        }
        return "Idle"
    }

    package var diagnostics: BatchExportDiagnostics {
        BatchExportDiagnostics(
            outputDirectoryPath: outputDirectoryPath,
            summary: statusText,
            exportedFileNames: exportedFileNames,
            failures: failures
        )
    }
}

package struct RawDevelopmentSettings: Codable, Equatable, Hashable {
    package var enabled: Bool
    package var exposureEV: Double
    package var temperatureK: Double
    package var tint: Double
    package var highlightRecovery: Double

    package init(
        enabled: Bool = true,
        exposureEV: Double = 0,
        temperatureK: Double = 5500,
        tint: Double = 0,
        highlightRecovery: Double = 0.25
    ) {
        self.enabled = enabled
        self.exposureEV = Self.clamped(exposureEV, lower: -2, upper: 2)
        self.temperatureK = Self.clamped(temperatureK, lower: 2500, upper: 9000)
        self.tint = Self.clamped(tint, lower: -1, upper: 1)
        self.highlightRecovery = Self.clamped(highlightRecovery, lower: 0, upper: 1)
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        exposureEV = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .exposureEV) ?? 0,
            lower: -2,
            upper: 2
        )
        temperatureK = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .temperatureK) ?? 5500,
            lower: 2500,
            upper: 9000
        )
        tint = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
            lower: -1,
            upper: 1
        )
        highlightRecovery = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .highlightRecovery) ?? 0.25,
            lower: 0,
            upper: 1
        )
    }

    package static let defaults = RawDevelopmentSettings()

    private enum CodingKeys: String, CodingKey {
        case enabled
        case exposureEV
        case temperatureK
        case tint
        case highlightRecovery
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

package struct ColorManagementSettings: Codable, Equatable, Hashable {
    package var inputIntent: String
    package var workingColorSpace: String
    package var outputColorSpace: String
    package var rawDevelopmentEnabled: Bool
    package var rawDevelopment: RawDevelopmentSettings

    package init(
        inputIntent: String = "embedded_or_camera_profile",
        workingColorSpace: String = "extended_linear_srgb",
        outputColorSpace: String = "srgb",
        rawDevelopmentEnabled: Bool = true,
        rawDevelopment: RawDevelopmentSettings = .defaults
    ) {
        self.inputIntent = inputIntent
        self.workingColorSpace = workingColorSpace
        self.outputColorSpace = ColorOutputProfile(rawProfileName: outputColorSpace).rawValue
        self.rawDevelopmentEnabled = rawDevelopmentEnabled
        self.rawDevelopment = rawDevelopment
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputIntent = try container.decodeIfPresent(String.self, forKey: .inputIntent) ?? "embedded_or_camera_profile"
        workingColorSpace = try container.decodeIfPresent(String.self, forKey: .workingColorSpace) ?? "extended_linear_srgb"
        let decodedOutputColorSpace = try container.decodeIfPresent(String.self, forKey: .outputColorSpace) ?? "srgb"
        outputColorSpace = ColorOutputProfile(rawProfileName: decodedOutputColorSpace).rawValue
        rawDevelopmentEnabled = try container.decodeIfPresent(Bool.self, forKey: .rawDevelopmentEnabled) ?? true
        rawDevelopment = try container.decodeIfPresent(RawDevelopmentSettings.self, forKey: .rawDevelopment) ?? .defaults
    }

    package static let defaults = ColorManagementSettings()

    private enum CodingKeys: String, CodingKey {
        case inputIntent
        case workingColorSpace
        case outputColorSpace
        case rawDevelopmentEnabled
        case rawDevelopment
    }
}

package enum ColorOutputProfile: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case sRGB = "srgb"
    case displayP3 = "display_p3"
    case extendedSRGB = "extended_srgb"
    case extendedLinearSRGB = "extended_linear_srgb"
    case linearSRGB = "linear_srgb"

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .sRGB:
            return "sRGB"
        case .displayP3:
            return "Display P3"
        case .extendedSRGB:
            return "Extended sRGB"
        case .extendedLinearSRGB:
            return "Extended Linear sRGB"
        case .linearSRGB:
            return "Linear sRGB"
        }
    }

    package init(rawProfileName: String) {
        let normalized = rawProfileName
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalized.contains("display_p3") || normalized == "p3" {
            self = .displayP3
        } else if normalized.contains("extended"), normalized.contains("linear") {
            self = .extendedLinearSRGB
        } else if normalized.contains("extended") {
            self = .extendedSRGB
        } else if normalized.contains("linear") {
            self = .linearSRGB
        } else {
            self = .sRGB
        }
    }
}

package struct CalibrationDataStatus: Codable, Equatable, Hashable {
    package var supportsSpectralCurves: Bool
    package var supportsMeasuredDensityCurves: Bool
    package var supportsGrainSpectra: Bool
    package var supportsThreeDimensionalLUTs: Bool
    package var importedAssetNames: [String]
    package var importedAssetSummaries: [String]
    package var redScale: Double
    package var greenScale: Double
    package var blueScale: Double
    package var densityGamma: Double
    package var grainAmount: Double
    package var note: String

    package init(
        supportsSpectralCurves: Bool = false,
        supportsMeasuredDensityCurves: Bool = false,
        supportsGrainSpectra: Bool = false,
        supportsThreeDimensionalLUTs: Bool = false,
        importedAssetNames: [String] = [],
        importedAssetSummaries: [String] = [],
        redScale: Double = 1.0,
        greenScale: Double = 1.0,
        blueScale: Double = 1.0,
        densityGamma: Double = 1.0,
        grainAmount: Double = 0.0,
        note: String = "Profiles currently use descriptive values that can be replaced by calibrated datasets."
    ) {
        self.supportsSpectralCurves = supportsSpectralCurves
        self.supportsMeasuredDensityCurves = supportsMeasuredDensityCurves
        self.supportsGrainSpectra = supportsGrainSpectra
        self.supportsThreeDimensionalLUTs = supportsThreeDimensionalLUTs
        self.importedAssetNames = importedAssetNames
        self.importedAssetSummaries = importedAssetSummaries
        self.redScale = Self.clamped(redScale, lower: 0.5, upper: 1.5)
        self.greenScale = Self.clamped(greenScale, lower: 0.5, upper: 1.5)
        self.blueScale = Self.clamped(blueScale, lower: 0.5, upper: 1.5)
        self.densityGamma = Self.clamped(densityGamma, lower: 0.75, upper: 1.35)
        self.grainAmount = Self.clamped(grainAmount, lower: 0, upper: 0.25)
        self.note = note
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportsSpectralCurves = try container.decodeIfPresent(Bool.self, forKey: .supportsSpectralCurves) ?? false
        supportsMeasuredDensityCurves = try container.decodeIfPresent(Bool.self, forKey: .supportsMeasuredDensityCurves) ?? false
        supportsGrainSpectra = try container.decodeIfPresent(Bool.self, forKey: .supportsGrainSpectra) ?? false
        supportsThreeDimensionalLUTs = try container.decodeIfPresent(Bool.self, forKey: .supportsThreeDimensionalLUTs) ?? false
        importedAssetNames = try container.decodeIfPresent([String].self, forKey: .importedAssetNames) ?? []
        importedAssetSummaries = try container.decodeIfPresent([String].self, forKey: .importedAssetSummaries) ?? []
        redScale = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .redScale) ?? 1.0,
            lower: 0.5,
            upper: 1.5
        )
        greenScale = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .greenScale) ?? 1.0,
            lower: 0.5,
            upper: 1.5
        )
        blueScale = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .blueScale) ?? 1.0,
            lower: 0.5,
            upper: 1.5
        )
        densityGamma = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .densityGamma) ?? 1.0,
            lower: 0.75,
            upper: 1.35
        )
        grainAmount = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .grainAmount) ?? 0.0,
            lower: 0,
            upper: 0.25
        )
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? CalibrationDataStatus.descriptiveOnly.note
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(supportsSpectralCurves, forKey: .supportsSpectralCurves)
        try container.encode(supportsMeasuredDensityCurves, forKey: .supportsMeasuredDensityCurves)
        try container.encode(supportsGrainSpectra, forKey: .supportsGrainSpectra)
        try container.encode(supportsThreeDimensionalLUTs, forKey: .supportsThreeDimensionalLUTs)
        try container.encode(importedAssetNames, forKey: .importedAssetNames)
        try container.encode(importedAssetSummaries, forKey: .importedAssetSummaries)
        try container.encode(redScale, forKey: .redScale)
        try container.encode(greenScale, forKey: .greenScale)
        try container.encode(blueScale, forKey: .blueScale)
        try container.encode(densityGamma, forKey: .densityGamma)
        try container.encode(grainAmount, forKey: .grainAmount)
        try container.encode(note, forKey: .note)
    }

    package static let descriptiveOnly = CalibrationDataStatus()

    private enum CodingKeys: String, CodingKey {
        case supportsSpectralCurves
        case supportsMeasuredDensityCurves
        case supportsGrainSpectra
        case supportsThreeDimensionalLUTs
        case importedAssetNames
        case importedAssetSummaries
        case redScale
        case greenScale
        case blueScale
        case densityGamma
        case grainAmount
        case note
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
