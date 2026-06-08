import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import FilmChefCore

struct TestCase {
    let name: String
    let run: () throws -> Void
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    let file: StaticString
    let line: UInt

    var description: String {
        "\(file):\(line): \(message)"
    }
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "Expectation failed.",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    if !condition() {
        throw TestFailure(message: message(), file: file, line: line)
    }
}

func require<T>(
    _ value: @autoclosure () -> T?,
    _ message: @autoclosure () -> String = "Required value was nil.",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let unwrapped = value() else {
        throw TestFailure(message: message(), file: file, line: line)
    }

    return unwrapped
}

func loadTestRecipes() throws -> [FilmRecipe] {
    let recipes = try RecipeStore().loadRecipes()
    try expect(!recipes.isEmpty, "Expected bundled recipes to load.")
    return recipes
}

func makeRecipeObject(_ recipe: FilmRecipe) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let data = try encoder.encode(recipe)
    let jsonObject = try JSONSerialization.jsonObject(with: data)
    return try require(
        jsonObject as? [String: Any],
        "Expected recipe to encode as a JSON object."
    )
}

func setJSONValue(_ value: Any, path: [String], object: inout [String: Any]) {
    guard let key = path.first else {
        return
    }

    if path.count == 1 {
        object[key] = value
        return
    }

    var child = object[key] as? [String: Any] ?? [:]
    setJSONValue(value, path: Array(path.dropFirst()), object: &child)
    object[key] = child
}

func mutatedRecipe(
    from recipe: FilmRecipe,
    mutate: (inout [String: Any]) -> Void
) throws -> FilmRecipe {
    var object = try makeRecipeObject(recipe)
    mutate(&object)
    let data = try JSONSerialization.data(withJSONObject: object)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(FilmRecipe.self, from: data)
}

func writeRecipeJSON(
    from recipe: FilmRecipe,
    to url: URL,
    mutate: (inout [String: Any]) -> Void = { _ in }
) throws {
    var object = try makeRecipeObject(recipe)
    mutate(&object)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

func makeTestImage(width: Int = 16, height: Int = 12) -> CIImage {
    CIImage(color: CIColor(red: 0.28, green: 0.48, blue: 0.72, alpha: 1.0))
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
}

func writeTestPNG(to url: URL, width: Int = 16, height: Int = 12) throws {
    let image = makeTestImage(width: width, height: height)
    let context = CIContext()
    let cgImage = try require(context.createCGImage(image, from: image.extent))
    let representation = NSBitmapImageRep(cgImage: cgImage)
    let data = try require(representation.representation(using: .png, properties: [:]))
    try data.write(to: url)
}

func renderBytes(
    _ image: CIImage,
    context: CIContext,
    extent: CGRect
) -> [UInt8] {
    let width = Int(extent.width)
    let height = Int(extent.height)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)

    context.render(
        image,
        toBitmap: &bytes,
        rowBytes: width * 4,
        bounds: extent,
        format: .RGBA8,
        colorSpace: CGColorSpaceCreateDeviceRGB()
    )

    return bytes
}

func adjustments(
    intensity: Double = RenderAdjustments.defaults.intensity,
    exposureTrim: Double = RenderAdjustments.defaults.exposureTrim,
    contrastTrim: Double = RenderAdjustments.defaults.contrastTrim,
    saturationTrim: Double = RenderAdjustments.defaults.saturationTrim,
    grainEnabled: Bool = false
) -> RenderAdjustments {
    RenderAdjustments(
        intensity: intensity,
        exposureTrim: exposureTrim,
        contrastTrim: contrastTrim,
        saturationTrim: saturationTrim,
        grainEnabled: grainEnabled
    )
}

func testLoadsExpectedBundledRecipesSortedByDisplayName() throws {
    let recipes = try loadTestRecipes()

    try expect(
        Set(recipes.map(\.profileId)) == [
            "cinestill-800t",
            "fujifilm-velvia-50",
            "ilford-hp5-plus-400",
            "kodak-ektachrome-e100",
            "kodak-gold-200",
            "kodak-portra-400",
            "kodak-portra-800",
            "kodak-tri-x-400",
            "kodak-vision3-250d"
        ],
        "Bundled recipe IDs changed unexpectedly."
    )

    let displayNames = recipes.map(\.displayName)
    try expect(
        displayNames == displayNames.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        },
        "Recipes should be sorted by display name."
    )

    try expect(
        recipes.map(\.profileId).count == Set(recipes.map(\.profileId)).count,
        "Recipe profile IDs must be unique."
    )
}

