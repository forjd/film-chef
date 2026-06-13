import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

package final class ImageProcessor {
    private static let defaultPreviewMaxDimension: CGFloat = 4096

    package enum ImageProcessorError: LocalizedError {
        case cannotLoadImage
        case cannotRenderImage
        case cannotEncodeImage
        case cannotSampleImage

        package var errorDescription: String? {
            switch self {
            case .cannotLoadImage:
                return "The selected photo could not be loaded."
            case .cannotRenderImage:
                return "The edited photo could not be rendered."
            case .cannotEncodeImage:
                return "The edited photo could not be encoded for export."
            case .cannotSampleImage:
                return "The edited photo could not be sampled for analysis."
            }
        }
    }

    private let context = CIContext()
    private let pipelineRenderer = FilmPipelineRenderer()
    private let bitmapRepresentation: ((
        NSBitmapImageRep,
        NSBitmapImageRep.FileType,
        [NSBitmapImageRep.PropertyKey: Any]
    ) -> Data?)?

    package init(
        bitmapRepresentation: ((
            NSBitmapImageRep,
            NSBitmapImageRep.FileType,
            [NSBitmapImageRep.PropertyKey: Any]
        ) -> Data?)? = nil
    ) {
        self.bitmapRepresentation = bitmapRepresentation
    }

    package func loadSourceImage(
        from url: URL,
        colorSettings: ColorManagementSettings = .defaults,
        treatAsRaw: Bool? = nil
    ) throws -> CIImage {
        let isRawSource = treatAsRaw ?? Self.isRawImage(at: url)
        guard let image = CIImage(contentsOf: url, options: sourceImageOptions(for: colorSettings)),
              let rendered = context.createCGImage(
                  isRawSource ? applyRawDevelopment(to: image, settings: colorSettings) : image,
                  from: image.extent,
                  format: .RGBAh,
                  colorSpace: workingColorSpace(for: colorSettings.workingColorSpace)
              )
        else {
            throw ImageProcessorError.cannotLoadImage
        }

        return CIImage(cgImage: rendered)
    }

    private static func isRawImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier)
        else {
            return false
        }

        return type.conforms(to: .rawImage)
    }

    package func validateReadableImage(at url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else {
            throw ImageProcessorError.cannotLoadImage
        }
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
        localAdjustments: [LocalAdjustmentLayer] = [],
        calibration: CalibrationDataStatus = .descriptiveOnly,
        maxDimension: CGFloat = ImageProcessor.defaultPreviewMaxDimension
    ) throws -> NSImage {
        try makeNSImage(from: renderedPreviewSource(
            from: source,
            recipe: recipe,
            adjustments: adjustments,
            localAdjustments: localAdjustments,
            calibration: calibration,
            maxDimension: maxDimension
        ))
    }

    package func renderedPreviewSource(
        from source: CIImage,
        recipe: FilmRecipe,
        adjustments: RenderAdjustments,
        localAdjustments: [LocalAdjustmentLayer] = [],
        calibration: CalibrationDataStatus = .descriptiveOnly,
        maxDimension: CGFloat = ImageProcessor.defaultPreviewMaxDimension
    ) -> CIImage {
        let previewSource = scaleForPreview(source, maxDimension: maxDimension)
        let longestSide = max(source.extent.width, source.extent.height)
        let spatialScale = (maxDimension > 0 && longestSide > maxDimension)
            ? Double(maxDimension / longestSide)
            : 1.0
        let rendered = pipelineRenderer.render(
            source: previewSource,
            recipe: recipe,
            adjustments: adjustments,
            calibration: calibration,
            spatialScale: spatialScale
        )
        return applyLocalAdjustments(localAdjustments, to: rendered)
    }

    package func makeNSImageAndHistogramSummary(
        from image: CIImage,
        bins: Int = 32,
        histogramMaxDimension: CGFloat = 512
    ) throws -> (image: NSImage, histogram: HistogramSummary) {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw ImageProcessorError.cannotRenderImage
        }

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: image.extent.width, height: image.extent.height)
        )
        // Reusing the rendered bitmap avoids evaluating the filter graph a
        // second time just for the histogram.
        let histogram = try histogramSummary(from: cgImage, bins: bins, maxDimension: histogramMaxDimension)
        return (nsImage, histogram)
    }

    package func makeNSImageForTesting(from image: CIImage) throws -> NSImage {
        try makeNSImage(from: image)
    }

    package func writeRenderedImage(
        from source: CIImage,
        recipe: FilmRecipe,
        adjustments: RenderAdjustments,
        to url: URL,
        settings: ExportSettings = .defaults,
        localAdjustments: [LocalAdjustmentLayer] = [],
        calibration: CalibrationDataStatus = .descriptiveOnly,
        colorSettings: ColorManagementSettings = .defaults,
        sourceMetadataURL: URL? = nil
    ) throws {
        var rendered = pipelineRenderer.render(
            source: source,
            recipe: recipe,
            adjustments: adjustments,
            calibration: calibration
        )
        rendered = applyLocalAdjustments(localAdjustments, to: rendered)

        if settings.scale > 0, abs(settings.scale - 1.0) > 0.001 {
            rendered = rendered.applyingFilter(
                "CILanczosScaleTransform",
                parameters: [
                    kCIInputScaleKey: CGFloat(settings.scale),
                    kCIInputAspectRatioKey: 1.0
                ]
            )
        }

        let fileType = exportFileType(for: url, settings: settings)
        let outputColorSpace = outputColorSpace(for: colorSettings.outputColorSpace)
        // Rendering must always color-match into the output space; skipping the
        // match writes linear working-space pixels that viewers read as encoded.
        // "Embed color profile" only controls whether the file keeps the tag.
        let pixelFormat: CIFormat = recipe.output.bitDepth >= 16 && fileType != .jpeg ? .RGBA16 : .RGBA8
        guard let matchedImage = context.createCGImage(
            rendered,
            from: rendered.extent,
            format: pixelFormat,
            colorSpace: outputColorSpace
        ) else {
            throw ImageProcessorError.cannotRenderImage
        }

        let cgImage = settings.embedColorProfile
            ? matchedImage
            : (matchedImage.copy(colorSpace: CGColorSpaceCreateDeviceRGB()) ?? matchedImage)
        let representation = NSBitmapImageRep(cgImage: cgImage)
        var bitmapProperties: [NSBitmapImageRep.PropertyKey: Any]

        if fileType == .jpeg {
            bitmapProperties = [.compressionFactor: clamped(settings.jpegQuality, lower: 0.1, upper: 1.0)]
        } else {
            bitmapProperties = [:]
        }

        if settings.preserveMetadata {
            bitmapProperties[.exifData] = [
                "Software": "Film Chef",
                "ImageDescription": "Rendered with Film Chef"
            ]
        }

        if let bitmapRepresentation {
            guard let data = bitmapRepresentation(representation, fileType, bitmapProperties) else {
                throw ImageProcessorError.cannotEncodeImage
            }

            try data.write(to: url, options: [.atomic])
            return
        }

        let data = try makeImageIOData(
            from: cgImage,
            fileType: fileType,
            settings: settings,
            profileName: outputProfileName(for: colorSettings.outputColorSpace),
            sourceMetadataURL: sourceMetadataURL
        )
        try data.write(to: url, options: [.atomic])
    }

    package func makeHistogramSummary(
        from image: CIImage,
        bins: Int = 32,
        maxDimension: CGFloat = 512
    ) throws -> HistogramSummary {
        let sampledImage = scaleForPreview(image, maxDimension: maxDimension)
        guard let cgImage = context.createCGImage(sampledImage, from: sampledImage.extent) else {
            throw ImageProcessorError.cannotSampleImage
        }

        return try histogramSummary(from: cgImage, bins: bins, maxDimension: maxDimension)
    }

    private func histogramSummary(
        from cgImage: CGImage,
        bins: Int,
        maxDimension: CGFloat
    ) throws -> HistogramSummary {
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let longestSide = max(sourceWidth, sourceHeight)
        let scale = (maxDimension > 0 && longestSide > maxDimension) ? maxDimension / longestSide : 1
        let width = max(1, Int((sourceWidth * scale).rounded()))
        let height = max(1, Int((sourceHeight * scale).rounded()))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageProcessorError.cannotSampleImage
        }

        // The context must only live inside withUnsafeMutableBytes; passing
        // &bytes directly would leave it holding a dangling pointer.
        let didDraw = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let bitmapContext = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }

            bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard didDraw else {
            throw ImageProcessorError.cannotSampleImage
        }

        let safeBins = max(2, bins)
        var red = [Double](repeating: 0, count: safeBins)
        var green = [Double](repeating: 0, count: safeBins)
        var blue = [Double](repeating: 0, count: safeBins)
        var luminance = [Double](repeating: 0, count: safeBins)
        var redParade = [Double](repeating: 0, count: safeBins)
        var greenParade = [Double](repeating: 0, count: safeBins)
        var blueParade = [Double](repeating: 0, count: safeBins)
        let pixelCount = width * height
        var shadowClipped = 0
        var highlightClipped = 0

        for offset in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
            let r = Double(bytes[offset])
            let g = Double(bytes[offset + 1])
            let b = Double(bytes[offset + 2])
            red[histogramBin(for: r, bins: safeBins)] += 1
            green[histogramBin(for: g, bins: safeBins)] += 1
            blue[histogramBin(for: b, bins: safeBins)] += 1
            let y = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
            luminance[histogramBin(for: y, bins: safeBins)] += 1
            let pixelIndex = offset / bytesPerPixel
            let x = pixelIndex % width
            let paradeBin = min(max(Int((Double(x) / max(Double(width - 1), 1)) * Double(safeBins - 1)), 0), safeBins - 1)
            redParade[paradeBin] += r / 255.0
            greenParade[paradeBin] += g / 255.0
            blueParade[paradeBin] += b / 255.0

            if r <= 1, g <= 1, b <= 1 {
                shadowClipped += 1
            }
            if r >= 254, g >= 254, b >= 254 {
                highlightClipped += 1
            }
        }

        return HistogramSummary(
            red: normalisedHistogram(red, pixelCount: pixelCount),
            green: normalisedHistogram(green, pixelCount: pixelCount),
            blue: normalisedHistogram(blue, pixelCount: pixelCount),
            luminance: normalisedHistogram(luminance, pixelCount: pixelCount),
            redParade: normalisedParade(redParade, width: width, height: height),
            greenParade: normalisedParade(greenParade, width: width, height: height),
            blueParade: normalisedParade(blueParade, width: width, height: height),
            sampleCount: pixelCount,
            shadowClippingRatio: Double(shadowClipped) / max(Double(pixelCount), 1),
            highlightClippingRatio: Double(highlightClipped) / max(Double(pixelCount), 1)
        )
    }

    package func samplePixel(
        from image: CIImage,
        normalisedX: Double,
        normalisedY: Double
    ) throws -> PixelSample {
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1 else {
            throw ImageProcessorError.cannotSampleImage
        }

        let clampedX = min(max(normalisedX, 0), 1)
        let clampedY = min(max(normalisedY, 0), 1)
        let sampleX = extent.minX + CGFloat(clampedX * Double(extent.width - 1))
        let sampleY = extent.minY + CGFloat(clampedY * Double(extent.height - 1))
        let sampleBounds = CGRect(
            x: sampleX.rounded(.down),
            y: sampleY.rounded(.down),
            width: 1,
            height: 1
        )
        var bytes = [UInt8](repeating: 0, count: 4)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageProcessorError.cannotSampleImage
        }
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: sampleBounds,
            format: .RGBA8,
            colorSpace: colorSpace
        )

        let r = Double(bytes[0]) / 255.0
        let g = Double(bytes[1]) / 255.0
        let b = Double(bytes[2]) / 255.0
        return PixelSample(
            x: clampedX,
            y: clampedY,
            red: r,
            green: g,
            blue: b,
            luminance: (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
        )
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

    private func applyRawDevelopment(to image: CIImage, settings: ColorManagementSettings) -> CIImage {
        guard settings.rawDevelopmentEnabled, settings.rawDevelopment.enabled else {
            return image
        }

        var output = image
        let raw = settings.rawDevelopment

        if abs(raw.exposureEV) > 0.001 {
            output = output.applyingFilter(
                "CIExposureAdjust",
                parameters: ["inputEV": raw.exposureEV]
            )
        }

        if abs(raw.temperatureK - 5500) > 1 || abs(raw.tint) > 0.001 {
            output = output.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 5500, y: 0),
                    "inputTargetNeutral": CIVector(x: CGFloat(raw.temperatureK), y: CGFloat(raw.tint * 100))
                ]
            )
        }

        if raw.highlightRecovery > 0.001 {
            output = output.applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: [
                    "inputHighlightAmount": clamped(1.0 - raw.highlightRecovery, lower: 0.0, upper: 1.0),
                    "inputShadowAmount": 0.0
                ]
            )
        }

        return output
    }

    private func sourceImageOptions(for settings: ColorManagementSettings) -> [CIImageOption: Any] {
        var options: [CIImageOption: Any] = [.applyOrientationProperty: true]

        let normalizedIntent = settings.inputIntent
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalizedIntent.contains("device_rgb") || normalizedIntent == "device" {
            options[.colorSpace] = CGColorSpaceCreateDeviceRGB()
        } else if normalizedIntent.contains("srgb") {
            options[.colorSpace] = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }

        return options
    }

    private func applyLocalAdjustments(_ layers: [LocalAdjustmentLayer], to image: CIImage) -> CIImage {
        layers.reduce(image) { currentImage, layer in
            guard layer.isEnabled else {
                return currentImage
            }

            var adjusted = currentImage
            if abs(layer.exposureEV) > 0.001 {
                adjusted = adjusted.applyingFilter(
                    "CIExposureAdjust",
                    parameters: ["inputEV": layer.exposureEV]
                )
            }

            if abs(layer.contrast) > 0.001 || abs(layer.saturation) > 0.001 {
                adjusted = adjusted.applyingFilter(
                    "CIColorControls",
                    parameters: [
                        "inputSaturation": clamped(1.0 + layer.saturation, lower: 0.0, upper: 2.5),
                        "inputBrightness": 0.0,
                        "inputContrast": clamped(1.0 + layer.contrast, lower: 0.25, upper: 2.5)
                    ]
                )
            }

            let mask = localAdjustmentMask(for: layer, extent: currentImage.extent)
            return adjusted
                .applyingFilter(
                    "CIBlendWithMask",
                    parameters: [
                        "inputBackgroundImage": currentImage,
                        "inputMaskImage": mask
                    ]
                )
                .cropped(to: currentImage.extent)
        }
    }

    private func localAdjustmentMask(for layer: LocalAdjustmentLayer, extent: CGRect) -> CIImage {
        let center = CIVector(
            x: extent.minX + (extent.width * CGFloat(clamped(layer.centerX, lower: 0, upper: 1))),
            y: extent.minY + (extent.height * CGFloat(clamped(layer.centerY, lower: 0, upper: 1)))
        )
        let radius = max(1.0, min(extent.width, extent.height) * CGFloat(clamped(layer.radius, lower: 0.02, upper: 1)))
        let feather = max(1.0, radius * CGFloat(clamped(layer.feather, lower: 0.01, upper: 1)))

        switch layer.mask {
        case .radial:
            return CIFilter(
                name: "CIRadialGradient",
                parameters: [
                    "inputCenter": center,
                    "inputRadius0": max(0, radius - feather),
                    "inputRadius1": radius,
                    "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                    "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)
                ]
            )?.outputImage?.cropped(to: extent) ?? CIImage(color: .clear).cropped(to: extent)
        case .linear:
            let start = CIVector(x: center.x, y: extent.minY)
            let end = CIVector(x: center.x, y: extent.maxY)
            return CIFilter(
                name: "CILinearGradient",
                parameters: [
                    "inputPoint0": start,
                    "inputPoint1": end,
                    "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                    "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)
                ]
            )?.outputImage?.cropped(to: extent) ?? CIImage(color: .clear).cropped(to: extent)
        case .brush:
            return pathBackedMask(for: layer, extent: extent, closesPath: false)
        case .path:
            return pathBackedMask(for: layer, extent: extent, closesPath: true)
        }
    }

    private func pathBackedMask(
        for layer: LocalAdjustmentLayer,
        extent: CGRect,
        closesPath: Bool
    ) -> CIImage {
        let width = max(1, Int(extent.width.rounded(.up)))
        let height = max(1, Int(extent.height.rounded(.up)))
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return CIImage(color: .clear).cropped(to: extent)
        }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let points = normalizedMaskPoints(for: layer, closesPath: closesPath)
            .map { point in
                CGPoint(
                    x: CGFloat(clamped(point.x, lower: 0, upper: 1)) * CGFloat(width),
                    y: CGFloat(clamped(point.y, lower: 0, upper: 1)) * CGFloat(height)
                )
            }

        if closesPath, points.count >= 3 {
            context.beginPath()
            context.move(to: points[0])
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.closePath()
            context.fillPath()
        } else if points.count > 1 {
            context.setLineWidth(max(1, CGFloat(clamped(layer.brushSize, lower: 0.01, upper: 1)) * min(CGFloat(width), CGFloat(height))))
            context.beginPath()
            context.move(to: points[0])
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        } else if let point = points.first {
            let diameter = max(1, CGFloat(clamped(layer.brushSize, lower: 0.01, upper: 1)) * min(CGFloat(width), CGFloat(height)))
            context.fillEllipse(
                in: CGRect(
                    x: point.x - (diameter / 2),
                    y: point.y - (diameter / 2),
                    width: diameter,
                    height: diameter
                )
            )
        }

        guard let cgImage = context.makeImage() else {
            return CIImage(color: .clear).cropped(to: extent)
        }

        let featherRadius = CGFloat(clamped(layer.feather, lower: 0, upper: 1)) * min(extent.width, extent.height) * 0.08
        var mask = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        if featherRadius > 0.5 {
            mask = mask
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": featherRadius])
                .cropped(to: extent)
        }
        return mask.cropped(to: extent)
    }

    private func normalizedMaskPoints(for layer: LocalAdjustmentLayer, closesPath: Bool) -> [NormalizedMaskPoint] {
        if !layer.pathPoints.isEmpty {
            return layer.pathPoints
        }

        if closesPath {
            return LocalAdjustmentLayer.defaultPathPoints
        }

        return [
            NormalizedMaskPoint(x: layer.centerX, y: layer.centerY)
        ]
    }

    private func exportFileType(for url: URL, settings: ExportSettings) -> NSBitmapImageRep.FileType {
        switch url.pathExtension.lowercased() {
        case "png":
            return .png
        case "tif", "tiff":
            return .tiff
        case "jpg", "jpeg":
            return .jpeg
        default:
            break
        }

        switch settings.fileFormat {
        case .jpeg:
            return .jpeg
        case .png:
            return .png
        case .tiff:
            return .tiff
        }
    }

    private func makeImageIOData(
        from image: CGImage,
        fileType: NSBitmapImageRep.FileType,
        settings: ExportSettings,
        profileName: String,
        sourceMetadataURL: URL? = nil
    ) throws -> Data {
        let data = NSMutableData()
        guard let typeIdentifier = imageDestinationTypeIdentifier(for: fileType),
              let destination = CGImageDestinationCreateWithData(
                  data,
                  typeIdentifier as CFString,
                  1,
                  nil
              )
        else {
            throw ImageProcessorError.cannotEncodeImage
        }

        var properties: [CFString: Any] = [:]
        if fileType == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = clamped(settings.jpegQuality, lower: 0.1, upper: 1.0)
        }

        if settings.preserveMetadata {
            var tiff: [CFString: Any] = [:]
            var exif: [CFString: Any] = [:]

            if let sourceMetadataURL,
               let imageSource = CGImageSourceCreateWithURL(sourceMetadataURL as CFURL, nil),
               let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                tiff = sourceProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
                exif = sourceProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
                if let gps = sourceProperties[kCGImagePropertyGPSDictionary] {
                    properties[kCGImagePropertyGPSDictionary] = gps
                }
                if let iptc = sourceProperties[kCGImagePropertyIPTCDictionary] {
                    properties[kCGImagePropertyIPTCDictionary] = iptc
                }
                // Orientation is already baked into the rendered pixels at load time.
                tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            }

            tiff[kCGImagePropertyTIFFSoftware] = "Film Chef"
            if tiff[kCGImagePropertyTIFFImageDescription] == nil {
                tiff[kCGImagePropertyTIFFImageDescription] = "Rendered with Film Chef"
            }
            if exif[kCGImagePropertyExifUserComment] == nil {
                exif[kCGImagePropertyExifUserComment] = "Rendered with Film Chef"
            }
            properties[kCGImagePropertyTIFFDictionary] = tiff
            properties[kCGImagePropertyExifDictionary] = exif
        }

        if settings.embedColorProfile {
            properties[kCGImagePropertyProfileName] = profileName
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.cannotEncodeImage
        }

        return data as Data
    }

    private func outputColorSpace(for name: String) -> CGColorSpace {
        workingColorSpace(for: name)
    }

    private func workingColorSpace(for name: String) -> CGColorSpace {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalized.contains("display_p3") || normalized == "p3" {
            return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        }

        if normalized.contains("extended"), normalized.contains("linear") {
            return CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        }

        if normalized.contains("extended") {
            return CGColorSpace(name: CGColorSpace.extendedSRGB) ?? CGColorSpaceCreateDeviceRGB()
        }

        if normalized.contains("linear") {
            return CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        }

        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    private func outputProfileName(for name: String) -> String {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalized.contains("display_p3") || normalized == "p3" {
            return "Display P3"
        }

        if normalized.contains("extended"), normalized.contains("linear") {
            return "Extended Linear sRGB"
        }

        if normalized.contains("extended") {
            return "Extended sRGB"
        }

        if normalized.contains("linear") {
            return "Linear sRGB"
        }

        return "sRGB IEC61966-2.1"
    }

    private func imageDestinationTypeIdentifier(for fileType: NSBitmapImageRep.FileType) -> String? {
        switch fileType {
        case .jpeg:
            return UTType.jpeg.identifier
        case .png:
            return UTType.png.identifier
        case .tiff:
            return UTType.tiff.identifier
        default:
            return nil
        }
    }

    private func histogramBin(for value: Double, bins: Int) -> Int {
        min(max(Int((value / 255.0) * Double(bins)), 0), bins - 1)
    }

    private func normalisedHistogram(_ values: [Double], pixelCount: Int) -> [Double] {
        let denominator = max(Double(pixelCount), 1.0)
        return values.map { $0 / denominator }
    }

    private func normalisedParade(_ values: [Double], width: Int, height: Int) -> [Double] {
        let denominator = max(Double(height) * (Double(width) / max(Double(values.count), 1)), 1.0)
        return values.map { clamped($0 / denominator, lower: 0.0, upper: 1.0) }
    }

    private func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    package func inferredExportFormat(for url: URL) -> ExportFileFormat {
        switch url.pathExtension.lowercased() {
        case "png":
            return .png
        case "tif", "tiff":
            return .tiff
        default:
            return .jpeg
        }
    }

}
