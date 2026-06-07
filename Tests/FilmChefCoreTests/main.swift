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

func makeTestImage(width: Int = 16, height: Int = 12) -> CIImage {
    CIImage(color: CIColor(red: 0.28, green: 0.48, blue: 0.72, alpha: 1.0))
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
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
            "ilford-hp5-plus-400",
            "kodak-ektachrome-e100",
            "kodak-gold-200"
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
    TestCase(name: "every bundled recipe renders a small image without changing extent", run: testEveryBundledRecipeRendersSmallImageWithoutChangingExtent),
    TestCase(name: "renderer clamps intensity before applying recipe", run: testRendererClampsIntensityBeforeApplyingRecipe),
    TestCase(name: "preview scaling respects max dimension", run: testPreviewScalingRespectsMaxDimension),
    TestCase(name: "write rendered image encodes PNG and JPEG", run: testWriteRenderedImageEncodesPngAndJpeg)
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
