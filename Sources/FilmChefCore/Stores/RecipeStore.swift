import Foundation

public final class RecipeStore {
    package enum RecipeStoreError: LocalizedError {
        case missingResource

        package var errorDescription: String? {
            switch self {
            case .missingResource:
                return "No film recipe JSON files could be found."
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
            let data = try Data(contentsOf: url)
            return try decoder.decode(FilmRecipe.self, from: data)
        }

        return recipes.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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
