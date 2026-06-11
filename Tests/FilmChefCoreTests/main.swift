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

func writeTestJPEG(
    to url: URL,
    width: Int = 16,
    height: Int = 12,
    orientation: Int? = nil
) throws {
    let image = makeTestImage(width: width, height: height)
    let context = CIContext()
    let cgImage = try require(context.createCGImage(image, from: image.extent))
    let data = NSMutableData()
    let destination = try require(CGImageDestinationCreateWithData(
        data,
        "public.jpeg" as CFString,
        1,
        nil
    ))

    var properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.95
    ]
    if let orientation {
        properties[kCGImagePropertyOrientation] = orientation
    }

    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    try expect(CGImageDestinationFinalize(destination), "Expected JPEG fixture to encode.")
    try (data as Data).write(to: url)
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

    try expect(ColorOutputProfile(rawProfileName: "Display P3") == .displayP3)
    try expect(ColorOutputProfile(rawProfileName: "extended-linear-srgb") == .extendedSRGB)
    try expect(ColorOutputProfile(rawProfileName: "linear_srgb") == .linearSRGB)
    try expect(ColorOutputProfile(rawProfileName: "unknown") == .sRGB)
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

func testRendererAppliesCalibrationInsidePipeline() throws {
    let recipes = try loadTestRecipes()
    let recipe = try require(recipes.first { $0.stock.family != .blackAndWhiteNegative })
    let source = makeTestImage()
    let context = CIContext()
    let renderer = FilmPipelineRenderer()

    let uncalibrated = renderer.render(
        source: source,
        recipe: recipe,
        adjustments: adjustments()
    )
    let calibrated = renderer.render(
        source: source,
        recipe: recipe,
        adjustments: adjustments(),
        calibration: CalibrationDataStatus(
            supportsSpectralCurves: true,
            supportsMeasuredDensityCurves: true,
            supportsGrainSpectra: true,
            supportsThreeDimensionalLUTs: true,
            redScale: 1.18,
            greenScale: 1.0,
            blueScale: 0.82,
            densityGamma: 1.12,
            grainAmount: 0.05
        )
    )

    try expect(calibrated.extent == source.extent)
    try expect(
        renderBytes(uncalibrated, context: context, extent: uncalibrated.extent)
            != renderBytes(calibrated, context: context, extent: calibrated.extent),
        "Renderer calibration should change pixels inside the film pipeline."
    )
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

func testHalationGlowsHighlightsWithoutShiftingShadows() throws {
    let recipes = try loadTestRecipes()
    let colourRecipe = try require(recipes.first { $0.stock.family != .blackAndWhiteNegative })
    let halationRecipe = try mutatedRecipe(from: colourRecipe) { object in
        setJSONValue(true, path: ["halation", "enabled"], object: &object)
        setJSONValue(0.8, path: ["halation", "strength"], object: &object)
        setJSONValue(3.0, path: ["halation", "radius"], object: &object)
        setJSONValue(0.6, path: ["halation", "threshold"], object: &object)
        setJSONValue(0.0, path: ["halation", "edge_preservation"], object: &object)
        setJSONValue(1.0, path: ["halation", "colour", "r"], object: &object)
        setJSONValue(0.35, path: ["halation", "colour", "g"], object: &object)
        setJSONValue(0.2, path: ["halation", "colour", "b"], object: &object)
    }
    let noHalationRecipe = try mutatedRecipe(from: halationRecipe) { object in
        setJSONValue(false, path: ["halation", "enabled"], object: &object)
    }

    let width = 48
    let height = 32
    let background = CIImage(color: CIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0))
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    let highlight = CIImage(color: CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        .cropped(to: CGRect(x: 20, y: 12, width: 8, height: 8))
    let source = highlight.composited(over: background)

    let context = CIContext()
    let renderer = FilmPipelineRenderer()
    let withHalation = renderBytes(
        renderer.render(source: source, recipe: halationRecipe, adjustments: adjustments()),
        context: context,
        extent: source.extent
    )
    let withoutHalation = renderBytes(
        renderer.render(source: source, recipe: noHalationRecipe, adjustments: adjustments()),
        context: context,
        extent: source.extent
    )

    let centerRow = height / 2
    let nearIndex = ((centerRow * width) + 29) * 4
    let farIndex = ((centerRow * width) + 4) * 4

    try expect(
        Int(withHalation[nearIndex]) > Int(withoutHalation[nearIndex]) + 4,
        "Halation should add red glow just outside a bright highlight."
    )
    for channelOffset in 0..<3 {
        let difference = abs(Int(withHalation[farIndex + channelOffset]) - Int(withoutHalation[farIndex + channelOffset]))
        try expect(
            difference <= 3,
            "Halation should not shift shadow pixels far from highlights (channel \(channelOffset) moved by \(difference))."
        )
    }
}

func testRendererScalesSpatialParametersForPreview() throws {
    let recipes = try loadTestRecipes()
    let base = try require(recipes.first { $0.stock.family != .blackAndWhiteNegative })
    let context = CIContext()
    let renderer = FilmPipelineRenderer()

    let background = CIImage(color: CIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0))
        .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 32))
    let highlight = CIImage(color: CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        .cropped(to: CGRect(x: 20, y: 12, width: 8, height: 8))
    let source = highlight.composited(over: background)

    let spatialRecipe = try mutatedRecipe(from: base) { object in
        setJSONValue(true, path: ["grain", "enabled"], object: &object)
        setJSONValue(0.5, path: ["grain", "strength"], object: &object)
        setJSONValue(true, path: ["halation", "enabled"], object: &object)
        setJSONValue(0.6, path: ["halation", "strength"], object: &object)
        setJSONValue(4.0, path: ["halation", "radius"], object: &object)
        setJSONValue(0.6, path: ["halation", "threshold"], object: &object)
        setJSONValue(1.5, path: ["sharpness", "film_mtf_blur"], object: &object)
    }
    let fullScale = renderer.render(
        source: source,
        recipe: spatialRecipe,
        adjustments: adjustments(grainEnabled: true),
        spatialScale: 1.0
    )
    let halfScale = renderer.render(
        source: source,
        recipe: spatialRecipe,
        adjustments: adjustments(grainEnabled: true),
        spatialScale: 0.5
    )
    try expect(
        renderBytes(fullScale, context: context, extent: source.extent)
            != renderBytes(halfScale, context: context, extent: source.extent),
        "Spatial scale should shrink grain, halation, and blur footprints."
    )

    let pointwiseRecipe = try mutatedRecipe(from: base) { object in
        setJSONValue(false, path: ["grain", "enabled"], object: &object)
        setJSONValue(false, path: ["halation", "enabled"], object: &object)
        setJSONValue(0.0, path: ["sharpness", "film_mtf_blur"], object: &object)
        setJSONValue(0.0, path: ["sharpness", "scanner_mtf_blur"], object: &object)
        setJSONValue(0.0, path: ["sharpness", "acutance"], object: &object)
        setJSONValue(0.0, path: ["sharpness", "digital_sharpening"], object: &object)
        setJSONValue(0.0, path: ["renderer", "sharpening"], object: &object)
        setJSONValue(NSNull(), path: ["renderer", "scanner_mtf"], object: &object)
    }
    let pointwiseFull = renderer.render(
        source: source,
        recipe: pointwiseRecipe,
        adjustments: adjustments(),
        spatialScale: 1.0
    )
    let pointwiseHalf = renderer.render(
        source: source,
        recipe: pointwiseRecipe,
        adjustments: adjustments(),
        spatialScale: 0.5
    )
    try expect(
        renderBytes(pointwiseFull, context: context, extent: source.extent)
            == renderBytes(pointwiseHalf, context: context, extent: source.extent),
        "Spatial scale must not change pointwise color stages."
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

func testHistogramClipWarningTextUsesConfiguredThreshold() throws {
    let summary = HistogramSummary(
        red: [0.0, 1.0],
        green: [0.0, 1.0],
        blue: [0.0, 1.0],
        luminance: [0.0, 1.0],
        sampleCount: 100,
        shadowClippingRatio: 0.08,
        highlightClippingRatio: 0.03
    )

    try expect(
        EditorStore.histogramClipWarningText(for: summary, threshold: 0.02) ==
            "Shadow 8% and highlight 3% clipping exceed threshold."
    )
    try expect(
        EditorStore.histogramClipWarningText(for: summary, threshold: 0.05) ==
            "Shadow 8% clipping exceeds threshold."
    )
    try expect(EditorStore.histogramClipWarningText(for: summary, threshold: 0.1) == nil)

    let highlightSummary = HistogramSummary(
        red: [0.0, 1.0],
        green: [0.0, 1.0],
        blue: [0.0, 1.0],
        luminance: [0.0, 1.0],
        sampleCount: 100,
        shadowClippingRatio: 0.0,
        highlightClippingRatio: 0.12
    )
    try expect(
        EditorStore.histogramClipWarningText(for: highlightSummary, threshold: 0.05) ==
            "Highlight 12% clipping exceeds threshold."
    )
}

func testImageProcessorSamplesActualPixelColor() throws {
    let processor = ImageProcessor()
    let sample = try processor.samplePixel(
        from: makeTestImage(width: 12, height: 10),
        normalisedX: 0.5,
        normalisedY: 0.5
    )

    try expect(sample.red > 0.2 && sample.red < 0.35)
    try expect(sample.green > 0.4 && sample.green < 0.55)
    try expect(sample.blue > 0.65 && sample.blue < 0.8)

    let clamped = try processor.samplePixel(
        from: makeTestImage(width: 12, height: 10),
        normalisedX: -1,
        normalisedY: 2
    )
    try expect(clamped.x == 0)
    try expect(clamped.y == 1)
    try expect(clamped.luminance > 0)
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

    let colorManaged = try processor.loadSourceImage(
        from: sourceURL,
        colorSettings: ColorManagementSettings(
            inputIntent: "device_rgb",
            workingColorSpace: "display_p3",
            outputColorSpace: "display_p3",
            rawDevelopmentEnabled: false
        )
    )
    try expect(colorManaged.extent == loaded.extent)

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

func testCameraProfileIngestionHonorsOrientationAndRawSettings() throws {
    let processor = ImageProcessor()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let orientedURL = directory.appendingPathComponent("camera-oriented.jpg")
    try writeTestJPEG(to: orientedURL, width: 8, height: 12, orientation: 6)

    let loaded = try processor.loadSourceImage(
        from: orientedURL,
        colorSettings: ColorManagementSettings(rawDevelopmentEnabled: false)
    )
    try expect(loaded.extent.width == 12)
    try expect(loaded.extent.height == 8)

    let colorManaged = try processor.loadSourceImage(
        from: orientedURL,
        colorSettings: ColorManagementSettings(
            inputIntent: "srgb",
            workingColorSpace: "linear_srgb",
            outputColorSpace: "srgb",
            rawDevelopmentEnabled: false
        )
    )
    try expect(colorManaged.extent == loaded.extent)

    let rawSettings = ColorManagementSettings(
        rawDevelopment: RawDevelopmentSettings(
            exposureEV: 1.0,
            temperatureK: 5400,
            tint: 0,
            highlightRecovery: 0
        )
    )

    let nonRawAdjusted = try processor.loadSourceImage(
        from: orientedURL,
        colorSettings: rawSettings
    )
    try expect(nonRawAdjusted.extent == loaded.extent)
    try expect(
        renderBytes(loaded, context: CIContext(), extent: loaded.extent)
            == renderBytes(nonRawAdjusted, context: CIContext(), extent: nonRawAdjusted.extent),
        "RAW development should not alter non-RAW sources."
    )

    let rawDeveloped = try processor.loadSourceImage(
        from: orientedURL,
        colorSettings: rawSettings,
        treatAsRaw: true
    )
    try expect(rawDeveloped.extent == loaded.extent)
    try expect(
        renderBytes(loaded, context: CIContext(), extent: loaded.extent)
            != renderBytes(rawDeveloped, context: CIContext(), extent: rawDeveloped.extent),
        "RAW exposure development should affect ingested RAW pixels."
    )
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
    editor.recipeDraft.captureColourTemperatureK = 6200
    editor.recipeDraft.captureFilterType = "85"
    editor.recipeDraft.captureFilterStrength = 0.4
    editor.recipeDraft.colourSaturation = 1.2
    editor.recipeDraft.processPushPullStops = 0.5
    editor.recipeDraft.processContrastMultiplier = 1.15
    editor.recipeDraft.processGrainMultiplier = 1.25
    editor.recipeDraft.grainEnabled = false
    editor.recipeDraft.grainStrength = 0.35
    editor.recipeDraft.halationEnabled = true
    editor.recipeDraft.halationStrength = 0.2
    editor.recipeDraft.sharpnessAcutance = 0.6
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
    try expect(editor.selectedRecipe?.captureConditions.colourTemperatureK == 6200)
    try expect(editor.selectedRecipe?.captureConditions.filter.type == "85")
    try expect(editor.selectedRecipe?.captureConditions.filter.strength == 0.4)
    try expect(editor.selectedRecipe?.colourModel.saturation == 1.2)
    try expect(editor.selectedRecipe?.process.pushPullStops == 0.5)
    try expect(editor.selectedRecipe?.process.contrastMultiplier == 1.15)
    try expect(editor.selectedRecipe?.process.grainMultiplier == 1.25)
    try expect(editor.selectedRecipe?.grain.enabled == false)
    try expect(editor.selectedRecipe?.grain.strength == 0.35)
    try expect(editor.selectedRecipe?.halation.enabled == true)
    try expect(editor.selectedRecipe?.halation.strength == 0.2)
    try expect(editor.selectedRecipe?.sharpness.acutance == 0.6)
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
    let sampledRGB = (editor.pixelSample?.red ?? 0) + (editor.pixelSample?.green ?? 0) + (editor.pixelSample?.blue ?? 0)
    try expect(sampledRGB > 0, "Preview sampler should read non-black color from the test image.")
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
    try expect(editor.calibrationDataStatus.importedAssetSummaries.contains("test-lut.cube: 3D LUT"))
    try expect(editor.calibrationDataStatus.importedAssetSummaries.contains("spectral-density.json: density curves, spectral curves"))
    try expect(editor.calibrationDataStatus.importedAssetSummaries.contains("grain-spectrum.csv: grain spectra, spectral curves"))

    let invalidLUTURL = directory.appendingPathComponent("invalid-lut.cube")
    try """
    LUT_3D_SIZE 2
    0.1 0.1 0.1
    """.data(using: .utf8)?.write(to: invalidLUTURL)
    editor.errorMessage = nil
    editor.importCalibrationAssetsForTesting(from: [invalidLUTURL])
    try expect(editor.errorMessage?.contains("Expected 8 LUT rows") == true)

    let oversizedLUTURL = directory.appendingPathComponent("oversized-lut.cube")
    try """
    LUT_3D_SIZE 3000000
    0.1 0.1 0.1
    """.data(using: .utf8)?.write(to: oversizedLUTURL)
    editor.errorMessage = nil
    editor.importCalibrationAssetsForTesting(from: [oversizedLUTURL])
    try expect(editor.errorMessage?.contains("LUT_3D_SIZE must be an integer between 2 and 256") == true)

    let domainLUTURL = directory.appendingPathComponent("domain-lut.cube")
    try """
    TITLE "Domain LUT"
    DOMAIN_MIN 0.0 0.0 0.0
    DOMAIN_MAX 1.0 1.0 1.0
    LUT_3D_SIZE 2
    0.20 0.10 0.10
    0.30 0.15 0.10
    0.40 0.20 0.15
    0.50 0.25 0.20
    0.60 0.30 0.22
    0.70 0.35 0.26
    0.80 0.40 0.30
    0.90 0.45 0.34
    """.data(using: .utf8)?.write(to: domainLUTURL)
    editor.errorMessage = nil
    editor.importCalibrationAssetsForTesting(from: [domainLUTURL])
    try expect(editor.errorMessage == nil, "Cube files with TITLE and DOMAIN header lines should import.")
    try expect(editor.calibrationDataStatus.supportsThreeDimensionalLUTs)

    let typedCalibrationURL = directory.appendingPathComponent("measured-curves.json")
    try """
    {
      "asset_types": ["spectral_curves", "density_curves", "grain_spectra"],
      "values": [0.15, 0.35, 0.55, 0.75],
      "rgb_scale": { "red": 1.08, "green": 1.0, "blue": 0.92 }
    }
    """.data(using: .utf8)?.write(to: typedCalibrationURL)
    let typedCalibrationEditor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
    typedCalibrationEditor.importCalibrationAssetsForTesting(from: [typedCalibrationURL])
    try expect(typedCalibrationEditor.calibrationDataStatus.supportsSpectralCurves)
    try expect(typedCalibrationEditor.calibrationDataStatus.supportsMeasuredDensityCurves)
    try expect(typedCalibrationEditor.calibrationDataStatus.supportsGrainSpectra)
    try expect(typedCalibrationEditor.calibrationDataStatus.supportsThreeDimensionalLUTs)
    try expect(typedCalibrationEditor.calibrationDataStatus.redScale > typedCalibrationEditor.calibrationDataStatus.blueScale)
    try expect(typedCalibrationEditor.calibrationDataStatus.importedAssetSummaries == ["measured-curves.json: density curves, grain spectra, RGB scale, spectral curves"])

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
    editor.duplicateSelectedExportPreset()
    let copiedPreset = try require(editor.exportPresets.first { $0.name == "Small Review Copy" })
    try expect(editor.selectedExportPresetID == copiedPreset.id)
    try expect(editor.exportPresetDraftName == "Small Review Copy")
    try expect(copiedPreset.settings == smallReviewPreset.settings)
    editor.beginNewExportPreset()
    try expect(editor.selectedExportPresetID == nil)
    editor.exportPresetDraftName = "Small Review"
    try expect(editor.exportPresetNameIssues == ["A preset named Small Review already exists."])
    try expect(!editor.canSaveExportPreset)
    editor.exportPresetDraftName = "Small Review Mobile"
    try expect(editor.canSaveExportPreset)
    editor.saveExportPreset()
    let mobilePreset = try require(editor.exportPresets.first { $0.name == "Small Review Mobile" })
    editor.exportPresetDraftName = "Small Review Mobile Updated"
    editor.saveExportPreset()
    try expect(editor.exportPresets.first { $0.id == mobilePreset.id }?.name == "Small Review Mobile Updated")
    editor.deleteSelectedExportPreset()
    try expect(!editor.exportPresets.contains { $0.id == mobilePreset.id })
    editor.restoreDefaultExportPresets()
    try expect(editor.exportPresets == ExportPreset.defaults)
    try expect(editor.selectedExportPresetID == nil)

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
    }
}

func testEditorSplitSamplerUsesVisibleImageSide() throws {
    try MainActor.assumeIsolated {
    let editor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
    editor.loadRecipesIfNeeded()

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let baseRecipe = try require(editor.recipes.first)
    let darkRecipeURL = directory.appendingPathComponent("split-sampler-black.json")
    try writeRecipeJSON(from: baseRecipe, to: darkRecipeURL) { object in
        setJSONValue("split-sampler-black", path: ["profile_id"], object: &object)
        setJSONValue("Split Sampler Black", path: ["display_name"], object: &object)
        setJSONValue(0.95, path: ["renderer", "black_point"], object: &object)
        setJSONValue(1.0, path: ["renderer", "white_point"], object: &object)
    }
    editor.importRecipeForTesting(from: darkRecipeURL)

    let imageURL = directory.appendingPathComponent("sample.png")
    try writeTestPNG(to: imageURL)
    editor.importPhotoForTesting(from: imageURL)
    editor.comparisonMode = .split
    editor.splitPosition = 0.5

    editor.samplePreviewPixel(x: 0.25, y: 0.5)
    let originalSideSample = try require(editor.pixelSample)
    try expect(originalSideSample.red > 0.2)
    try expect(originalSideSample.green > 0.4)
    try expect(originalSideSample.blue > 0.6)

    editor.samplePreviewPixel(x: 0.75, y: 0.5)
    let processedSideSample = try require(editor.pixelSample)
    try expect(
        processedSideSample.red + processedSideSample.green + processedSideSample.blue < 0.05,
        "Split sampler should read the processed side when the marker is right of the divider."
    )
    }
}

func testEditorRecipeDraftEditingFlow() throws {
    try MainActor.assumeIsolated {
        let editor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
        editor.loadRecipesIfNeeded()
        let recipe = try require(editor.selectedRecipe)

        editor.duplicateSelectedRecipeForEditing()
        editor.recipeDraft.displayName = "Focused Recipe"
        editor.recipeDraft.manufacturer = "Film Chef Tests"
        editor.recipeDraft.summary = "Focused recipe editing coverage."
        editor.recipeDraft.captureFilterType = "80a"
        editor.recipeDraft.captureFilterStrength = 0.3
        editor.recipeDraft.processPushPullStops = -0.5
        editor.recipeDraft.grainEnabled = !recipe.grain.enabled
        editor.recipeDraft.halationEnabled = !recipe.halation.enabled
        editor.recipeDraft.layerRGBToLayerMatrix[0][0] = 0.77
        let firstCurveChannel = try require(editor.recipeDraft.characteristicCurveGammas.keys.sorted().first)
        editor.recipeDraft.characteristicCurveToes[firstCurveChannel] = 0.22
        editor.recipeDraft.characteristicCurveGammas[firstCurveChannel] = 1.42
        editor.recipeDraft.characteristicCurveShoulders[firstCurveChannel] = 0.33
        try expect(editor.canApplyRecipeDraft)

        editor.applyRecipeDraft()
        try expect(editor.selectedRecipe?.name == "Focused Recipe")
        try expect(editor.selectedRecipe?.captureConditions.filter.type == "80a")
        try expect(editor.selectedRecipe?.process.pushPullStops == -0.5)
        try expect(editor.selectedRecipe?.grain.enabled == !recipe.grain.enabled)
        try expect(editor.selectedRecipe?.halation.enabled == !recipe.halation.enabled)
        try expect(editor.selectedRecipe?.layerModel.rgbToLayerMatrix[0][0] == 0.77)
        try expect(editor.selectedRecipe?.characteristicCurves.channels[firstCurveChannel]?.toe == 0.22)
        try expect(editor.selectedRecipe?.characteristicCurves.channels[firstCurveChannel]?.gamma == 1.42)
        try expect(editor.selectedRecipe?.characteristicCurves.channels[firstCurveChannel]?.shoulder == 0.33)

        editor.recipeDraft.layerRGBToLayerMatrix[0][0] = 5.0
        try expect(!editor.recipeDraftIssues.isEmpty)
        try expect(!editor.canApplyRecipeDraft)
    }
}

func testEditorPreviewLocalMaskAndVariantControls() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("Preview Controls.png")
    try writeTestPNG(to: sourceURL, width: 10, height: 8)

    try MainActor.assumeIsolated {
        let editor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
        editor.loadRecipesIfNeeded()
        editor.importPhotoForTesting(from: sourceURL)

        editor.previewZoom = 2.0
        editor.setPreviewPan(x: 1_000, y: -1_000)
        try expect(editor.previewPanX == 220)
        try expect(editor.previewPanY == -220)
        editor.loupeEnabled = true
        editor.loupePlacement = .bottomLeft
        try expect(editor.canResetPreviewView)

        editor.addLocalAdjustment()
        editor.beginLocalMaskEditAtPreviewPoint(x: 0.25, y: 0.75)
        editor.updateLocalMaskEditAtPreviewPoint(x: 0.45, y: 0.55)
        editor.endLocalMaskEditAtPreviewPoint()
        try expect(editor.localAdjustments.first?.centerX == 0.45)
        try expect(editor.localAdjustments.first?.centerY == 0.55)

        editor.captureVariant(note: "Focused variant")
        let variant = try require(editor.editHistory.last)
        let variantLayerID = try require(editor.localAdjustments.first?.id)
        editor.localAdjustments.removeAll()
        try expect(editor.localAdjustments.isEmpty)
        editor.restoreVariant(id: variant.id)
        try expect(editor.localAdjustments.first?.id == variantLayerID)
        try expect(editor.localAdjustments.first?.centerX == 0.45)
        editor.renameVariant(id: variant.id, note: "Focused variant renamed")
        try expect(editor.editHistory.first { $0.id == variant.id }?.note == "Focused variant renamed")
        editor.duplicateVariant(id: variant.id)
        try expect(editor.editHistory.count >= 3)
        try expect(editor.editHistory[editor.editHistoryIndex ?? -1].localAdjustments.first?.id == variantLayerID)
    }
}

func testEditorCalibrationImportFlow() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let typedCalibrationURL = directory.appendingPathComponent("typed.json")
    try """
    {
      "asset_types": ["spectral_curves", "density_curves", "grain_spectra"],
      "values": [0.1, 0.2, 0.3],
      "rgb_scale": { "red": 1.1, "green": 1.0, "blue": 0.9 }
    }
    """.data(using: .utf8)?.write(to: typedCalibrationURL)

    try MainActor.assumeIsolated {
        let editor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
        editor.importCalibrationAssetsForTesting(from: [typedCalibrationURL])
        try expect(editor.calibrationDataStatus.supportsSpectralCurves)
        try expect(editor.calibrationDataStatus.supportsMeasuredDensityCurves)
        try expect(editor.calibrationDataStatus.supportsGrainSpectra)
        try expect(editor.calibrationDataStatus.supportsThreeDimensionalLUTs)
    }
}

