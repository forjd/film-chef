import Foundation

struct FilmRecipe: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let maker: String
    let iso: Int
    let stockType: FilmStockType
    let summary: String
    let parameters: FilmRecipeParameters
}

enum FilmStockType: String, Codable, Hashable {
    case color
    case blackAndWhite

    var label: String {
        switch self {
        case .color:
            return "Color negative"
        case .blackAndWhite:
            return "Black and white"
        }
    }

    var systemImageName: String {
        switch self {
        case .color:
            return "camera.filters"
        case .blackAndWhite:
            return "circle.lefthalf.filled"
        }
    }
}

struct FilmRecipeParameters: Codable, Hashable {
    let exposure: Double
    let brightness: Double
    let contrast: Double
    let saturation: Double
    let temperature: Double
    let tint: Double
    let highlights: Double
    let shadows: Double
    let grain: Double
    let vignette: Double
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
