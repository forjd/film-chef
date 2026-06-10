import Foundation

extension EditorStore {
    package static func exportNamingTemplateIssues(for template: String) -> [String] {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["Naming template must not be empty."]
        }

        var issues: [String] = []
        let allowedTokens = Set(["photo", "recipe", "format"])
        let scanner = Array(trimmed)
        var index = scanner.startIndex

        while index < scanner.endIndex {
            let character = scanner[index]
            if character == "}" {
                issues.append("Naming template has a closing brace without an opening brace.")
                index = scanner.index(after: index)
                continue
            }
            guard character == "{" else {
                index = scanner.index(after: index)
                continue
            }

            guard let closeIndex = scanner[index...].firstIndex(of: "}") else {
                issues.append("Naming template has an opening brace without a closing brace.")
                break
            }

            let tokenStart = scanner.index(after: index)
            let token = String(scanner[tokenStart..<closeIndex])
            if !allowedTokens.contains(token) {
                issues.append("Unsupported naming token {\(token)}. Use {photo}, {recipe}, or {format}.")
            }
            index = scanner.index(after: closeIndex)
        }

        return Array(Set(issues)).sorted()
    }

    nonisolated package static func uniqueExportURL(
        in directory: URL,
        item: FilmProjectItem,
        recipe: FilmRecipe,
        settings: ExportSettings
    ) -> URL {
        let baseName = sanitizedFileComponent(
            settings.namingTemplate
                .replacingOccurrences(
                    of: "{photo}",
                    with: URL(fileURLWithPath: item.displayName).deletingPathExtension().lastPathComponent
                )
                .replacingOccurrences(of: "{recipe}", with: recipe.name)
                .replacingOccurrences(of: "{format}", with: settings.fileFormat.label)
        )
        let fileExtension = settings.fileFormat.preferredPathExtension
        var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).\(fileExtension)")
            suffix += 1
        }

        return candidate
    }

    nonisolated package static func sanitizedFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = value
            .components(separatedBy: allowed.inverted)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()

        return cleaned.isEmpty ? "photo" : cleaned
    }
}