func testEditorExportSettingsAndBatchFlow() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("Export Flow.png")
    try writeTestPNG(to: sourceURL, width: 10, height: 8)
    let missingAfterImportURL = directory.appendingPathComponent("Missing Later.png")
    try writeTestPNG(to: missingAfterImportURL, width: 10, height: 8)

    try MainActor.assumeIsolated {
        let editor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
        editor.loadRecipesIfNeeded()
        editor.importPhotoForTesting(from: sourceURL)
        editor.importPhotoForTesting(from: missingAfterImportURL)
        try? FileManager.default.removeItem(at: missingAfterImportURL)

        editor.exportSettings.namingTemplate = "{photo}-{bad}"
        try expect(!editor.canExportCurrentSettings)
        try expect(!editor.canBatchExport)
        editor.exportSettings.namingTemplate = "{photo}_{recipe}_{format}"
        try expect(editor.canExportCurrentSettings)
        try expect(editor.canBatchExport)

        let batchDirectory = directory.appendingPathComponent("batch", isDirectory: true)
        editor.exportProjectPhotosForTesting(to: batchDirectory)
        let batchFiles = try FileManager.default.contentsOfDirectory(atPath: batchDirectory.path)
        try expect(batchFiles.count == 1)
        try expect(editor.batchExportState.completedCount == 2)
        try expect(editor.batchExportState.exportedFileNames.count == 1)
        try expect(editor.batchExportState.failures.count == 1)
        try expect(editor.batchExportState.failures.first?.itemName == "Missing Later.png")
        try expect(editor.batchExportState.statusText == "Exported 1 of 2; 1 failed.")
        try expect(editor.batchExportState.diagnostics.outputDirectoryPath == batchDirectory.path)
        try expect(editor.batchExportState.diagnostics.retryableFailureCount == 1)
        try expect(editor.errorMessage == "1 batch export item failed.")
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

func testProjectStoreLoadsSparseSchemaOneProjectsWithDefaults() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let projectID = UUID()
    let projectURL = directory.appendingPathComponent("Legacy.filmchef")
    try """
    {
      "schemaVersion": 1,
      "id": "\(projectID.uuidString)",
      "name": "Legacy Project"
    }
    """.data(using: .utf8)?.write(to: projectURL)

    let project = try ProjectStore().loadProject(from: projectURL)
    try expect(project.schemaVersion == 1)
    try expect(project.id == projectID)
    try expect(project.name == "Legacy Project")
    try expect(project.items.isEmpty)
    try expect(project.editHistory.isEmpty)
    try expect(project.exportSettings == .defaults)
    try expect(project.exportPresets == ExportPreset.defaults)
    try expect(project.colorManagementSettings == .defaults)
    try expect(project.calibrationDataStatus == .descriptiveOnly)
    try expect(project.updatedAt == project.createdAt)
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
        try expect(loadedProject.calibrationDataStatus.importedAssetSummaries == ["project-lut.cube: 3D LUT"])

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
        try expect(reopened.calibrationDataStatus.importedAssetSummaries == ["project-lut.cube: 3D LUT"])
        try expect(reopened.calibrationDataStatus.redScale > reopened.calibrationDataStatus.blueScale)
        try expect(reopened.histogramSummary != nil)
        let cacheHitsBeforeColorChange = reopened.previewCacheHitCount
        reopened.colorManagementSettings.rawDevelopment.exposureEV = 0.25
        try expect(reopened.project.colorManagementSettings.rawDevelopment.exposureEV == 0.25)
        try expect(reopened.previewRenderStatus == "Preview ready")
        try expect(reopened.previewCacheHitCount == cacheHitsBeforeColorChange)
        reopened.colorManagementSettings.outputColorSpace = ColorOutputProfile.displayP3.rawValue
        try expect(reopened.selectedOutputProfile == .displayP3)
        try expect(reopened.project.colorManagementSettings.outputColorSpace == "display_p3")

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

        let missingItemID = UUID()
        let missingProject = FilmProject(
            items: [
                FilmProjectItem(
                    id: missingItemID,
                    displayName: "Missing Photo.png",
                    originalURLPath: directory.appendingPathComponent("missing-photo.png").path,
                    selectedRecipeID: reopened.selectedRecipeID,
                    adjustments: RenderAdjustments.defaults
                )
            ],
            selectedItemID: missingItemID
        )
        let missingProjectURL = directory.appendingPathComponent("Missing Project.filmchef")
        try ProjectStore().writeProject(missingProject, to: missingProjectURL)

        let relinkEditor = EditorStore(recipeStore: RecipeStore(), imageProcessor: ImageProcessor())
        relinkEditor.loadRecipesIfNeeded()
        relinkEditor.openProjectForTesting(from: missingProjectURL)
        try expect(relinkEditor.projectItemNeedingRelinkID == missingItemID)
        relinkEditor.relinkProjectItemForTesting(id: missingItemID, to: sourceURL)
        try expect(relinkEditor.projectItemNeedingRelinkID == nil)
        try expect(relinkEditor.hasImportedImage)
        try expect(relinkEditor.project.items.first?.originalURLPath == sourceURL.path)
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

    let taggedAverage = try decodedAverageByteValue(at: jpegURL)
    let untaggedAverage = try decodedAverageByteValue(at: minimalURL)
    try expect(
        abs(taggedAverage - untaggedAverage) < 8,
        "Exports without an embedded profile must still be color matched (tagged avg \(taggedAverage), untagged avg \(untaggedAverage))."
    )

    let metadataSourceURL = directory.appendingPathComponent("metadata-source.jpg")
    try writeTestJPEG(to: metadataSourceURL)
    let metadataData = try Data(contentsOf: metadataSourceURL)
    let metadataSource = try require(CGImageSourceCreateWithData(metadataData as CFData, nil))
    let stampedImage = try require(CGImageSourceCreateImageAtIndex(metadataSource, 0, nil))
    let stampedData = NSMutableData()
    let stampedDestination = try require(CGImageDestinationCreateWithData(stampedData, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(stampedDestination, stampedImage, [
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCam"]
    ] as CFDictionary)
    try expect(CGImageDestinationFinalize(stampedDestination))
    try (stampedData as Data).write(to: metadataSourceURL)

    let preservedURL = directory.appendingPathComponent("render-preserved.jpg")
    try processor.writeRenderedImage(
        from: source,
        recipe: recipe,
        adjustments: adjustments(),
        to: preservedURL,
        settings: ExportSettings(fileFormat: .jpeg, preserveMetadata: true),
        sourceMetadataURL: metadataSourceURL
    )
    let preservedSource = try require(CGImageSourceCreateWithURL(preservedURL as CFURL, nil))
    let preservedProperties = try require(CGImageSourceCopyPropertiesAtIndex(preservedSource, 0, nil) as? [String: Any])
    let preservedTIFF = try require(preservedProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
    try expect(preservedTIFF[kCGImagePropertyTIFFMake as String] as? String == "TestCam", "Source camera metadata should survive export.")
    try expect(preservedTIFF[kCGImagePropertyTIFFSoftware as String] as? String == "Film Chef")

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
    if recipe.output.bitDepth >= 16 {
        let tiffSource = try require(CGImageSourceCreateWithURL(tiffURL as CFURL, nil))
        let tiffProperties = try require(CGImageSourceCopyPropertiesAtIndex(tiffSource, 0, nil) as? [String: Any])
        try expect(
            tiffProperties[kCGImagePropertyDepth as String] as? Int == 16,
            "TIFF export should honor the recipe's 16-bit output depth."
        )
    }
}

func decodedAverageByteValue(at url: URL) throws -> Double {
    let source = try require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let cgImage = try require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let width = cgImage.width
    let height = cgImage.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = try require(CGColorSpace(name: CGColorSpace.sRGB))

    try bytes.withUnsafeMutableBytes { buffer in
        let bitmapContext = try require(CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    var total = 0.0
    var sampleCount = 0
    for offset in stride(from: 0, to: bytes.count, by: 4) {
        total += Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])
        sampleCount += 3
    }
    return total / Double(max(sampleCount, 1))
}

let tests: [TestCase] = [
    TestCase(name: "loads expected bundled recipes sorted by display name", run: testLoadsExpectedBundledRecipesSortedByDisplayName),
    TestCase(name: "bundled recipes conform to renderable schema expectations", run: testBundledRecipesConformToRenderableSchemaExpectations),
    TestCase(name: "recipe validator reports actionable issues", run: testRecipeValidatorReportsActionableIssues),
    TestCase(name: "recipe store rejects invalid and duplicate recipes", run: testRecipeStoreRejectsInvalidAndDuplicateRecipes),
    TestCase(name: "stock family maps to UI stock type", run: testStockFamilyMapsToUiStockType),
    TestCase(name: "recipe display metadata accessors", run: testRecipeDisplayMetadataAccessors),
    TestCase(name: "every bundled recipe renders a small image without changing extent", run: testEveryBundledRecipeRendersSmallImageWithoutChangingExtent),
    TestCase(name: "renderer applies calibration inside pipeline", run: testRendererAppliesCalibrationInsidePipeline),
    TestCase(name: "renderer covers profile driven branches", run: testRendererCoversProfileDrivenBranches),
    TestCase(name: "renderer clamps intensity before applying recipe", run: testRendererClampsIntensityBeforeApplyingRecipe),
    TestCase(name: "halation glows highlights without shifting shadows", run: testHalationGlowsHighlightsWithoutShiftingShadows),
    TestCase(name: "renderer scales spatial parameters for preview", run: testRendererScalesSpatialParametersForPreview),
    TestCase(name: "preview scaling respects max dimension", run: testPreviewScalingRespectsMaxDimension),
    TestCase(name: "histogram clip warning text uses configured threshold", run: testHistogramClipWarningTextUsesConfiguredThreshold),
    TestCase(name: "image processor samples actual pixel color", run: testImageProcessorSamplesActualPixelColor),
    TestCase(name: "image processor loads renders and reports errors", run: testImageProcessorLoadsRendersAndReportsErrors),
    TestCase(name: "camera profile ingestion honors orientation and RAW settings", run: testCameraProfileIngestionHonorsOrientationAndRawSettings),
    TestCase(name: "write rendered image encodes PNG and JPEG", run: testWriteRenderedImageEncodesPngAndJpeg),
    TestCase(name: "editor store end to end smoke flow", run: testEditorStoreStateImportExportAndViewConstruction),
    TestCase(name: "editor split sampler uses visible image side", run: testEditorSplitSamplerUsesVisibleImageSide),
    TestCase(name: "editor recipe draft editing flow", run: testEditorRecipeDraftEditingFlow),
    TestCase(name: "editor preview local mask and variant controls", run: testEditorPreviewLocalMaskAndVariantControls),
    TestCase(name: "editor calibration import flow", run: testEditorCalibrationImportFlow),
    TestCase(name: "editor export settings and batch flow", run: testEditorExportSettingsAndBatchFlow),
    TestCase(name: "project store loads sparse schema one projects with defaults", run: testProjectStoreLoadsSparseSchemaOneProjectsWithDefaults),
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