func testBundledRecipesConformToRenderableSchemaExpectations() throws {
    let recipes = try loadTestRecipes()
    let expectedCurveChannels = Set(["red", "green", "blue"])

    for recipe in recipes {
        try FilmRecipeValidator.validate(recipe)
        try expect(recipe.schemaVersion == "1.0", "\(recipe.profileId) uses an unsupported schema.")
        try expect(!recipe.profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try expect(!recipe.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try expect(recipe.stock.boxSpeedIso > 0, "\(recipe.profileId) has an invalid stock ISO.")
        try expect(recipe.exposure.boxSpeedIso > 0, "\(recipe.profileId) has an invalid exposure box ISO.")
        try expect(recipe.exposure.exposedAtIso > 0, "\(recipe.profileId) has an invalid exposed-at ISO.")
        try expect(recipe.format.frameSizeMm.width > 0, "\(recipe.profileId) has an invalid frame width.")
        try expect(recipe.format.frameSizeMm.height > 0, "\(recipe.profileId) has an invalid frame height.")
        try expect(recipe.format.defaultAspectRatio > 0, "\(recipe.profileId) has an invalid aspect ratio.")

        try expect(!recipe.layerModel.rgbToLayerMatrix.isEmpty, "\(recipe.profileId) has an empty layer matrix.")
        if recipe.stock.family != .blackAndWhiteNegative {
            try expect(recipe.layerModel.rgbToLayerMatrix.count == 3, "\(recipe.profileId) has an invalid layer matrix.")
        }
        for row in recipe.layerModel.rgbToLayerMatrix {
            try expect(row.count == 3, "\(recipe.profileId) has an invalid layer matrix row.")
        }

        let curveChannels = Set(recipe.characteristicCurves.channels.keys)
        if recipe.stock.family == .blackAndWhiteNegative {
            try expect(curveChannels.contains("luminance"), "\(recipe.profileId) is missing a luminance curve channel.")
        } else {
            try expect(
                expectedCurveChannels.isSubset(of: curveChannels),
                "\(recipe.profileId) is missing one or more RGB curve channels."
            )
        }
        try expect(recipe.renderer.whitePoint > recipe.renderer.blackPoint, "\(recipe.profileId) has invalid points.")
        try expect(recipe.output.bitDepth > 0, "\(recipe.profileId) has an invalid output bit depth.")
    }
}

func testRecipeValidatorReportsActionableIssues() throws {
    let recipes = try loadTestRecipes()
    let recipe = try require(recipes.first { $0.stock.family != .blackAndWhiteNegative })
    let invalidRecipe = try mutatedRecipe(from: recipe) { object in
        object["schema_version"] = "99.0"
        object["display_name"] = "   "
        setJSONValue(0, path: ["stock", "box_speed_iso"], object: &object)
        setJSONValue([], path: ["layer_model", "rgb_to_layer_matrix"], object: &object)
        setJSONValue(0, path: ["renderer", "white_point"], object: &object)
        setJSONValue(0, path: ["renderer", "black_point"], object: &object)
        setJSONValue(99, path: ["grain", "strength"], object: &object)
    }

    let issues = FilmRecipeValidator.issues(for: invalidRecipe).map(\.message)
    try expect(issues.contains("Unsupported schema_version '99.0'."))
    try expect(issues.contains("display_name must not be empty."))
    try expect(issues.contains("stock.box_speed_iso must be greater than 0."))
    try expect(issues.contains("layer_model.rgb_to_layer_matrix must include at least one row."))
    try expect(issues.contains("Color recipes must provide a 3-row layer_model.rgb_to_layer_matrix."))
    try expect(issues.contains("renderer.white_point must be greater than renderer.black_point."))
    try expect(issues.contains("grain.strength must be between 0 and 2."))
}

func testRecipeStoreRejectsInvalidAndDuplicateRecipes() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let recipes = try loadTestRecipes()
    let recipe = try require(recipes.first)
    let validURL = directory.appendingPathComponent("valid.json")
    let duplicateURL = directory.appendingPathComponent("duplicate.json")
    let invalidURL = directory.appendingPathComponent("invalid.json")

    try writeRecipeJSON(from: recipe, to: validURL)
    try writeRecipeJSON(from: recipe, to: duplicateURL)
    try writeRecipeJSON(from: recipe, to: invalidURL) { object in
        object["schema_version"] = "99.0"
        setJSONValue(-400, path: ["exposure", "exposed_at_iso"], object: &object)
    }

    do {
        _ = try RecipeStore(recipeURLProvider: { [invalidURL] }).loadRecipe(from: invalidURL)
        try expect(false, "Expected invalid imported recipe to fail validation.")
    } catch let error as FilmRecipeValidationError {
        let description = try require(error.errorDescription)
        try expect(description.contains("Recipe validation failed for \(recipe.profileId):"))
        try expect(description.contains("Unsupported schema_version '99.0'."))
        try expect(description.contains("exposure.exposed_at_iso must be greater than 0."))
    }

    do {
        _ = try RecipeStore(recipeURLProvider: { [validURL, duplicateURL] }).loadRecipes()
        try expect(false, "Expected duplicate profile IDs to fail collection validation.")
    } catch let error as FilmRecipeValidationError {
        let description = try require(error.errorDescription)
        try expect(description.contains("Duplicate profile_id '\(recipe.profileId)' is not allowed."))
    }
}

func testStockFamilyMapsToUiStockType() throws {
    try expect(FilmStockType(family: .blackAndWhiteNegative) == .blackAndWhite)
    try expect(FilmStockType(family: .colourNegative) == .color)
    try expect(FilmStockType(family: .colourReversal) == .slide)
    try expect(FilmStockType(family: .motionPictureNegative) == .motionPicture)
    try expect(FilmStockType(family: .specialty) == .specialty)
}

func testRecipeDisplayMetadataAccessors() throws {
    let recipes = try loadTestRecipes()
    let recipe = try require(recipes.first)
    try expect(recipe.id == recipe.profileId)
    try expect(recipe.name == recipe.displayName)
    try expect(recipe.maker == recipe.manufacturer)
    try expect(recipe.iso == recipe.stock.boxSpeedIso)
    try expect(recipe.stockType == FilmStockType(family: recipe.stock.family))

    let familyLabels: [(FilmStockFamily, String)] = [
        (.blackAndWhiteNegative, "Black and white negative"),
        (.colourNegative, "Color negative"),
        (.colourReversal, "Color reversal"),
        (.motionPictureNegative, "Motion picture negative"),
        (.specialty, "Specialty stock")
    ]
    for (family, label) in familyLabels {
        try expect(family.label == label)
    }

    let stockTypeLabels: [(FilmStockType, String, String)] = [
        (.color, "Color negative", "camera.filters"),
        (.blackAndWhite, "Black and white", "circle.lefthalf.filled"),
        (.slide, "Color reversal", "rectangle.on.rectangle.angled"),
        (.motionPicture, "Motion picture", "film"),
        (.specialty, "Specialty", "sparkles")
    ]
    for (stockType, label, systemImageName) in stockTypeLabels {
        try expect(stockType.label == label)
        try expect(stockType.systemImageName == systemImageName)
    }
}

func testEveryBundledRecipeRendersSmallImageWithoutChangingExtent() throws {
    let recipes = try loadTestRecipes()
    let source = makeTestImage()
    let context = CIContext()
    let renderer = FilmPipelineRenderer()

    for recipe in recipes {
        let rendered = renderer.render(
            source: source,
            recipe: recipe,
            adjustments: adjustments()
        )

        try expect(rendered.extent == source.extent, "\(recipe.profileId) changed the render extent.")
        try expect(
            context.createCGImage(rendered, from: source.extent) != nil,
            "Expected \(recipe.profileId) to produce a renderable image."
        )
    }
}

func testRendererCoversProfileDrivenBranches() throws {
    let recipes = try loadTestRecipes()
    let source = makeTestImage()
    let context = CIContext()
    let renderer = FilmPipelineRenderer()

    let colourRecipe = try require(recipes.first { $0.stock.family != .blackAndWhiteNegative })
    let blackAndWhiteRecipe = try require(recipes.first { $0.stock.family == .blackAndWhiteNegative })

    let variants = try [
        mutatedRecipe(from: colourRecipe) { object in
            setJSONValue(false, path: ["input", "requires_scene_linear"], object: &object)
            setJSONValue("85", path: ["capture_conditions", "filter", "type"], object: &object)
            setJSONValue(1.0, path: ["capture_conditions", "filter", "strength"], object: &object)
            setJSONValue(4200, path: ["capture_conditions", "colour_temperature_k"], object: &object)
            setJSONValue(5600, path: ["stock", "native_colour_temperature_k"], object: &object)
            setJSONValue(true, path: ["grain", "enabled"], object: &object)
            setJSONValue(0.4, path: ["grain", "strength"], object: &object)
        },
        mutatedRecipe(from: colourRecipe) { object in
            setJSONValue(true, path: ["grain", "enabled"], object: &object)
            setJSONValue(0.4, path: ["grain", "strength"], object: &object)
            setJSONValue(NSNull(), path: ["grain", "tonal_distribution"], object: &object)
            setJSONValue(NSNull(), path: ["grain", "channel_variance"], object: &object)
            setJSONValue(0.0, path: ["grain", "softness"], object: &object)
            setJSONValue(0.4, path: ["process", "speed_gain_ev"], object: &object)
        },
        mutatedRecipe(from: colourRecipe) { object in
            setJSONValue("80a", path: ["capture_conditions", "filter", "type"], object: &object)
            setJSONValue(1.0, path: ["capture_conditions", "filter", "strength"], object: &object)
            setJSONValue([String: Any](), path: ["characteristic_curves", "channels"], object: &object)
            setJSONValue(false, path: ["output", "dither"], object: &object)
        },
        mutatedRecipe(from: blackAndWhiteRecipe) { object in
            setJSONValue("yellow", path: ["capture_conditions", "filter", "type"], object: &object)
            setJSONValue(1.0, path: ["capture_conditions", "filter", "strength"], object: &object)
            setJSONValue(true, path: ["colour_model", "toning", "enabled"], object: &object)
            setJSONValue(0.6, path: ["colour_model", "toning", "warmth"], object: &object)
            setJSONValue(0.3, path: ["colour_model", "toning", "selenium"], object: &object)
        },
        mutatedRecipe(from: blackAndWhiteRecipe) { object in
            setJSONValue("orange", path: ["capture_conditions", "filter", "type"], object: &object)
            setJSONValue(1.0, path: ["capture_conditions", "filter", "strength"], object: &object)
            setJSONValue([[0.30, 0.59]], path: ["layer_model", "rgb_to_layer_matrix"], object: &object)
        },
        mutatedRecipe(from: blackAndWhiteRecipe) { object in
            setJSONValue("red", path: ["capture_conditions", "filter", "type"], object: &object)
            setJSONValue(1.0, path: ["capture_conditions", "filter", "strength"], object: &object)
        },
        mutatedRecipe(from: blackAndWhiteRecipe) { object in
            setJSONValue("green", path: ["capture_conditions", "filter", "type"], object: &object)
            setJSONValue(1.0, path: ["capture_conditions", "filter", "strength"], object: &object)
            setJSONValue(false, path: ["grain", "enabled"], object: &object)
        }
    ]

    for recipe in variants {
        let rendered = renderer.render(
            source: source,
            recipe: recipe,
            adjustments: adjustments(grainEnabled: true)
        )
        try expect(rendered.extent == source.extent)
        try expect(context.createCGImage(rendered, from: source.extent) != nil)
    }
}

func testRendererClampsIntensityBeforeApplyingRecipe() throws {
    let recipes = try loadTestRecipes()
    let recipe = try require(recipes.first)
    let source = makeTestImage()
    let context = CIContext()
    let renderer = FilmPipelineRenderer()

    let negativeIntensity = renderer.render(
        source: source,
        recipe: recipe,
        adjustments: adjustments(intensity: -0.75)
    )
    let zeroIntensity = renderer.render(
        source: source,
        recipe: recipe,
        adjustments: adjustments(intensity: 0.0)
    )
    try expect(
        renderBytes(negativeIntensity, context: context, extent: source.extent)
            == renderBytes(zeroIntensity, context: context, extent: source.extent),
        "Negative intensity should clamp to zero intensity."
    )

    let fullIntensity = renderer.render(
        source: source,
        recipe: recipe,
        adjustments: adjustments(intensity: 1.0)
    )
    let excessiveIntensity = renderer.render(
        source: source,
        recipe: recipe,
        adjustments: adjustments(intensity: 1.75)
    )
    try expect(
        renderBytes(excessiveIntensity, context: context, extent: source.extent)
            == renderBytes(fullIntensity, context: context, extent: source.extent),
        "Excessive intensity should clamp to full intensity."
    )
}

func testPreviewScalingRespectsMaxDimension() throws {
    let processor = ImageProcessor()
    let preview = try processor.makePreviewImage(
        from: makeTestImage(width: 80, height: 40),
        maxDimension: 20
    )

    try expect(abs(preview.size.width - 20) <= 0.5, "Preview width should match max dimension.")
    try expect(abs(preview.size.height - 10) <= 0.5, "Preview height should preserve aspect ratio.")
}

func testImageProcessorLoadsRendersAndReportsErrors() throws {
    let processor = ImageProcessor()
    let recipes = try loadTestRecipes()
    let recipe = try require(recipes.first)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let sourceURL = directory.appendingPathComponent("source.png")
    try writeTestPNG(to: sourceURL)

    let loaded = try processor.loadSourceImage(from: sourceURL)
    try expect(loaded.extent.width == 16)
    try expect(loaded.extent.height == 12)

    let unscaled = try processor.makePreviewImage(from: loaded, maxDimension: 64)
    try expect(unscaled.size.width == 16)
    try expect(unscaled.size.height == 12)

    let zeroMaxPreview = try processor.makePreviewImage(from: loaded, maxDimension: 0)
    try expect(zeroMaxPreview.size.width == 16)
    try expect(zeroMaxPreview.size.height == 12)

    let brushAdjustment = LocalAdjustmentLayer(
        name: "Brush Test",
        mask: .brush,
        brushSize: 0.18,
        pathPoints: [
            NormalizedMaskPoint(x: 0.2, y: 0.2),
            NormalizedMaskPoint(x: 0.8, y: 0.8)
        ],
        exposureEV: 0.25
    )
    let pathAdjustment = LocalAdjustmentLayer(
        name: "Path Test",
        mask: .path,
        brushSize: 0.12,
        pathPoints: LocalAdjustmentLayer.defaultPathPoints,
        contrast: 0.2
    )
    let rendered = try processor.renderPreviewImage(
        from: loaded,
        recipe: recipe,
        adjustments: adjustments(),
        localAdjustments: [.centeredDodge, brushAdjustment, pathAdjustment],
        maxDimension: 8
    )
    try expect(abs(rendered.size.width - 8) <= 0.5)

    let histogram = try processor.makeHistogramSummary(from: loaded, bins: 8, maxDimension: 16)
    try expect(histogram.red.count == 8)
    try expect(histogram.green.count == 8)
    try expect(histogram.blue.count == 8)
    try expect(histogram.luminance.count == 8)
    try expect(histogram.redParade.count == 8)
    try expect(histogram.greenParade.count == 8)
    try expect(histogram.blueParade.count == 8)
    try expect(histogram.sampleCount == 16 * 12)
    try expect(histogram.shadowClippingRatio >= 0)
    try expect(histogram.highlightClippingRatio >= 0)

    let sample = try processor.samplePixel(from: loaded, normalisedX: 0.5, normalisedY: 0.5)
    try expect(sample.red >= 0 && sample.red <= 1)
    try expect(sample.green >= 0 && sample.green <= 1)
    try expect(sample.blue >= 0 && sample.blue <= 1)

    let uncalibrated = processor.renderedPreviewSource(
        from: loaded,
        recipe: recipe,
        adjustments: adjustments(),
        maxDimension: 16
    )
    let calibrated = processor.renderedPreviewSource(
        from: loaded,
        recipe: recipe,
        adjustments: adjustments(),
        calibration: CalibrationDataStatus(
            supportsSpectralCurves: true,
            supportsMeasuredDensityCurves: true,
            supportsGrainSpectra: true,
            supportsThreeDimensionalLUTs: true,
            redScale: 1.2,
            greenScale: 1.0,
            blueScale: 0.8,
            densityGamma: 1.08,
            grainAmount: 0.04
        ),
        maxDimension: 16
    )
    try expect(
        renderBytes(uncalibrated, context: CIContext(), extent: uncalibrated.extent)
            != renderBytes(calibrated, context: CIContext(), extent: calibrated.extent),
        "Calibration scales should change rendered pixels."
    )

    let rawAdjusted = try processor.loadSourceImage(
        from: sourceURL,
        colorSettings: ColorManagementSettings(
            rawDevelopment: RawDevelopmentSettings(
                exposureEV: 0.3,
                temperatureK: 6200,
                tint: 0.1,
                highlightRecovery: 0.2
            )
        )
    )
    try expect(rawAdjusted.extent == loaded.extent)

    do {
        _ = try processor.loadSourceImage(from: directory.appendingPathComponent("missing.png"))
        try expect(false, "Expected missing image load to fail.")
    } catch ImageProcessor.ImageProcessorError.cannotLoadImage {
    }

    do {
        _ = try processor.makePreviewImage(from: CIImage.empty())
        try expect(false, "Expected empty image preview to fail.")
    } catch ImageProcessor.ImageProcessorError.cannotRenderImage {
    }

    do {
        try processor.writeRenderedImage(
            from: CIImage.empty(),
            recipe: recipe,
            adjustments: adjustments(),
            to: directory.appendingPathComponent("empty.jpg")
        )
        try expect(false, "Expected empty image export to fail.")
    } catch ImageProcessor.ImageProcessorError.cannotRenderImage {
    }

    let failingEncoder = ImageProcessor { _, _, _ in nil }
    do {
        try failingEncoder.writeRenderedImage(
            from: loaded,
            recipe: recipe,
            adjustments: adjustments(),
            to: directory.appendingPathComponent("unencodable.jpg")
        )
        try expect(false, "Expected injected encoder failure.")
    } catch ImageProcessor.ImageProcessorError.cannotEncodeImage {
    }

    try expect(ImageProcessor.ImageProcessorError.cannotLoadImage.errorDescription != nil)
    try expect(ImageProcessor.ImageProcessorError.cannotRenderImage.errorDescription != nil)
    try expect(ImageProcessor.ImageProcessorError.cannotEncodeImage.errorDescription != nil)
    try expect(ImageProcessor.ImageProcessorError.cannotSampleImage.errorDescription != nil)
}

func testEditorStoreStateImportExportAndViewConstruction() throws {
    try MainActor.assumeIsolated {
    let editor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
    editor.loadRecipesIfNeeded()
    editor.loadRecipesIfNeeded()

    let recipe = try require(editor.recipes.first)
    try expect(editor.selectedRecipe?.id == recipe.id)
    try expect(!editor.selectedRecipeIsEditable)
    try expect(editor.recipeDraft.displayName == recipe.displayName)
    try expect(editor.recipeDraft.manufacturer == recipe.manufacturer)
    try expect(editor.recipeDraft.summary == recipe.summary)
    try expect(!editor.hasImportedImage)
    try expect(!editor.canExport)

    let bundledRecipeCount = editor.recipes.count
    editor.recipeDraft.displayName = "Bundled Edit Attempt"
    try expect(!editor.canApplyRecipeDraft)
    editor.resetRecipeDraft()
    try expect(editor.recipeDraft.displayName == recipe.displayName)

    editor.duplicateSelectedRecipeForEditing()
    let duplicatedRecipe = try require(editor.selectedRecipe)
    try expect(editor.recipes.count == bundledRecipeCount + 1)
    try expect(editor.selectedRecipeIsEditable)
    try expect(duplicatedRecipe.id.hasPrefix("\(recipe.id)-custom"))
    try expect(duplicatedRecipe.name.hasPrefix("\(recipe.name) Copy"))
    try expect(editor.recipeImportStatus?.title == "Recipe imported")

    editor.recipeDraft.displayName = "   "
    try expect(!editor.recipeDraftIssues.isEmpty)
    try expect(!editor.canApplyRecipeDraft)
    editor.recipeDraft.displayName = "Custom Gold 200"
    editor.recipeDraft.manufacturer = "Film Chef Lab"
    editor.recipeDraft.summary = "A user-adjusted metadata copy for export."
    editor.recipeDraft.stockBoxSpeedIso = 500
    editor.recipeDraft.exposedAtIso = 320
    editor.recipeDraft.exposureCompensationEv = 0.15
    editor.recipeDraft.colourSaturation = 1.2
    editor.recipeDraft.grainStrength = 0.35
    editor.recipeDraft.halationStrength = 0.2
    editor.recipeDraft.rendererContrast = 1.1
    editor.recipeDraft.outputColourSpace = "display_p3"
    editor.recipeDraft.outputBitDepth = 16
    try expect(editor.canApplyRecipeDraft)
    editor.applyRecipeDraft()
    try expect(editor.selectedRecipe?.name == "Custom Gold 200")
    try expect(editor.selectedRecipe?.maker == "Film Chef Lab")
    try expect(editor.selectedRecipe?.summary == "A user-adjusted metadata copy for export.")
    try expect(editor.selectedRecipe?.stock.boxSpeedIso == 500)
    try expect(editor.selectedRecipe?.exposure.exposedAtIso == 320)
    try expect(editor.selectedRecipe?.colourModel.saturation == 1.2)
    try expect(editor.selectedRecipe?.grain.strength == 0.35)
    try expect(editor.selectedRecipe?.halation.strength == 0.2)
    try expect(editor.selectedRecipe?.renderer.contrast == 1.1)
    try expect(editor.selectedRecipe?.output.colourSpace == "display_p3")
    try expect(editor.selectedRecipe?.output.bitDepth == 16)
    try expect(editor.recipeDraft.displayName == "Custom Gold 200")

    editor.beginImport()
    try expect(editor.isImporting)

    struct ImportError: LocalizedError {
        var errorDescription: String? { "Import failed." }
    }
    editor.handleImportResult(.failure(ImportError()))
    try expect(editor.errorMessage == "Import failed.")
    editor.errorMessage = nil
    editor.handleImportResults(.success([]))
    try expect(editor.errorMessage == nil)
    editor.handleImportResults(.failure(ImportError()))
    try expect(editor.errorMessage == "Import failed.")
    editor.errorMessage = nil

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let sourceURL = directory.appendingPathComponent(" Sample Photo .png")
    try writeTestPNG(to: sourceURL, width: 10, height: 8)

    editor.handleImportResult(.success(sourceURL))
    let importedViaTestingURL = directory.appendingPathComponent("Testing Import.png")
    try writeTestPNG(to: importedViaTestingURL, width: 9, height: 7)
    editor.importPhotoForTesting(from: importedViaTestingURL)
    editor.handleImportResults(.success([sourceURL]))
    try expect(editor.hasImportedImage)
    try expect(editor.canExport)
    try expect(editor.importedImageName == " Sample Photo .png")
    try expect(editor.originalPreviewImage != nil)
    try expect(editor.editedPreviewImage != nil)
    try expect(editor.histogramSummary != nil)
    try expect(editor.project.items.count == 2)
    try expect(editor.canBatchExport)
    try expect(editor.editHistory.count >= 1)
    try expect(editor.displayedPreviewImage === editor.editedPreviewImage)

    let otherItem = try require(editor.project.items.first { $0.displayName == "Testing Import.png" })
    editor.selectProjectItem(id: otherItem.id)
    try expect(editor.importedImageName == "Testing Import.png")
    let sourceItem = try require(editor.project.items.first { $0.displayName == " Sample Photo .png" })
    editor.selectProjectItem(id: sourceItem.id)
    try expect(editor.importedImageName == " Sample Photo .png")

    editor.showOriginal = true
    try expect(editor.displayedPreviewImage === editor.originalPreviewImage)
    editor.comparisonMode = .split
    try expect(editor.comparisonMode == .split)
    editor.previewZoom = 2.0
    editor.panPreview(deltaX: 24, deltaY: -12)
    try expect(editor.previewPanX == 24)
    try expect(editor.previewPanY == -12)
    editor.setPreviewPan(x: 1_000, y: -1_000)
    try expect(editor.previewPanX == 220)
    try expect(editor.previewPanY == -220)
    editor.loupeEnabled = true
    editor.loupeZoom = 3.0
    editor.loupePlacement = .topRight
    try expect(editor.loupePlacement == .topRight)
    try expect(editor.canResetPreviewView)
    editor.resetPreviewView()
    try expect(editor.previewZoom == 1.0)
    try expect(editor.previewPanX == 0)
    try expect(editor.previewPanY == 0)
    try expect(!editor.loupeEnabled)

    editor.intensity = 0.25
    try expect(editor.previewRenderProgress == 1.0)
    try expect(editor.previewRenderStatus == "Preview ready")
    let cacheHitsBeforeRepeat = editor.previewCacheHitCount
    editor.intensity = 0.25
    try expect(editor.previewCacheHitCount > cacheHitsBeforeRepeat)
    for step in 1...9 {
        editor.intensity = Double(step) / 10.0
    }
    try expect(editor.previewRenderCacheSize <= 8)
    editor.intensity = 0.25
    editor.exposureTrim = 0.2
    editor.contrastTrim = -0.1
    editor.saturationTrim = 0.15
    editor.grainEnabled = false
    editor.addLocalAdjustment()
    try expect(editor.localAdjustments.count == 1)
    try expect(editor.selectedLocalAdjustmentID == editor.localAdjustments[0].id)
    try expect(editor.canEditLocalMaskOnPreview)
    editor.beginLocalMaskEditAtPreviewPoint(x: 0.35, y: 0.65)
    editor.updateLocalMaskEditAtPreviewPoint(x: 0.45, y: 0.55)
    editor.endLocalMaskEditAtPreviewPoint()
    try expect(editor.localAdjustments[0].centerX == 0.45)
    try expect(editor.localAdjustments[0].centerY == 0.55)
    editor.localAdjustments[0].mask = .brush
    editor.beginLocalMaskEditAtPreviewPoint(x: 0.2, y: 0.2)
    editor.updateLocalMaskEditAtPreviewPoint(x: 0.24, y: 0.25)
    editor.endLocalMaskEditAtPreviewPoint()
    try expect(editor.localAdjustments[0].pathPoints.count == 2)
    editor.localAdjustments[0].mask = .path
    editor.localAdjustments[0].pathPoints = [
        NormalizedMaskPoint(x: 0.1, y: 0.1),
        NormalizedMaskPoint(x: 0.9, y: 0.1),
        NormalizedMaskPoint(x: 0.5, y: 0.9)
    ]
    editor.beginLocalMaskEditAtPreviewPoint(x: 0.88, y: 0.12)
    editor.updateLocalMaskEditAtPreviewPoint(x: 0.7, y: 0.3)
    editor.endLocalMaskEditAtPreviewPoint()
    try expect(editor.localAdjustments[0].pathPoints[1] == NormalizedMaskPoint(x: 0.7, y: 0.3))
    editor.localAdjustments[0].mask = .radial
    editor.localAdjustments[0].centerX = 0.45
    editor.localAdjustments[0].exposureEV = 0.35
    try expect(editor.currentAdjustments.intensity == 0.25)
    try expect(editor.canUndoEdit)
    editor.undoEdit()
    try expect(editor.canRedoEdit)
    editor.redoEdit()
    editor.captureVariant(note: "Warm review")
    let capturedVariant = try require(editor.editHistory.last)
    editor.renameVariant(id: capturedVariant.id, note: "Warm review v1")
    try expect(editor.editHistory.last?.note == "Warm review v1")
    editor.duplicateVariant(id: capturedVariant.id)
    try expect(editor.editHistory.last?.note == "Warm review v1 Copy")
    try expect(editor.editHistoryIndex == editor.editHistory.count - 1)
    let duplicateVariant = try require(editor.editHistory.last)
    editor.restoreVariant(id: capturedVariant.id)
    try expect(editor.editHistory[editor.editHistoryIndex ?? -1].id == capturedVariant.id)
    editor.deleteVariant(id: duplicateVariant.id)
    try expect(!editor.editHistory.contains { $0.id == duplicateVariant.id })
    try expect(editor.project.items.first { $0.id == editor.project.selectedItemID }?.localAdjustments.count == 1)
    editor.resetControls()
    try expect(editor.currentAdjustments == RenderAdjustments.defaults)
    try expect(!editor.showOriginal)
    editor.samplePreviewPixel(x: 0.25, y: 0.75)
    try expect(editor.pixelSample != nil)
    try expect(editor.pixelSample?.x == 0.25)
    try expect(editor.pixelSample?.y == 0.75)
    editor.samplePreviewPixel(x: -1, y: 2)
    try expect(editor.samplerX == 0)
    try expect(editor.samplerY == 1)
    try expect(editor.pixelSample?.x == 0)
    try expect(editor.pixelSample?.y == 1)
    editor.removeLocalAdjustments()
    try expect(editor.localAdjustments.isEmpty)
    try expect(editor.selectedLocalAdjustmentID == nil)

    let lutURL = directory.appendingPathComponent("test-lut.cube")
    try """
    LUT_3D_SIZE 2
    0.20 0.10 0.10
    0.30 0.15 0.10
    0.40 0.20 0.15
    0.50 0.25 0.20
    0.60 0.30 0.22
    0.70 0.35 0.26
    0.80 0.40 0.30
    0.90 0.45 0.34
    """.data(using: .utf8)?.write(to: lutURL)
    let spectralURL = directory.appendingPathComponent("spectral-density.json")
    try #"{"red":0.7,"green":0.5,"blue":0.3,"density":0.8}"#.data(using: .utf8)?.write(to: spectralURL)
    let grainURL = directory.appendingPathComponent("grain-spectrum.csv")
    try "frequency,amount\n1,0.4\n2,0.7\n".data(using: .utf8)?.write(to: grainURL)
    editor.importCalibrationAssetsForTesting(from: [lutURL, spectralURL, grainURL])
    try expect(editor.calibrationDataStatus.supportsThreeDimensionalLUTs)
    try expect(editor.calibrationDataStatus.supportsSpectralCurves)
    try expect(editor.calibrationDataStatus.supportsMeasuredDensityCurves)
    try expect(editor.calibrationDataStatus.supportsGrainSpectra)
    try expect(editor.calibrationDataStatus.redScale > editor.calibrationDataStatus.blueScale)
    try expect(editor.calibrationDataStatus.densityGamma > 1.0)
    try expect(editor.calibrationDataStatus.grainAmount > 0)

    let invalidLUTURL = directory.appendingPathComponent("invalid-lut.cube")
    try """
    LUT_3D_SIZE 2
    0.1 0.1 0.1
    """.data(using: .utf8)?.write(to: invalidLUTURL)
    editor.errorMessage = nil
    editor.importCalibrationAssetsForTesting(from: [invalidLUTURL])
    try expect(editor.errorMessage?.contains("Expected 8 LUT rows") == true)

    let suggestedName = editor.suggestedExportFileNameForTesting()
    try expect(suggestedName.hasPrefix("Sample Photo-"))
    try expect(suggestedName.hasSuffix(".jpg"))

    try expect(editor.exportPresets.count >= 3)
    try expect(editor.exportNamingTemplateIssues.isEmpty)
    try expect(editor.exportFileNamePreview.hasSuffix(".jpg"))
    editor.exportSettings.namingTemplate = "{photo}-{bad}"
    try expect(editor.exportNamingTemplateIssues.contains("Unsupported naming token {bad}. Use {photo}, {recipe}, or {format}."))
    try expect(!editor.canSaveExportPreset)
    editor.exportSettings.namingTemplate = "{photo-{recipe}"
    try expect(editor.exportNamingTemplateIssues.contains("Unsupported naming token {photo-{recipe}. Use {photo}, {recipe}, or {format}."))
    editor.exportSettings.namingTemplate = "{photo}-{recipe}"
    editor.exportPresetDraftName = "Small Review"
    editor.exportSettings = ExportSettings(fileFormat: .png, jpegQuality: 1.0, scale: 0.5, preserveMetadata: false, embedColorProfile: true, namingTemplate: "{photo}-small")
    editor.saveExportPreset()
    let smallReviewPreset = try require(editor.exportPresets.first { $0.name == "Small Review" })
    try expect(editor.selectedExportPresetID == smallReviewPreset.id)
    editor.exportSettings = .defaults
    editor.applySelectedExportPreset()
    try expect(editor.exportSettings.fileFormat == .png)
    try expect(editor.exportSettings.scale == 0.5)

    let exportURL = directory.appendingPathComponent("export.jpeg")
    editor.exportEditedPhotoForTesting(to: exportURL)
    try expect(FileManager.default.fileExists(atPath: exportURL.path))

    let batchDirectory = directory.appendingPathComponent("batch", isDirectory: true)
    editor.exportSettings.fileFormat = .jpeg
    editor.exportSettings.namingTemplate = "{photo}_{recipe}_{format}"
    editor.exportProjectPhotosForTesting(to: batchDirectory)
    let batchFiles = try FileManager.default.contentsOfDirectory(atPath: batchDirectory.path)
    try expect(batchFiles.count == 2, "Expected both project photos to export.")
    try expect(batchFiles.allSatisfy { $0.contains("_jpeg") })
    try expect(!editor.batchExportState.isExporting)
    try expect(editor.batchExportState.completedCount == 2)
    try expect(editor.batchExportState.exportedFileNames.count == 2)

    let recipeExportURL = directory.appendingPathComponent("recipe.json")
    editor.exportSelectedRecipeForTesting(to: recipeExportURL)
    try expect(FileManager.default.fileExists(atPath: recipeExportURL.path))
    editor.importRecipeForTesting(from: recipeExportURL)
    try expect(editor.selectedRecipe != nil)
    try expect(editor.selectedRecipeIsEditable)
    try expect(editor.recipeImportStatus?.title == "Recipe imported")

    let invalidRecipeURL = directory.appendingPathComponent("invalid-recipe.json")
    try writeRecipeJSON(from: recipe, to: invalidRecipeURL) { object in
        setJSONValue(0, path: ["output", "bit_depth"], object: &object)
    }
    let selectedRecipeID = editor.selectedRecipeID
    editor.errorMessage = nil
    editor.importRecipeForTesting(from: invalidRecipeURL)
    try expect(editor.selectedRecipeID == selectedRecipeID)
    try expect(editor.errorMessage?.contains("output.bit_depth must be greater than 0.") == true)
    if case .failed(let name, let issues) = editor.recipeImportStatus {
        try expect(name == "invalid-recipe.json")
        try expect(issues.map(\.message).contains("output.bit_depth must be greater than 0."))
    } else {
        try expect(false, "Expected invalid recipe import to record structured validation issues.")
    }
    editor.clearRecipeImportStatus()
    try expect(editor.recipeImportStatus == nil)

    let fallbackEditor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
    try expect(fallbackEditor.suggestedExportFileNameForTesting() == "film-chef-photo-edited.jpg")
    fallbackEditor.triggerExportPanelForTesting()

    let failingRecipeEditor = EditorStore(recipeStore: RecipeStore(recipeURLProvider: { [] }))
    failingRecipeEditor.loadRecipesIfNeeded()
    try expect(failingRecipeEditor.errorMessage == RecipeStore.RecipeStoreError.missingResource.errorDescription)

    let failingImportEditor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
    failingImportEditor.loadRecipesIfNeeded()
    failingImportEditor.importPhotoForTesting(from: directory.appendingPathComponent("missing.png"))
    try expect(failingImportEditor.errorMessage == ImageProcessor.ImageProcessorError.cannotLoadImage.errorDescription)

    let failingExportEditor = EditorStore(
        recipeStore: RecipeStore(),
        imageProcessor: ImageProcessor { _, _, _ in nil }
    )
    failingExportEditor.loadRecipesIfNeeded()
    failingExportEditor.importPhotoForTesting(from: sourceURL)
    failingExportEditor.exportEditedPhotoForTesting(to: directory.appendingPathComponent("bad-export.jpg"))
    try expect(failingExportEditor.errorMessage == ImageProcessor.ImageProcessorError.cannotEncodeImage.errorDescription)

    ContentViewCoverageProbe.touch(editor: editor)
    SidebarViewCoverageProbe.touch(editor: editor, recipe: recipe)
    PreviewPaneViewCoverageProbe.touch(editor: editor)
    ControlsViewCoverageProbe.touch(editor: editor)
    HistogramViewCoverageProbe.touch(summary: editor.histogramSummary)
    }
}

func testErrorDescriptionsAreStable() throws {
    try expect(RecipeStore.RecipeStoreError.missingResource.errorDescription == "No film recipe JSON files could be found.")
    try expect(
        FilmRecipeValidationError.invalidRecipe(
            profileID: "sample",
            issues: [RecipeValidationIssue("schema_version must not be empty.")]
        ).errorDescription == "Recipe validation failed for sample:\n- schema_version must not be empty."
    )
    try expect(ProjectStore.ProjectStoreError.missingPhotoReference.errorDescription != nil)
    try expect(ProjectStore.ProjectStoreError.unsupportedSchema(99).errorDescription != nil)
}

func testProjectStoreAndEditorPersistRestorableProject() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let sourceURL = directory.appendingPathComponent("Project Photo.png")
    try writeTestPNG(to: sourceURL, width: 11, height: 9)
    let projectURL = directory.appendingPathComponent("Project.filmchef")

    try MainActor.assumeIsolated {
        let editor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
        editor.loadRecipesIfNeeded()
        editor.importPhotoForTesting(from: sourceURL)
        editor.intensity = 0.4
        editor.exposureTrim = 0.15
        editor.addLocalAdjustment()
        editor.localAdjustments[0].mask = .path
        editor.localAdjustments[0].brushSize = 0.2
        editor.localAdjustments[0].pathPoints = [
            NormalizedMaskPoint(x: 0.25, y: 0.3),
            NormalizedMaskPoint(x: 0.75, y: 0.3),
            NormalizedMaskPoint(x: 0.55, y: 0.7)
        ]
        editor.localAdjustments[0].saturation = 0.2
        editor.previewZoom = 1.5
        editor.splitPosition = 0.35
        editor.histogramChannelMode = .rgb
        editor.exportSettings = ExportSettings(fileFormat: .tiff, jpegQuality: 0.8, scale: 1.25, namingTemplate: "{photo}_custom")
        editor.exportPresetDraftName = "Project TIFF"
        editor.saveExportPreset()
        let lutURL = directory.appendingPathComponent("project-lut.cube")
        try """
        LUT_3D_SIZE 2
        0.15 0.10 0.10
        0.25 0.13 0.10
        0.35 0.18 0.12
        0.45 0.23 0.16
        0.55 0.28 0.19
        0.65 0.34 0.22
        0.75 0.40 0.25
        0.85 0.45 0.28
        """.data(using: .utf8)?.write(to: lutURL)
        editor.importCalibrationAssetsForTesting(from: [lutURL])
        editor.saveProjectForTesting(to: projectURL)
        try expect(FileManager.default.fileExists(atPath: projectURL.path))

        let loadedProject = try ProjectStore().loadProject(from: projectURL)
        try expect(loadedProject.schemaVersion == 1)
        try expect(loadedProject.items.count == 1)
        try expect(loadedProject.items.first?.originalURLPath == sourceURL.path)
        try expect(loadedProject.items.first?.localAdjustments.count == 1)
        try expect(loadedProject.editHistory.count == editor.editHistory.count)
        try expect(loadedProject.exportSettings.fileFormat == .tiff)
        try expect(loadedProject.exportSettings.namingTemplate == "{photo}_custom")
        try expect(loadedProject.exportPresets.contains { $0.name == "Project TIFF" })
        try expect(loadedProject.calibrationDataStatus.supportsThreeDimensionalLUTs)
        try expect(loadedProject.calibrationDataStatus.redScale > loadedProject.calibrationDataStatus.blueScale)

        let reopened = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
        reopened.loadRecipesIfNeeded()
        reopened.openProjectForTesting(from: projectURL)
        try expect(reopened.hasImportedImage)
        try expect(reopened.importedImageName == "Project Photo.png")
        try expect(reopened.currentAdjustments.intensity == 0.4)
        try expect(reopened.currentAdjustments.exposureTrim == 0.15)
        try expect(reopened.localAdjustments.count == 1)
        try expect(reopened.localAdjustments[0].mask == .path)
        try expect(reopened.localAdjustments[0].brushSize == 0.2)
        try expect(reopened.localAdjustments[0].pathPoints.count == 3)
        try expect(reopened.exportSettings.fileFormat == .tiff)
        try expect(reopened.exportSettings.namingTemplate == "{photo}_custom")
        try expect(reopened.exportPresets.contains { $0.name == "Project TIFF" })
        try expect(reopened.calibrationDataStatus.importedAssetNames == ["project-lut.cube"])
        try expect(reopened.calibrationDataStatus.redScale > reopened.calibrationDataStatus.blueScale)
        try expect(reopened.histogramSummary != nil)
        let cacheHitsBeforeColorChange = reopened.previewCacheHitCount
        reopened.colorManagementSettings.rawDevelopment.exposureEV = 0.25
        try expect(reopened.project.colorManagementSettings.rawDevelopment.exposureEV == 0.25)
        try expect(reopened.previewRenderStatus == "Preview ready")
        try expect(reopened.previewCacheHitCount == cacheHitsBeforeColorChange)

        let secondURL = directory.appendingPathComponent("Second Photo.png")
        try writeTestPNG(to: secondURL, width: 8, height: 6)
        reopened.handleImportResults(.success([sourceURL, secondURL]))
        try expect(reopened.project.items.count == 2)
        let secondItem = try require(reopened.project.items.first { $0.displayName == "Second Photo.png" })
        reopened.selectProjectItem(id: secondItem.id)
        try expect(reopened.importedImageName == "Second Photo.png")

        let batchDirectory = directory.appendingPathComponent("project-batch", isDirectory: true)
        reopened.exportProjectPhotosForTesting(to: batchDirectory)
        let batchFiles = try FileManager.default.contentsOfDirectory(atPath: batchDirectory.path)
        try expect(batchFiles.count == 2)
    }

    let missingReference = FilmProjectItem(
        displayName: "Missing",
        originalURLPath: nil,
        selectedRecipeID: nil,
        adjustments: RenderAdjustments.defaults
    )
    do {
        _ = try ProjectStore().resolvePhotoURL(for: missingReference)
        try expect(false, "Expected missing project photo reference to fail.")
    } catch ProjectStore.ProjectStoreError.missingPhotoReference {
    }
}

