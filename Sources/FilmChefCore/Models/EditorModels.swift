import Foundation

package struct FilmProject: Codable, Equatable {
    package var schemaVersion: Int
    package var id: UUID
    package var name: String
    package var items: [FilmProjectItem]
    package var selectedItemID: UUID?
    package var editHistory: [EditSnapshot]
    package var editHistoryIndex: Int?
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
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([FilmProjectItem].self, forKey: .items)
        selectedItemID = try container.decodeIfPresent(UUID.self, forKey: .selectedItemID)
        editHistory = try container.decode([EditSnapshot].self, forKey: .editHistory)
        editHistoryIndex = try container.decodeIfPresent(Int.self, forKey: .editHistoryIndex)
        exportSettings = try container.decode(ExportSettings.self, forKey: .exportSettings)
        exportPresets = try container.decodeIfPresent([ExportPreset].self, forKey: .exportPresets) ?? ExportPreset.defaults
        colorManagementSettings = try container.decode(ColorManagementSettings.self, forKey: .colorManagementSettings)
        calibrationDataStatus = try container.decode(CalibrationDataStatus.self, forKey: .calibrationDataStatus)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

package struct EditSnapshot: Codable, Equatable, Identifiable {
    package var id: UUID
    package var recipeID: String?
    package var adjustments: RenderAdjustments
    package var localAdjustments: [LocalAdjustmentLayer]
    package var note: String
    package var createdAt: Date

    package init(
        id: UUID = UUID(),
        recipeID: String?,
        adjustments: RenderAdjustments,
        localAdjustments: [LocalAdjustmentLayer] = [],
        note: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recipeID = recipeID
        self.adjustments = adjustments
        self.localAdjustments = localAdjustments
        self.note = note
        self.createdAt = createdAt
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        recipeID = try container.decodeIfPresent(String.self, forKey: .recipeID)
        adjustments = try container.decode(RenderAdjustments.self, forKey: .adjustments)
        localAdjustments = try container.decodeIfPresent([LocalAdjustmentLayer].self, forKey: .localAdjustments) ?? []
        note = try container.decode(String.self, forKey: .note)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
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
        self.centerX = centerX
        self.centerY = centerY
        self.radius = radius
        self.feather = feather
        self.brushSize = brushSize
        self.pathPoints = pathPoints
        self.exposureEV = exposureEV
        self.contrast = contrast
        self.saturation = saturation
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        mask = try container.decode(LocalAdjustmentMask.self, forKey: .mask)
        centerX = try container.decode(Double.self, forKey: .centerX)
        centerY = try container.decode(Double.self, forKey: .centerY)
        radius = try container.decode(Double.self, forKey: .radius)
        feather = try container.decode(Double.self, forKey: .feather)
        brushSize = try container.decodeIfPresent(Double.self, forKey: .brushSize) ?? 0.12
        pathPoints = try container.decodeIfPresent([NormalizedMaskPoint].self, forKey: .pathPoints) ?? Self.defaultPathPoints
        exposureEV = try container.decode(Double.self, forKey: .exposureEV)
        contrast = try container.decode(Double.self, forKey: .contrast)
        saturation = try container.decode(Double.self, forKey: .saturation)
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
}

package enum PreviewComparisonMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case edited
    case original
    case split
    case sideBySide

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .edited:
            return "Edited"
        case .original:
            return "Original"
        case .split:
            return "Split"
        case .sideBySide:
            return "Side by Side"
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
        self.jpegQuality = jpegQuality
        self.scale = scale
        self.preserveMetadata = preserveMetadata
        self.embedColorProfile = embedColorProfile
        self.namingTemplate = namingTemplate
    }

    package static let defaults = ExportSettings()
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

    package static let defaults = [
        ExportPreset(name: "Web JPEG", settings: ExportSettings(fileFormat: .jpeg, jpegQuality: 0.86, scale: 1.0, preserveMetadata: false, embedColorProfile: true, namingTemplate: "{photo}-{recipe}")),
        ExportPreset(name: "Archive TIFF", settings: ExportSettings(fileFormat: .tiff, jpegQuality: 1.0, scale: 1.0, preserveMetadata: true, embedColorProfile: true, namingTemplate: "{photo}-{recipe}-archive")),
        ExportPreset(name: "Review PNG", settings: ExportSettings(fileFormat: .png, jpegQuality: 1.0, scale: 0.5, preserveMetadata: false, embedColorProfile: true, namingTemplate: "{photo}-{recipe}-review"))
    ]
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

package struct BatchExportState: Codable, Equatable, Hashable {
    package var isExporting: Bool
    package var completedCount: Int
    package var totalCount: Int
    package var currentItemName: String?
    package var wasCancelled: Bool
    package var exportedFileNames: [String]

    package init(
        isExporting: Bool = false,
        completedCount: Int = 0,
        totalCount: Int = 0,
        currentItemName: String? = nil,
        wasCancelled: Bool = false,
        exportedFileNames: [String] = []
    ) {
        self.isExporting = isExporting
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.currentItemName = currentItemName
        self.wasCancelled = wasCancelled
        self.exportedFileNames = exportedFileNames
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
            return "Exported \(completedCount) of \(totalCount)."
        }
        return "Idle"
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
        self.exposureEV = exposureEV
        self.temperatureK = temperatureK
        self.tint = tint
        self.highlightRecovery = highlightRecovery
    }

    package static let defaults = RawDevelopmentSettings()
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
        self.outputColorSpace = outputColorSpace
        self.rawDevelopmentEnabled = rawDevelopmentEnabled
        self.rawDevelopment = rawDevelopment
    }

    package static let defaults = ColorManagementSettings()
}

