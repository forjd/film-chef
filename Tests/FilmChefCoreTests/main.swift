import AppKit
import CoreGraphics
import CoreImage
import Foundation
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

    let rendered = try processor.renderPreviewImage(
        from: loaded,
        recipe: recipe,
        adjustments: adjustments(),
        maxDimension: 8
    )
    try expect(abs(rendered.size.width - 8) <= 0.5)

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
}

func testEditorStoreStateImportExportAndViewConstruction() throws {
    try MainActor.assumeIsolated {
    let editor = EditorStore(recipeStore: RecipeStore())
    editor.loadRecipesIfNeeded()
    editor.loadRecipesIfNeeded()

    let recipe = try require(editor.recipes.first)
    try expect(editor.selectedRecipe?.id == recipe.id)
    try expect(!editor.hasImportedImage)
    try expect(!editor.canExport)

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
    try expect(editor.displayedPreviewImage === editor.editedPreviewImage)

    editor.showOriginal = true
    try expect(editor.displayedPreviewImage === editor.originalPreviewImage)

    editor.intensity = 0.25
    editor.exposureTrim = 0.2
    editor.contrastTrim = -0.1
    editor.saturationTrim = 0.15
    editor.grainEnabled = false
    try expect(editor.currentAdjustments.intensity == 0.25)
    editor.resetControls()
    try expect(editor.currentAdjustments == RenderAdjustments.defaults)
    try expect(!editor.showOriginal)

    let suggestedName = editor.suggestedExportFileNameForTesting()
    try expect(suggestedName.hasPrefix("Sample Photo-"))
    try expect(suggestedName.hasSuffix(".jpg"))

    let exportURL = directory.appendingPathComponent("export.jpeg")
    editor.exportEditedPhotoForTesting(to: exportURL)
    try expect(FileManager.default.fileExists(atPath: exportURL.path))

    let fallbackEditor = EditorStore(recipeStore: RecipeStore())
    try expect(fallbackEditor.suggestedExportFileNameForTesting() == "film-chef-photo-edited.jpg")
    fallbackEditor.triggerExportPanelForTesting()

    let failingRecipeEditor = EditorStore(recipeStore: RecipeStore(recipeURLProvider: { [] }))
    failingRecipeEditor.loadRecipesIfNeeded()
    try expect(failingRecipeEditor.errorMessage == RecipeStore.RecipeStoreError.missingResource.errorDescription)

    let failingImportEditor = EditorStore(recipeStore: RecipeStore())
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
    }
}

func testErrorDescriptionsAreStable() throws {
    try expect(RecipeStore.RecipeStoreError.missingResource.errorDescription == "No film recipe JSON files could be found.")
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
}

let tests: [TestCase] = [
    TestCase(name: "loads expected bundled recipes sorted by display name", run: testLoadsExpectedBundledRecipesSortedByDisplayName),
    TestCase(name: "bundled recipes conform to renderable schema expectations", run: testBundledRecipesConformToRenderableSchemaExpectations),
    TestCase(name: "stock family maps to UI stock type", run: testStockFamilyMapsToUiStockType),
    TestCase(name: "recipe display metadata accessors", run: testRecipeDisplayMetadataAccessors),
    TestCase(name: "every bundled recipe renders a small image without changing extent", run: testEveryBundledRecipeRendersSmallImageWithoutChangingExtent),
    TestCase(name: "renderer covers profile driven branches", run: testRendererCoversProfileDrivenBranches),
    TestCase(name: "renderer clamps intensity before applying recipe", run: testRendererClampsIntensityBeforeApplyingRecipe),
    TestCase(name: "preview scaling respects max dimension", run: testPreviewScalingRespectsMaxDimension),
    TestCase(name: "image processor loads renders and reports errors", run: testImageProcessorLoadsRendersAndReportsErrors),
    TestCase(name: "write rendered image encodes PNG and JPEG", run: testWriteRenderedImageEncodesPngAndJpeg),
    TestCase(name: "editor store state import export and view construction", run: testEditorStoreStateImportExportAndViewConstruction),
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
