import Foundation

final class RecipeStore {
    enum RecipeStoreError: LocalizedError {
        case missingResource
        case emptyRecipes

        var errorDescription: String? {
            switch self {
            case .missingResource:
                return "The film recipe JSON file could not be found."
            case .emptyRecipes:
                return "The film recipe JSON file does not contain any recipes."
            }
        }
    }

    func loadRecipes() throws -> [FilmRecipe] {
        let url = Bundle.module.url(
            forResource: "film_recipes",
            withExtension: "json",
            subdirectory: "Recipes"
        ) ?? Bundle.module.url(
            forResource: "film_recipes",
            withExtension: "json"
        )

        guard let url else {
            throw RecipeStoreError.missingResource
        }

        let data = try Data(contentsOf: url)
        let recipes = try JSONDecoder().decode([FilmRecipe].self, from: data)

        guard !recipes.isEmpty else {
            throw RecipeStoreError.emptyRecipes
        }

        return recipes
    }
}
