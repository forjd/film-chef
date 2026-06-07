import AppKit
import CoreImage
import Foundation
import UniformTypeIdentifiers

final class ImageProcessor {
    enum ImageProcessorError: LocalizedError {
        case cannotLoadImage
        case cannotRenderImage
        case cannotEncodeImage

        var errorDescription: String? {
            switch self {
            case .cannotLoadImage:
                return "The selected photo could not be loaded."
            case .cannotRenderImage:
                return "The edited photo could not be rendered."
            case .cannotEncodeImage:
                return "The edited photo could not be encoded for export."
            }
        }
    }

    private let context = CIContext()

    func loadSourceImage(from url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              let rendered = context.createCGImage(image, from: image.extent)
        else {
            throw ImageProcessorError.cannotLoadImage
        }

        return CIImage(cgImage: rendered)
    }

    func makePreviewImage(from source: CIImage, maxDimension: CGFloat = 1800) throws -> NSImage {
        try makeNSImage(from: scaleForPreview(source, maxDimension: maxDimension))
    }

    func renderPreviewImage(
        from source: CIImage,
        recipe: FilmRecipe,
        adjustments: RenderAdjustments,
        maxDimension: CGFloat = 1800
    ) throws -> NSImage {
        let previewSource = scaleForPreview(source, maxDimension: maxDimension)
        let rendered = apply(recipe: recipe, to: previewSource, adjustments: adjustments)
        return try makeNSImage(from: rendered)
    }

    func writeRenderedImage(
        from source: CIImage,
        recipe: FilmRecipe,
        adjustments: RenderAdjustments,
        to url: URL
    ) throws {
        let rendered = apply(recipe: recipe, to: source, adjustments: adjustments)
        guard let cgImage = context.createCGImage(rendered, from: rendered.extent) else {
            throw ImageProcessorError.cannotRenderImage
        }

        let representation = NSBitmapImageRep(cgImage: cgImage)
        let fileType = exportFileType(for: url)
        let properties: [NSBitmapImageRep.PropertyKey: Any]

        if fileType == .jpeg {
            properties = [.compressionFactor: 0.92]
        } else {
            properties = [:]
        }

        guard let data = representation.representation(using: fileType, properties: properties) else {
            throw ImageProcessorError.cannotEncodeImage
        }

        try data.write(to: url)
    }

    private func apply(
        recipe: FilmRecipe,
        to source: CIImage,
        adjustments: RenderAdjustments
    ) -> CIImage {
        let extent = source.extent
        let parameters = recipe.parameters
        let intensity = clamped(adjustments.intensity, lower: 0.0, upper: 1.0)

        var output = source

        let exposure = parameters.exposure * intensity + adjustments.exposureTrim
        if abs(exposure) > 0.001 {
            output = output.applyingFilter(
                "CIExposureAdjust",
                parameters: ["inputEV": exposure]
            )
        }

        if recipe.stockType == .color {
            let targetTemperature = 6500.0 + parameters.temperature * intensity
            let targetTint = parameters.tint * intensity

            if abs(parameters.temperature) > 0.001 || abs(parameters.tint) > 0.001 {
                output = output.applyingFilter(
                    "CITemperatureAndTint",
                    parameters: [
                        "inputNeutral": CIVector(x: 6500, y: 0),
                        "inputTargetNeutral": CIVector(x: targetTemperature, y: targetTint)
                    ]
                )
            }
        }

        let contrast = clamped(
            1.0 + ((parameters.contrast - 1.0) * intensity) + adjustments.contrastTrim,
            lower: 0.25,
            upper: 2.5
        )
        let saturation = clamped(
            1.0 + ((parameters.saturation - 1.0) * intensity) + adjustments.saturationTrim,
            lower: 0.0,
            upper: 2.5
        )
        let brightness = parameters.brightness * intensity

        output = output.applyingFilter(
            "CIColorControls",
            parameters: [
                "inputSaturation": saturation,
                "inputBrightness": brightness,
                "inputContrast": contrast
            ]
        )

        if abs(parameters.highlights - 1.0) > 0.001 || abs(parameters.shadows) > 0.001 {
            output = output.applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: [
                    "inputHighlightAmount": 1.0 + ((parameters.highlights - 1.0) * intensity),
                    "inputShadowAmount": parameters.shadows * intensity
                ]
            )
        }

        if parameters.vignette > 0.001 {
            let radius = min(extent.width, extent.height) * 0.78
            output = output
                .clampedToExtent()
                .applyingFilter(
                    "CIVignetteEffect",
                    parameters: [
                        "inputCenter": CIVector(x: extent.midX, y: extent.midY),
                        "inputRadius": radius,
                        "inputIntensity": parameters.vignette * intensity
                    ]
                )
                .cropped(to: extent)
        }

        if adjustments.grainEnabled, parameters.grain > 0.001 {
            output = addGrain(
                to: output,
                extent: extent,
                amount: parameters.grain * intensity
            )
        }

        return output.cropped(to: extent)
    }

    private func addGrain(to image: CIImage, extent: CGRect, amount: Double) -> CIImage {
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else {
            return image
        }

        let alpha = CGFloat(clamped(amount, lower: 0.0, upper: 0.45))
        let noise = random
            .cropped(to: extent)
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 0.30, y: 0.30, z: 0.30, w: 0),
                    "inputGVector": CIVector(x: 0.30, y: 0.30, z: 0.30, w: 0),
                    "inputBVector": CIVector(x: 0.30, y: 0.30, z: 0.30, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
                ]
            )

        return noise
            .applyingFilter(
                "CISoftLightBlendMode",
                parameters: ["inputBackgroundImage": image]
            )
            .cropped(to: extent)
    }

    private func scaleForPreview(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let longestSide = max(image.extent.width, image.extent.height)

        guard longestSide > maxDimension else {
            return image
        }

        let scale = maxDimension / longestSide
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func makeNSImage(from image: CIImage) throws -> NSImage {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw ImageProcessorError.cannotRenderImage
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: image.extent.width, height: image.extent.height)
        )
    }

    private func exportFileType(for url: URL) -> NSBitmapImageRep.FileType {
        switch url.pathExtension.lowercased() {
        case "png":
            return .png
        default:
            return .jpeg
        }
    }

    private func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