package struct CalibrationDataStatus: Codable, Equatable, Hashable {
    package var supportsSpectralCurves: Bool
    package var supportsMeasuredDensityCurves: Bool
    package var supportsGrainSpectra: Bool
    package var supportsThreeDimensionalLUTs: Bool
    package var importedAssetNames: [String]
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
        self.redScale = redScale
        self.greenScale = greenScale
        self.blueScale = blueScale
        self.densityGamma = densityGamma
        self.grainAmount = grainAmount
        self.note = note
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportsSpectralCurves = try container.decode(Bool.self, forKey: .supportsSpectralCurves)
        supportsMeasuredDensityCurves = try container.decode(Bool.self, forKey: .supportsMeasuredDensityCurves)
        supportsGrainSpectra = try container.decodeIfPresent(Bool.self, forKey: .supportsGrainSpectra) ?? false
        supportsThreeDimensionalLUTs = try container.decode(Bool.self, forKey: .supportsThreeDimensionalLUTs)
        importedAssetNames = try container.decode([String].self, forKey: .importedAssetNames)
        redScale = try container.decode(Double.self, forKey: .redScale)
        greenScale = try container.decode(Double.self, forKey: .greenScale)
        blueScale = try container.decode(Double.self, forKey: .blueScale)
        densityGamma = try container.decodeIfPresent(Double.self, forKey: .densityGamma) ?? 1.0
        grainAmount = try container.decodeIfPresent(Double.self, forKey: .grainAmount) ?? 0.0
        note = try container.decode(String.self, forKey: .note)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(supportsSpectralCurves, forKey: .supportsSpectralCurves)
        try container.encode(supportsMeasuredDensityCurves, forKey: .supportsMeasuredDensityCurves)
        try container.encode(supportsGrainSpectra, forKey: .supportsGrainSpectra)
        try container.encode(supportsThreeDimensionalLUTs, forKey: .supportsThreeDimensionalLUTs)
        try container.encode(importedAssetNames, forKey: .importedAssetNames)
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
        case redScale
        case greenScale
        case blueScale
        case densityGamma
        case grainAmount
        case note
    }
}
