import Foundation

package final class ProjectStore {
    package enum ProjectStoreError: LocalizedError {
        case unsupportedSchema(Int)
        case missingPhotoReference

        package var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                return "Film Chef project schema \(version) is not supported."
            case .missingPhotoReference:
                return "The project does not contain a restorable photo reference."
            }
        }
    }

    package init() {}

    package func loadProject(from url: URL) throws -> FilmProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        let project = try decoder.decode(FilmProject.self, from: data)

        guard project.schemaVersion == 1 else {
            throw ProjectStoreError.unsupportedSchema(project.schemaVersion)
        }

        return project
    }

    package func writeProject(_ project: FilmProject, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        // Atomic so a crash mid-save cannot truncate the user's only copy.
        try data.write(to: url, options: [.atomic])
    }

    package func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    package func resolvePhotoURL(for item: FilmProjectItem) throws -> URL {
        try resolvePhotoReference(for: item).url
    }

    package func resolvePhotoReference(for item: FilmProjectItem) throws -> (url: URL, refreshedBookmarkData: Data?) {
        if let bookmarkData = item.originalBookmarkData {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if !isStale {
                return (url, nil)
            }

            // Creating a security-scoped bookmark requires active access to
            // the resource in a sandboxed process.
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return (url, self.bookmarkData(for: url))
        }

        if let path = item.originalURLPath, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            return (url, bookmarkData(for: url))
        }

        throw ProjectStoreError.missingPhotoReference
    }
}
