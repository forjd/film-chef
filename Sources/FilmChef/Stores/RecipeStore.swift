import Foundation

final class RecipeStore {
    enum RecipeStoreError: LocalizedError {
        case missingResource
        case emptyRecipes

        var errorDescription: String? {
            switch self {
            case .missingResource:
                return "No film recipe JSON files could be found."
            case .emptyRecipes:
                return "The film recipe directory does not contain any recipes."
            }
        }
    }

    func loadRecipes() throws -> [FilmRecipe] {
        let urls = recipeURLs()

        guard !urls.isEmpty else {
            throw RecipeStoreError.missingResource
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let recipes = try urls.map { url in
            let data = try Data(contentsOf: url)
            return try decoder.decode(FilmRecipe.self, from: data)
        }

        guard !recipes.isEmpty else {
            throw RecipeStoreError.emptyRecipes
        }

        return recipes.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func recipeURLs() -> [URL] {
        let recipeDirectoryURLs = Bundle.module.urls(
            forResourcesWithExtension: "json",
            subdirectory: "Recipes"
        ) ?? []

        let candidateURLs = recipeDirectoryURLs.isEmpty
            ? Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
            : recipeDirectoryURLs

        return candidateURLs
            .filter { $0.deletingPathExtension().lastPathComponent != "film_recipes" }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }
}