func testWriteRenderedImageEncodesPngAndJpeg() throws {
    let processor = ImageProcessor()
    let recipes = try loadTestRecipes()
    let recipe = try require(recipes.first)
    let source = makeTestImage(width: 12, height: 10)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let pngURL = directory.appendingPathComponent("render.png")
    try processor.writeRenderedImage(
        from: source,
        recipe: recipe,
        adjustments: adjustments(),
        to: pngURL
    )
    let pngData = try Data(contentsOf: pngURL)
    try expect(
        Array(pngData.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        "PNG export did not have a PNG signature."
    )

    let jpegURL = directory.appendingPathComponent("render.jpg")
    try processor.writeRenderedImage(
        from: source,
        recipe: recipe,
        adjustments: adjustments(),
        to: jpegURL
    )
    let jpegData = try Data(contentsOf: jpegURL)
    try expect(
        Array(jpegData.prefix(2)) == [0xFF, 0xD8],
        "JPEG export did not have a JPEG signature."
    )
    let jpegSource = try require(CGImageSourceCreateWithURL(jpegURL as CFURL, nil))
    let jpegProperties = try require(CGImageSourceCopyPropertiesAtIndex(jpegSource, 0, nil) as? [String: Any])
    let exifMetadata = try require(jpegProperties[kCGImagePropertyExifDictionary as String] as? [String: Any])
    try expect(exifMetadata[kCGImagePropertyExifUserComment as String] as? String == "Rendered with Film Chef")

    let p3URL = directory.appendingPathComponent("render-p3.jpg")
    try processor.writeRenderedImage(
        from: source,
        recipe: recipe,
        adjustments: adjustments(),
        to: p3URL,
        colorSettings: ColorManagementSettings(outputColorSpace: "display_p3")
    )
    let p3Source = try require(CGImageSourceCreateWithURL(p3URL as CFURL, nil))
    let p3Properties = try require(CGImageSourceCopyPropertiesAtIndex(p3Source, 0, nil) as? [String: Any])
    try expect(p3Properties[kCGImagePropertyProfileName as String] as? String == "Display P3")

    let minimalURL = directory.appendingPathComponent("render-minimal.jpg")
    try processor.writeRenderedImage(
        from: source,
        recipe: recipe,
        adjustments: adjustments(),
        to: minimalURL,
        settings: ExportSettings(fileFormat: .jpeg, preserveMetadata: false, embedColorProfile: false)
    )
    let minimalSource = try require(CGImageSourceCreateWithURL(minimalURL as CFURL, nil))
    let minimalProperties = try require(CGImageSourceCopyPropertiesAtIndex(minimalSource, 0, nil) as? [String: Any])
    let minimalExif = minimalProperties[kCGImagePropertyExifDictionary as String] as? [String: Any]
    try expect(minimalExif?[kCGImagePropertyExifUserComment as String] as? String != "Rendered with Film Chef")

    let tiffURL = directory.appendingPathComponent("render.tiff")
    try processor.writeRenderedImage(
        from: source,
        recipe: recipe,
        adjustments: adjustments(),
        to: tiffURL,
        settings: ExportSettings(fileFormat: .tiff),
        localAdjustments: [.centeredDodge]
    )
    let tiffData = try Data(contentsOf: tiffURL)
    try expect(
        Array(tiffData.prefix(2)) == [0x49, 0x49] || Array(tiffData.prefix(2)) == [0x4D, 0x4D],
        "TIFF export did not have a TIFF byte-order signature."
    )
}

let tests: [TestCase] = [
    TestCase(name: "loads expected bundled recipes sorted by display name", run: testLoadsExpectedBundledRecipesSortedByDisplayName),
    TestCase(name: "bundled recipes conform to renderable schema expectations", run: testBundledRecipesConformToRenderableSchemaExpectations),
    TestCase(name: "recipe validator reports actionable issues", run: testRecipeValidatorReportsActionableIssues),
    TestCase(name: "recipe store rejects invalid and duplicate recipes", run: testRecipeStoreRejectsInvalidAndDuplicateRecipes),
    TestCase(name: "stock family maps to UI stock type", run: testStockFamilyMapsToUiStockType),
    TestCase(name: "recipe display metadata accessors", run: testRecipeDisplayMetadataAccessors),
    TestCase(name: "every bundled recipe renders a small image without changing extent", run: testEveryBundledRecipeRendersSmallImageWithoutChangingExtent),
    TestCase(name: "renderer covers profile driven branches", run: testRendererCoversProfileDrivenBranches),
    TestCase(name: "renderer clamps intensity before applying recipe", run: testRendererClampsIntensityBeforeApplyingRecipe),
    TestCase(name: "preview scaling respects max dimension", run: testPreviewScalingRespectsMaxDimension),
    TestCase(name: "image processor loads renders and reports errors", run: testImageProcessorLoadsRendersAndReportsErrors),
    TestCase(name: "write rendered image encodes PNG and JPEG", run: testWriteRenderedImageEncodesPngAndJpeg),
    TestCase(name: "editor store state import export and view construction", run: testEditorStoreStateImportExportAndViewConstruction),
    TestCase(name: "project store and editor persist restorable project", run: testProjectStoreAndEditorPersistRestorableProject),
    TestCase(name: "error descriptions are stable", run: testErrorDescriptionsAreStable)
]

var failures: [(String, Error)] = []

for test in tests {
    do {
        try test.run()
        print("[PASS] \(test.name)")
    } catch {
        failures.append((test.name, error))
        print("[FAIL] \(test.name)")
        print("       \(error)")
    }
}

if failures.isEmpty {
    print("FilmChefCoreTests: \(tests.count)/\(tests.count) passed")
} else {
    print("FilmChefCoreTests: \(tests.count - failures.count)/\(tests.count) passed")
    exit(EXIT_FAILURE)
}
