import AppKit
import CoreImage
import Foundation
import UniformTypeIdentifiers

package final class ImageProcessor {
    private static let defaultPreviewMaxDimension: CGFloat = 4096

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
    private let pipelineRenderer = FilmPipelineRenderer()

    package init() {}

    package func loadSourceImage(from url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              let rendered = context.createCGImage(image, from: image.extent)
        else {
            throw ImageProcessorError.cannotLoadImage
        }

        return CIImage(cgImage: rendered)
    }

    package func makePreviewImage(
        from source: CIImage,
        maxDimension: CGFloat = ImageProcessor.defaultPreviewMaxDimension
    ) throws -> NSImage {
        try makeNSImage(from: scaleForPreview(source, maxDimension: maxDimension))
    }

    package func renderPreviewImage(
        from source: CIImage,
        recipe: FilmRecipe,
        adjustments: RenderAdjustments,
        maxDimension: CGFloat = ImageProcessor.defaultPreviewMaxDimension
    ) throws -> NSImage {
        let previewSource = scaleForPreview(source, maxDimension: maxDimension)
        let rendered = pipelineRenderer.render(
            source: previewSource,
            recipe: recipe,
            adjustments: adjustments
        )
        return try makeNSImage(from: rendered)
    }

    package func writeRenderedImage(
        from source: CIImage,
        recipe: FilmRecipe,
        adjustments: RenderAdjustments,
        to url: URL
    ) throws {
        let rendered = pipelineRenderer.render(
            source: source,
            recipe: recipe,
            adjustments: adjustments
        )
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

    private func scaleForPreview(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        guard maxDimension > 0 else {
            return image
        }

        let longestSide = max(image.extent.width, image.extent.height)

        guard longestSide > maxDimension else {
            return image
        }

        let scale = maxDimension / longestSide
        return image.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0
            ]
        )
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

}
