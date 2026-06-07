import Foundation

package struct FilmRecipe: Codable, Hashable, Identifiable {
    package let schemaVersion: String
    package let profileId: String
    package let displayName: String
    package let manufacturer: String
    package let summary: String
    package let format: FilmFormat
    package let stock: FilmStock
    package let input: FilmInput
    package let exposure: FilmExposure
    package let captureConditions: FilmCaptureConditions
    package let layerModel: FilmLayerModel
    package let characteristicCurves: FilmCharacteristicCurves
    package let colourModel: FilmColourModel
    package let process: FilmProcess
    package let grain: FilmGrain
    package let halation: FilmHalation
    package let sharpness: FilmSharpness
    package let renderer: FilmRenderer
    package let output: FilmOutput
    package let calibration: FilmCalibration

    package var id: String { profileId }
    package var name: String { displayName }
    package var maker: String { manufacturer }
    package var iso: Int { stock.boxSpeedIso }
    package var stockType: FilmStockType { FilmStockType(family: stock.family) }
}

package struct FilmFormat: Codable, Hashable {
    package let type: String
    package let frameSizeMm: FilmFrameSize
    package let defaultAspectRatio: Double
}

package struct FilmFrameSize: Codable, Hashable {
    package let width: Double
    package let height: Double
}

package struct FilmStock: Codable, Hashable {
    package let family: FilmStockFamily
    package let process: String
    package let boxSpeedIso: Int
    package let nativeBalance: String
    package let nativeColourTemperatureK: Int?
    package let hasOrangeMask: Bool
    package let hasRemjet: Bool
    package let antiHalation: String
}

package enum FilmStockFamily: String, Codable, Hashable {
    case blackAndWhiteNegative = "black_and_white_negative"
    case colourNegative = "colour_negative"
    case colourReversal = "colour_reversal"
    case motionPictureNegative = "motion_picture_negative"
    case specialty = "specialty"

    package var label: String {
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

package struct FilmInput: Codable, Hashable {
    package let preferredSource: String
    package let workingSpace: String
    package let requiresSceneLinear: Bool
}

package struct FilmExposure: Codable, Hashable {
    package let boxSpeedIso: Int
    package let exposedAtIso: Int
    package let exposureCompensationEv: Double
    package let middleGrey: Double
    package let highlightProtection: Double?
    package let shadowLiftBeforeFilm: Double?
}

package struct FilmCaptureConditions: Codable, Hashable {
    package let illuminant: String
    package let colourTemperatureK: Int
    package let lensContrast: Double?
    package let lensFlare: Double?
    package let filter: FilmCaptureFilter
    package let daylightMode: FilmDaylightMode?
}

package struct FilmCaptureFilter: Codable, Hashable {
    package let type: String
    package let strength: Double
}

package struct FilmDaylightMode: Codable, Hashable {
    package let enabled: Bool
    package let recommendedFilter: String?
    package let recommendedExposedAtIso: Int?
}

package struct FilmLayerModel: Codable, Hashable {
    package let type: String
    package let layers: [String]
    package let rgbToLayerMatrix: [[Double]]
}

package struct FilmCharacteristicCurves: Codable, Hashable {
    package let curveSpace: String
    package let channels: [String: FilmCharacteristicCurve]
}

package struct FilmCharacteristicCurve: Codable, Hashable {
    package let toe: Double
    package let gamma: Double
    package let shoulder: Double
    package let dMin: Double
    package let dMax: Double
}

package struct FilmColourModel: Codable, Hashable {
    package let palette: String
    package let saturation: Double?
    package let warmth: Double?
    package let hueBias: FilmHueBias?
    package let skinToneProtection: Double?
    package let orangeMask: FilmOrangeMask?
    package let toning: FilmToning?
}

package struct FilmHueBias: Codable, Hashable {
    package let reds: Double
    package let yellows: Double
    package let greens: Double
    package let cyans: Double
    package let blues: Double
    package let magentas: Double
}

package struct FilmOrangeMask: Codable, Hashable {
    package let enabled: Bool
    package let density: FilmChannelValues
}

package struct FilmToning: Codable, Hashable {
    package let enabled: Bool
    package let warmth: Double
    package let selenium: Double
}

package struct FilmProcess: Codable, Hashable {
    package let type: String
    package let variant: String
    package let developerStyle: String?
    package let pushPullStops: Double
    package let contrastMultiplier: Double
    package let speedGainEv: Double
    package let grainMultiplier: Double
    package let colourShift: FilmRGB?
}

package struct FilmGrain: Codable, Hashable {
    package let enabled: Bool
    package let model: String
    package let strength: Double
    package let size: Double
    package let clumpiness: Double
    package let softness: Double
    package let tonalDistribution: FilmTonalDistribution?
    package let chromaticity: Double
    package let channelVariance: FilmChannelValues?
    package let formatScale: String?
    package let seedMode: String?
}

package struct FilmTonalDistribution: Codable, Hashable {
    package let shadow: Double
    package let midtone: Double
    package let highlight: Double
}

package struct FilmHalation: Codable, Hashable {
    package let enabled: Bool
    package let model: String
    package let threshold: Double
    package let strength: Double
    package let radius: Double
    package let colour: FilmRGB
    package let affects: String?
    package let edgePreservation: Double?
}

package struct FilmSharpness: Codable, Hashable {
    package let filmMtfBlur: Double
    package let scannerMtfBlur: Double
    package let acutance: Double
    package let digitalSharpening: Double
}

package struct FilmRenderer: Codable, Hashable {
    package let type: String
    package let negativeInversion: Bool
    package let autoExposure: Double
    package let autoWhiteBalance: Double
    package let blackPoint: Double
    package let whitePoint: Double
    package let contrast: Double
    package let saturation: Double
    package let sharpening: Double?
    package let scannerMtf: FilmScannerMTF?
}

package struct FilmScannerMTF: Codable, Hashable {
    package let blurRadius: Double
    package let microcontrast: Double
}

package struct FilmOutput: Codable, Hashable {
    package let colourSpace: String
    package let bitDepth: Int
    package let dither: Bool
}

package struct FilmCalibration: Codable, Hashable {
    package let confidence: String
    package let source: String
    package let notes: String
}

package struct FilmRGB: Codable, Hashable {
    package let r: Double
    package let g: Double
    package let b: Double
}

package struct FilmChannelValues: Codable, Hashable {
    package let red: Double
    package let green: Double
    package let blue: Double
}

package enum FilmStockType: Hashable {
    case color
    case blackAndWhite
    case slide
    case motionPicture
    case specialty

    package init(family: FilmStockFamily) {
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

    package var label: String {
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

    package var systemImageName: String {
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

package struct RenderAdjustments: Codable, Equatable, Hashable {
    package var intensity: Double
    package var exposureTrim: Double
    package var contrastTrim: Double
    package var saturationTrim: Double
    package var grainEnabled: Bool

    package init(
        intensity: Double,
        exposureTrim: Double,
        contrastTrim: Double,
        saturationTrim: Double,
        grainEnabled: Bool
    ) {
        self.intensity = intensity
        self.exposureTrim = exposureTrim
        self.contrastTrim = contrastTrim
        self.saturationTrim = saturationTrim
        self.grainEnabled = grainEnabled
    }

    package static let defaults = RenderAdjustments(
        intensity: 1.0,
        exposureTrim: 0.0,
        contrastTrim: 0.0,
        saturationTrim: 0.0,
        grainEnabled: true
    )
}
