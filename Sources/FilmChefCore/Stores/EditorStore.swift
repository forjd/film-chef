import AppKit
import CoreImage
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class EditorStore: ObservableObject {
    @Published private(set) var recipes: [FilmRecipe] = []
    @Published var selectedRecipeID: String? {
        didSet { renderPreviewIfNeeded() }
    }

    @Published private(set) var importedImageName: String?
    @Published private(set) var originalPreviewImage: NSImage?
    @Published private(set) var editedPreviewImage: NSImage?
    @Published var isImporting = false
    @Published var errorMessage: String?

    @Published var showOriginal = false
    @Published var intensity = RenderAdjustments.defaults.intensity {
        didSet { renderPreviewIfNeeded() }
    }
    @Published var exposureTrim = RenderAdjustments.defaults.exposureTrim {
        didSet { renderPreviewIfNeeded() }
    }
    @Published var contrastTrim = RenderAdjustments.defaults.contrastTrim {
        didSet { renderPreviewIfNeeded() }
    }
    @Published var saturationTrim = RenderAdjustments.defaults.saturationTrim {
        didSet { renderPreviewIfNeeded() }
    }
    @Published var grainEnabled = RenderAdjustments.defaults.grainEnabled {
        didSet { renderPreviewIfNeeded() }
    }

    private let recipeStore: RecipeStore
    private let imageProcessor = ImageProcessor()
    private var sourceImage: CIImage?
    private var sourceURL: URL?
    private var suppressPreviewUpdates = false

    public init(recipeStore: RecipeStore) {
        self.recipeStore = recipeStore
    }

    var selectedRecipe: FilmRecipe? {
        recipes.first { $0.id == selectedRecipeID }
    }

    var displayedPreviewImage: NSImage? {
        showOriginal ? originalPreviewImage : editedPreviewImage
    }

    var hasImportedImage: Bool {
        sourceImage != nil
    }

    public var canExport: Bool {
        sourceImage != nil && selectedRecipe != nil
    }

    var currentAdjustments: RenderAdjustments {
        RenderAdjustments(
            intensity: intensity,
            exposureTrim: exposureTrim,
            contrastTrim: contrastTrim,
            saturationTrim: saturationTrim,
            grainEnabled: grainEnabled
        )
    }

    public func loadRecipesIfNeeded() {
        guard recipes.isEmpty else {
            return
        }

        do {
            recipes = try recipeStore.loadRecipes()
            selectedRecipeID = recipes.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func beginImport() {
        isImporting = true
    }

    func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importPhoto(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func handleImportResults(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }

            importPhoto(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    public func resetControls() {
        suppressPreviewUpdates = true
        intensity = RenderAdjustments.defaults.intensity
        exposureTrim = RenderAdjustments.defaults.exposureTrim
        contrastTrim = RenderAdjustments.defaults.contrastTrim
        saturationTrim = RenderAdjustments.defaults.saturationTrim
        grainEnabled = RenderAdjustments.defaults.grainEnabled
        showOriginal = false
        suppressPreviewUpdates = false
        renderPreviewIfNeeded()
    }

    public func exportEditedPhoto() {
        guard canExport else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Edited Photo"
        panel.allowedContentTypes = [.jpeg, .png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedExportFileName()

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            Task { @MainActor in
                self?.writeExport(to: url)
            }
        }
    }

    private func importPhoto(from url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let loadedImage = try imageProcessor.loadSourceImage(from: url)
            sourceImage = loadedImage
            sourceURL = url
            importedImageName = url.lastPathComponent
            originalPreviewImage = try imageProcessor.makePreviewImage(from: loadedImage)
            showOriginal = false
            renderPreviewIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func writeExport(to url: URL) {
        guard let sourceImage, let selectedRecipe else {
            return
        }

        do {
            try imageProcessor.writeRenderedImage(
                from: sourceImage,
                recipe: selectedRecipe,
                adjustments: currentAdjustments,
                to: url
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renderPreviewIfNeeded() {
        guard !suppressPreviewUpdates,
              let sourceImage,
              let selectedRecipe
        else {
            return
        }

        do {
            editedPreviewImage = try imageProcessor.renderPreviewImage(
                from: sourceImage,
                recipe: selectedRecipe,
                adjustments: currentAdjustments
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func suggestedExportFileName() -> String {
        let baseName = sourceURL?
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let safeBaseName = baseName?.isEmpty == false ? baseName! : "film-chef-photo"
        let recipeSlug = selectedRecipe?.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "+", with: "plus")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()

        if let recipeSlug, !recipeSlug.isEmpty {
            return "\(safeBaseName)-\(recipeSlug).jpg"
        }

        return "\(safeBaseName)-edited.jpg"
    }
}
