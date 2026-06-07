import Foundation

struct FilmRecipe: Codable, Hashable, Identifiable {
    let schemaVersion: String
    let profileId: String
    let displayName: String
    let manufacturer: String
    let summary: String
    let format: FilmFormat
    let stock: FilmStock
    let input: FilmInput
    let exposure: FilmExposure
    let captureConditions: FilmCaptureConditions
    let layerModel: FilmLayerModel
    let characteristicCurves: FilmCharacteristicCurves
    let colourModel: FilmColourModel
    let process: FilmProcess
    let grain: FilmGrain
    let halation: FilmHalation
    let sharpness: FilmSharpness
    let renderer: FilmRenderer
    let output: FilmOutput
    let calibration: FilmCalibration

    var id: String { profileId }
    var name: String { displayName }
    var maker: String { manufacturer }
    var iso: Int { stock.boxSpeedIso }
    var stockType: FilmStockType { FilmStockType(family: stock.family) }
}

struct FilmFormat: Codable, Hashable {
    let type: String
    let frameSizeMm: FilmFrameSize
    let defaultAspectRatio: Double
}

struct FilmFrameSize: Codable, Hashable {
    let width: Double
    let height: Double
}

struct FilmStock: Codable, Hashable {
    let family: FilmStockFamily
    let process: String
    let boxSpeedIso: Int
    let nativeBalance: String
    let nativeColourTemperatureK: Int?
    let hasOrangeMask: Bool
    let hasRemjet: Bool
    let antiHalation: String
}

enum FilmStockFamily: String, Codable, Hashable {
    case blackAndWhiteNegative = "black_and_white_negative"
    case colourNegative = "colour_negative"
    case colourReversal = "colour_reversal"
    case motionPictureNegative = "motion_picture_negative"
    case specialty = "specialty"

    var label: String {
        switch self {
        case .blackAndWhiteNegative:
            return "Black and white negative"
        case .colourNegative:
            return "Color negative"
        case .colourReversal:
            return "Color reversal"
        case .motionPictureNegative:
            return "Motion picture negative"
        case .specialty:
            return "Specialty stock"
        }
    }
}

struct FilmInput: Codable, Hashable {
    let preferredSource: String
    let workingSpace: String
    let requiresSceneLinear: Bool
}

struct FilmExposure: Codable, Hashable {
    let boxSpeedIso: Int
    let exposedAtIso: Int
    let exposureCompensationEv: Double
    let middleGrey: Double
    let highlightProtection: Double?
    let shadowLiftBeforeFilm: Double?
}

struct FilmCaptureConditions: Codable, Hashable {
    let illuminant: String
    let colourTemperatureK: Int
    let lensContrast: Double?
    let lensFlare: Double?
    let filter: FilmCaptureFilter
    let daylightMode: FilmDaylightMode?
}

struct FilmCaptureFilter: Codable, Hashable {
    let type: String
    let strength: Double
}

struct FilmDaylightMode: Codable, Hashable {
    let enabled: Bool
    let recommendedFilter: String?
    let recommendedExposedAtIso: Int?
}

struct FilmLayerModel: Codable, Hashable {
    let type: String
    let layers: [String]
    let rgbToLayerMatrix: [[Double]]
}

struct FilmCharacteristicCurves: Codable, Hashable {
    let curveSpace: String
    let channels: [String: FilmCharacteristicCurve]
}

struct FilmCharacteristicCurve: Codable, Hashable {
    let toe: Double
    let gamma: Double
    let shoulder: Double
    let dMin: Double
    let dMax: Double
}

struct FilmColourModel: Codable, Hashable {
    let palette: String
    let saturation: Double?
    let warmth: Double?
    let hueBias: FilmHueBias?
    let skinToneProtection: Double?
    let orangeMask: FilmOrangeMask?
    let toning: FilmToning?
}

struct FilmHueBias: Codable, Hashable {
    let reds: Double
    let yellows: Double
    let greens: Double
    let cyans: Double
    let blues: Double
    let magentas: Double
}

struct FilmOrangeMask: Codable, Hashable {
    let enabled: Bool
    let density: FilmChannelValues
}

struct FilmToning: Codable, Hashable {
    let enabled: Bool
    let warmth: Double
    let selenium: Double
}

struct FilmProcess: Codable, Hashable {
    let type: String
    let variant: String
    let developerStyle: String?
    let pushPullStops: Double
    let contrastMultiplier: Double
    let speedGainEv: Double
    let grainMultiplier: Double
    let colourShift: FilmRGB?
}

struct FilmGrain: Codable, Hashable {
    let enabled: Bool
    let model: String
    let strength: Double
    let size: Double
    let clumpiness: Double
    let softness: Double
    let tonalDistribution: FilmTonalDistribution?
    let chromaticity: Double
    let channelVariance: FilmChannelValues?
    let formatScale: String?
    let seedMode: String?
}

struct FilmTonalDistribution: Codable, Hashable {
    let shadow: Double
    let midtone: Double
    let highlight: Double
}

struct FilmHalation: Codable, Hashable {
    let enabled: Bool
    let model: String
    let threshold: Double
    let strength: Double
    let radius: Double
    let colour: FilmRGB
    let affects: String?
    let edgePreservation: Double?
}

struct FilmSharpness: Codable, Hashable {
    let filmMtfBlur: Double
    let scannerMtfBlur: Double
    let acutance: Double
    let digitalSharpening: Double
}

struct FilmRenderer: Codable, Hashable {
    let type: String
    let negativeInversion: Bool
    let autoExposure: Double
    let autoWhiteBalance: Double
    let blackPoint: Double
    let whitePoint: Double
    let contrast: Double
    let saturation: Double
    let sharpening: Double?
    let scannerMtf: FilmScannerMTF?
}

struct FilmScannerMTF: Codable, Hashable {
    let blurRadius: Double
    let microcontrast: Double
}

struct FilmOutput: Codable, Hashable {
    let colourSpace: String
    let bitDepth: Int
    let dither: Bool
}

struct FilmCalibration: Codable, Hashable {
    let confidence: String
    let source: String
    let notes: String
}

struct FilmRGB: Codable, Hashable {
    let r: Double
    let g: Double
    let b: Double
}

struct FilmChannelValues: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
}

enum FilmStockType: Hashable {
    case color
    case blackAndWhite
    case slide
    case motionPicture
    case specialty

    init(family: FilmStockFamily) {
        switch family {
        case .blackAndWhiteNegative:
            self = .blackAndWhite
        case .colourNegative:
            self = .color
        case .colourReversal:
            self = .slide
        case .motionPictureNegative:
            self = .motionPicture
        case .specialty:
            self = .specialty
        }
    }

    var label: String {
        switch self {
        case .color:
            return "Color negative"
        case .blackAndWhite:
            return "Black and white"
        case .slide:
            return "Color reversal"
        case .motionPicture:
            return "Motion picture"
        case .specialty:
            return "Specialty"
        }
    }

    var systemImageName: String {
        switch self {
        case .color:
            return "camera.filters"
        case .blackAndWhite:
            return "circle.lefthalf.filled"
        case .slide:
            return "rectangle.on.rectangle.angled"
        case .motionPicture:
            return "film"
        case .specialty:
            return "sparkles"
        }
    }
}

struct RenderAdjustments: Equatable {
    var intensity: Double
    var exposureTrim: Double
    var contrastTrim: Double
    var saturationTrim: Double
    var grainEnabled: Bool

    static let defaults = RenderAdjustments(
        intensity: 1.0,
        exposureTrim: 0.0,
        contrastTrim: 0.0,
        saturationTrim: 0.0,
        grainEnabled: true
    )
}
