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
    private static let profileIDAllowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")

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
            let normalizedProfileID = profileID.lowercased()
            if !profileID.isEmpty, !seenProfileIDs.insert(normalizedProfileID).inserted {
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
        validateProfileID(recipe.profileId, issues: &issues)
        requireNonEmpty(recipe.displayName, field: "display_name", issues: &issues)
        requireNonEmpty(recipe.manufacturer, field: "manufacturer", issues: &issues)
        requireNonEmpty(recipe.summary, field: "summary", issues: &issues)

        requirePositive(recipe.stock.boxSpeedIso, field: "stock.box_speed_iso", issues: &issues)
        requirePositive(recipe.exposure.boxSpeedIso, field: "exposure.box_speed_iso", issues: &issues)
        requirePositive(recipe.exposure.exposedAtIso, field: "exposure.exposed_at_iso", issues: &issues)
        requirePositive(recipe.format.frameSizeMm.width, field: "format.frame_size_mm.width", issues: &issues)
        requirePositive(recipe.format.frameSizeMm.height, field: "format.frame_size_mm.height", issues: &issues)
        requirePositive(recipe.format.defaultAspectRatio, field: "format.default_aspect_ratio", issues: &issues)
        requireRange(recipe.exposure.middleGrey, field: "exposure.middle_grey", range: 0.01...0.99, issues: &issues)
        requireRange(recipe.exposure.exposureCompensationEv, field: "exposure.exposure_compensation_ev", range: -8...8, issues: &issues)
        requireOptionalRange(recipe.exposure.highlightProtection, field: "exposure.highlight_protection", range: 0...1, issues: &issues)
        requireOptionalRange(recipe.exposure.shadowLiftBeforeFilm, field: "exposure.shadow_lift_before_film", range: 0...1, issues: &issues)
        requireRange(Double(recipe.captureConditions.colourTemperatureK), field: "capture_conditions.colour_temperature_k", range: 1000...40000, issues: &issues)
        requireRange(recipe.captureConditions.filter.strength, field: "capture_conditions.filter.strength", range: 0...1, issues: &issues)
        requireOptionalRange(recipe.captureConditions.lensContrast, field: "capture_conditions.lens_contrast", range: 0.1...3, issues: &issues)
        requireOptionalRange(recipe.captureConditions.lensFlare, field: "capture_conditions.lens_flare", range: 0...1, issues: &issues)

        if recipe.layerModel.rgbToLayerMatrix.isEmpty {
            issues.append(RecipeValidationIssue("layer_model.rgb_to_layer_matrix must include at least one row."))
        }

        if recipe.stock.family != .blackAndWhiteNegative, recipe.layerModel.rgbToLayerMatrix.count != 3 {
            issues.append(RecipeValidationIssue("Color recipes must provide a 3-row layer_model.rgb_to_layer_matrix."))
        }

        for (index, row) in recipe.layerModel.rgbToLayerMatrix.enumerated() where row.count != 3 {
            issues.append(RecipeValidationIssue("layer_model.rgb_to_layer_matrix row \(index + 1) must contain 3 values."))
        }
        for (rowIndex, row) in recipe.layerModel.rgbToLayerMatrix.enumerated() {
            for (columnIndex, value) in row.enumerated() where !value.isFinite || abs(value) > 4 {
                issues.append(RecipeValidationIssue("layer_model.rgb_to_layer_matrix value \(rowIndex + 1).\(columnIndex + 1) must be finite and between -4 and 4."))
            }
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
        validateCurves(recipe.characteristicCurves.channels, issues: &issues)
        requireOptionalRange(recipe.colourModel.saturation, field: "colour_model.saturation", range: 0...3, issues: &issues)
        requireOptionalRange(recipe.colourModel.warmth, field: "colour_model.warmth", range: -1...1, issues: &issues)
        requireOptionalRange(recipe.colourModel.skinToneProtection, field: "colour_model.skin_tone_protection", range: 0...1, issues: &issues)
        if let hueBias = recipe.colourModel.hueBias {
            requireRange(hueBias.reds, field: "colour_model.hue_bias.reds", range: -1...1, issues: &issues)
            requireRange(hueBias.yellows, field: "colour_model.hue_bias.yellows", range: -1...1, issues: &issues)
            requireRange(hueBias.greens, field: "colour_model.hue_bias.greens", range: -1...1, issues: &issues)
            requireRange(hueBias.cyans, field: "colour_model.hue_bias.cyans", range: -1...1, issues: &issues)
            requireRange(hueBias.blues, field: "colour_model.hue_bias.blues", range: -1...1, issues: &issues)
            requireRange(hueBias.magentas, field: "colour_model.hue_bias.magentas", range: -1...1, issues: &issues)
        }
        requireRange(recipe.process.pushPullStops, field: "process.push_pull_stops", range: -5...5, issues: &issues)
        requireRange(recipe.process.contrastMultiplier, field: "process.contrast_multiplier", range: 0.1...4, issues: &issues)
        requireRange(recipe.process.speedGainEv, field: "process.speed_gain_ev", range: -5...5, issues: &issues)
        requireRange(recipe.process.grainMultiplier, field: "process.grain_multiplier", range: 0...5, issues: &issues)
        requireRange(recipe.grain.strength, field: "grain.strength", range: 0...2, issues: &issues)
        requireRange(recipe.grain.size, field: "grain.size", range: 0...5, issues: &issues)
        requireRange(recipe.grain.clumpiness, field: "grain.clumpiness", range: 0...1, issues: &issues)
        requireRange(recipe.grain.softness, field: "grain.softness", range: 0...1, issues: &issues)
        requireRange(recipe.grain.chromaticity, field: "grain.chromaticity", range: 0...1, issues: &issues)
        requireRange(recipe.halation.threshold, field: "halation.threshold", range: 0...1, issues: &issues)
        requireRange(recipe.halation.strength, field: "halation.strength", range: 0...2, issues: &issues)
        requireRange(recipe.halation.radius, field: "halation.radius", range: 0...100, issues: &issues)
        requireOptionalRange(recipe.halation.edgePreservation, field: "halation.edge_preservation", range: 0...1, issues: &issues)
        requireRange(recipe.sharpness.filmMtfBlur, field: "sharpness.film_mtf_blur", range: 0...20, issues: &issues)
        requireRange(recipe.sharpness.scannerMtfBlur, field: "sharpness.scanner_mtf_blur", range: 0...20, issues: &issues)
        requireRange(recipe.sharpness.acutance, field: "sharpness.acutance", range: 0...3, issues: &issues)
        requireRange(recipe.sharpness.digitalSharpening, field: "sharpness.digital_sharpening", range: 0...3, issues: &issues)
        requireRange(recipe.renderer.blackPoint, field: "renderer.black_point", range: 0...1, issues: &issues)
        requireRange(recipe.renderer.whitePoint, field: "renderer.white_point", range: 0...1.5, issues: &issues)
        requireRange(recipe.renderer.contrast, field: "renderer.contrast", range: 0.1...4, issues: &issues)
        requireRange(recipe.renderer.saturation, field: "renderer.saturation", range: 0...4, issues: &issues)
        requireOptionalRange(recipe.renderer.sharpening, field: "renderer.sharpening", range: 0...3, issues: &issues)
        if let scannerMtf = recipe.renderer.scannerMtf {
            requireRange(scannerMtf.blurRadius, field: "renderer.scanner_mtf.blur_radius", range: 0...20, issues: &issues)
            requireRange(scannerMtf.microcontrast, field: "renderer.scanner_mtf.microcontrast", range: 0...3, issues: &issues)
        }

        requirePositive(recipe.output.bitDepth, field: "output.bit_depth", issues: &issues)
        if ![8, 10, 12, 16, 32].contains(recipe.output.bitDepth) {
            issues.append(RecipeValidationIssue("output.bit_depth must be one of 8, 10, 12, 16, or 32."))
        }

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

    private static func validateProfileID(_ value: String, issues: inout [RecipeValidationIssue]) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }

        if value != trimmedValue {
            issues.append(RecipeValidationIssue("profile_id must not contain leading or trailing whitespace."))
        }
        if trimmedValue.rangeOfCharacter(from: profileIDAllowedCharacters.inverted) != nil {
            issues.append(RecipeValidationIssue("profile_id must use lowercase ASCII letters, numbers, hyphens, or underscores only."))
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

    private static func requireRange(
        _ value: Double,
        field: String,
        range: ClosedRange<Double>,
        issues: inout [RecipeValidationIssue]
    ) {
        if !value.isFinite || !range.contains(value) {
            issues.append(RecipeValidationIssue("\(field) must be between \(format(range.lowerBound)) and \(format(range.upperBound))."))
        }
    }

    private static func requireOptionalRange(
        _ value: Double?,
        field: String,
        range: ClosedRange<Double>,
        issues: inout [RecipeValidationIssue]
    ) {
        guard let value else {
            return
        }
        requireRange(value, field: field, range: range, issues: &issues)
    }

    private static func validateCurves(
        _ channels: [String: FilmCharacteristicCurve],
        issues: inout [RecipeValidationIssue]
    ) {
        for (channel, curve) in channels {
            requireRange(curve.toe, field: "characteristic_curves.channels.\(channel).toe", range: 0...2, issues: &issues)
            requireRange(curve.gamma, field: "characteristic_curves.channels.\(channel).gamma", range: 0.05...5, issues: &issues)
            requireRange(curve.shoulder, field: "characteristic_curves.channels.\(channel).shoulder", range: 0...2, issues: &issues)
            requireRange(curve.dMin, field: "characteristic_curves.channels.\(channel).d_min", range: 0...4, issues: &issues)
            requireRange(curve.dMax, field: "characteristic_curves.channels.\(channel).d_max", range: 0...8, issues: &issues)
            if curve.dMax <= curve.dMin {
                issues.append(RecipeValidationIssue("characteristic_curves.channels.\(channel).d_max must be greater than d_min."))
            }
        }
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private static func validationName(for recipe: FilmRecipe) -> String {
        let profileID = recipe.profileId.trimmingCharacters(in: .whitespacesAndNewlines)
        return profileID.isEmpty ? "imported recipe" : profileID
    }
}
