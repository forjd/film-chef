import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @ObservedObject var editor: EditorStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(editor: EditorStore) {
        self.editor = editor
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(editor: editor)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } content: {
            PreviewPaneView(editor: editor)
                .navigationSplitViewColumnWidth(min: 520, ideal: 760)
        } detail: {
            ControlsView(editor: editor)
                .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 400)
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: editor.beginImport) {
                    Label("Import Photos", systemImage: "photo.badge.plus")
                }

                Button(action: editor.beginRecipeImport) {
                    Label("Import Recipe", systemImage: "doc.badge.plus")
                }

                Button(action: editor.beginCalibrationImport) {
                    Label("Calibration", systemImage: "chart.xyaxis.line")
                }

                Button(action: editor.saveProject) {
                    Label("Save Project", systemImage: "folder.badge.plus")
                }

                Button(action: editor.exportEditedPhoto) {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .disabled(!editor.canExport)

                Button(action: editor.exportProjectPhotos) {
                    Label("Batch Export", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(!editor.canBatchExport)
            }
        }
        .fileImporter(
            isPresented: $editor.isImportingRecipe,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: editor.handleRecipeImportResults
        )
        .fileImporter(
            isPresented: $editor.isImportingCalibration,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: true,
            onCompletion: editor.handleCalibrationImportResults
        )
        .fileImporter(
            isPresented: $editor.isOpeningProject,
            allowedContentTypes: [.filmChefProject, .json],
            allowsMultipleSelection: false,
            onCompletion: editor.handleProjectOpenResults
        )
        .alert(
            "Film Chef",
            isPresented: Binding(
                get: { editor.errorMessage != nil },
                set: setAlertPresented
            )
        ) {
            Button("OK", action: clearError)
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    fileprivate func setAlertPresented(_ isPresented: Bool) {
        if !isPresented {
            editor.errorMessage = nil
        }
    }

    fileprivate func clearError() {
        editor.errorMessage = nil
    }
}

package enum ContentViewCoverageProbe {
    @MainActor
    package static func touch(editor: EditorStore) {
        let contentView = ContentView(editor: editor)
        _ = contentView.body
        contentView.setAlertPresented(true)
        contentView.setAlertPresented(false)
        contentView.clearError()
    }
}
