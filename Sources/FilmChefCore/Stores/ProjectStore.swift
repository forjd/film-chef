import Foundation

package final class ProjectStore {
    private static let maxProjectByteCount = 64 * 1024 * 1024

    package enum ProjectStoreError: LocalizedError {
        case unsupportedSchema(Int)
        case missingPhotoReference
        case oversizedProject(String)

        package var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                return "Film Chef project schema \(version) is not supported."
            case .missingPhotoReference:
                return "The project does not contain a restorable photo reference."
            case .oversizedProject(let name):
                return "\(name) is too large to open as a Film Chef project."
            }
        }
    }

    package init() {}

    package func loadProject(from url: URL) throws -> FilmProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try projectData(from: url)
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

    private func projectData(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize > Self.maxProjectByteCount {
            throw ProjectStoreError.oversizedProject(url.lastPathComponent)
        }
        return try Data(contentsOf: url)
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
