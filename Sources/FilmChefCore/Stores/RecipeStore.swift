import Foundation

public final class RecipeStore {
    private static let maxRecipeByteCount = 2 * 1024 * 1024

    package enum RecipeStoreError: LocalizedError {
        case missingResource
        case oversizedRecipe(String)

        package var errorDescription: String? {
            switch self {
            case .missingResource:
                return "No film recipe JSON files could be found."
            case .oversizedRecipe(let name):
                return "\(name) is too large to import as a film recipe."
            }
        }
    }

    private let recipeURLProvider: () -> [URL]

    public init() {
        recipeURLProvider = Self.bundledRecipeURLs
    }

    package init(recipeURLProvider: @escaping () -> [URL]) {
        self.recipeURLProvider = recipeURLProvider
    }

    package func loadRecipes() throws -> [FilmRecipe] {
        let urls = recipeURLProvider()

        guard !urls.isEmpty else {
            throw RecipeStoreError.missingResource
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let recipes = try urls.map { url in
            let data = try recipeData(from: url)
            return try decoder.decode(FilmRecipe.self, from: data)
        }

        try FilmRecipeValidator.validateCollection(recipes)

        return recipes.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    package func loadRecipe(from url: URL) throws -> FilmRecipe {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try recipeData(from: url)
        let recipe = try decoder.decode(FilmRecipe.self, from: data)
        try FilmRecipeValidator.validate(recipe)
        return recipe
    }

    package func writeRecipe(_ recipe: FilmRecipe, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(recipe)
        try data.write(to: url, options: [.atomic])
    }

    private func recipeData(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize > Self.maxRecipeByteCount {
            throw RecipeStoreError.oversizedRecipe(url.lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        if data.count > Self.maxRecipeByteCount {
            throw RecipeStoreError.oversizedRecipe(url.lastPathComponent)
        }
        return data
    }

    private static func bundledRecipeURLs() -> [URL] {
        let recipeDirectoryPaths = Bundle.module
            .paths(forResourcesOfType: "json", inDirectory: "Recipes")
        let rootJSONPaths = Bundle.module
            .paths(forResourcesOfType: "json", inDirectory: nil)

        let recipeURLs = Array(Set(recipeDirectoryPaths + rootJSONPaths))
            .map(URL.init(fileURLWithPath:))

        return recipeURLs
            .filter { $0.deletingPathExtension().lastPathComponent != "film_recipes" }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }
}
