import Foundation

package struct RecipeValidationIssue: Hashable, CustomStringConvertible {
    package let message: String

    package init(_ message: String) {
        self.message = message
    }

    package var description: String {
        message
    }
}

package enum FilmRecipeValidationError: LocalizedError, Equatable {
    case invalidRecipe(profileID: String, issues: [RecipeValidationIssue])

    package var errorDescription: String? {
        switch self {
        case .invalidRecipe(let profileID, let issues):
            let issueList = issues
                .map { "- \($0.message)" }
                .joined(separator: "\n")
            return "Recipe validation failed for \(profileID):\n\(issueList)"
        }
    }
}

package enum FilmRecipeValidator {
    package static let supportedSchemaVersions: Set<String> = ["1.0"]

    package static func validate(_ recipe: FilmRecipe) throws {
        let issues = issues(for: recipe)
        guard issues.isEmpty else {
            throw FilmRecipeValidationError.invalidRecipe(
                profileID: validationName(for: recipe),
                issues: issues
            )
        }
    }

    package static func validateCollection(_ recipes: [FilmRecipe]) throws {
        var issues: [RecipeValidationIssue] = []
        var seenProfileIDs: Set<String> = []

        for recipe in recipes {
            issues.append(contentsOf: self.issues(for: recipe))

            let profileID = recipe.profileId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !profileID.isEmpty, !seenProfileIDs.insert(profileID).inserted {
                issues.append(RecipeValidationIssue("Duplicate profile_id '\(profileID)' is not allowed."))
            }
        }

        guard issues.isEmpty else {
            throw FilmRecipeValidationError.invalidRecipe(
                profileID: "recipe collection",
                issues: issues
            )
        }
    }

    package static func issues(for recipe: FilmRecipe) -> [RecipeValidationIssue] {
        var issues: [RecipeValidationIssue] = []

        requireNonEmpty(recipe.schemaVersion, field: "schema_version", issues: &issues)
        if !supportedSchemaVersions.contains(recipe.schemaVersion) {
            issues.append(RecipeValidationIssue("Unsupported schema_version '\(recipe.schemaVersion)'."))
        }

        requireNonEmpty(recipe.profileId, field: "profile_id", issues: &issues)
        requireNonEmpty(recipe.displayName, field: "display_name", issues: &issues)
        requireNonEmpty(recipe.manufacturer, field: "manufacturer", issues: &issues)
        requireNonEmpty(recipe.summary, field: "summary", issues: &issues)

        requirePositive(recipe.stock.boxSpeedIso, field: "stock.box_speed_iso", issues: &issues)
        requirePositive(recipe.exposure.boxSpeedIso, field: "exposure.box_speed_iso", issues: &issues)
        requirePositive(recipe.exposure.exposedAtIso, field: "exposure.exposed_at_iso", issues: &issues)
        requirePositive(recipe.format.frameSizeMm.width, field: "format.frame_size_mm.width", issues: &issues)
        requirePositive(recipe.format.frameSizeMm.height, field: "format.frame_size_mm.height", issues: &issues)
        requirePositive(recipe.format.defaultAspectRatio, field: "format.default_aspect_ratio", issues: &issues)

        if recipe.layerModel.rgbToLayerMatrix.isEmpty {
            issues.append(RecipeValidationIssue("layer_model.rgb_to_layer_matrix must include at least one row."))
        }

        if recipe.stock.family != .blackAndWhiteNegative, recipe.layerModel.rgbToLayerMatrix.count != 3 {
            issues.append(RecipeValidationIssue("Color recipes must provide a 3-row layer_model.rgb_to_layer_matrix."))
        }

        for (index, row) in recipe.layerModel.rgbToLayerMatrix.enumerated() where row.count != 3 {
            issues.append(RecipeValidationIssue("layer_model.rgb_to_layer_matrix row \(index + 1) must contain 3 values."))
        }

        let curveChannels = Set(recipe.characteristicCurves.channels.keys)
        if recipe.stock.family == .blackAndWhiteNegative {
            if !curveChannels.contains("luminance") {
                issues.append(RecipeValidationIssue("Black and white recipes must include a luminance characteristic curve."))
            }
        } else if !["red", "green", "blue"].allSatisfy(curveChannels.contains) {
            issues.append(RecipeValidationIssue("Color recipes must include red, green, and blue characteristic curves."))
        }

        if recipe.renderer.whitePoint <= recipe.renderer.blackPoint {
            issues.append(RecipeValidationIssue("renderer.white_point must be greater than renderer.black_point."))
        }

        requirePositive(recipe.output.bitDepth, field: "output.bit_depth", issues: &issues)

        return issues
    }

    private static func requireNonEmpty(
        _ value: String,
        field: String,
        issues: inout [RecipeValidationIssue]
    ) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(RecipeValidationIssue("\(field) must not be empty."))
        }
    }

    private static func requirePositive(
        _ value: Int,
        field: String,
        issues: inout [RecipeValidationIssue]
    ) {
        if value <= 0 {
            issues.append(RecipeValidationIssue("\(field) must be greater than 0."))
        }
    }

    private static func requirePositive(
        _ value: Double,
        field: String,
        issues: inout [RecipeValidationIssue]
    ) {
        if !value.isFinite || value <= 0 {
            issues.append(RecipeValidationIssue("\(field) must be greater than 0."))
        }
    }

    private static func validationName(for recipe: FilmRecipe) -> String {
        let profileID = recipe.profileId.trimmingCharacters(in: .whitespacesAndNewlines)
        return profileID.isEmpty ? "imported recipe" : profileID
    }
}
