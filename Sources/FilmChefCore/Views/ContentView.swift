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
                Button {
                    editor.beginImport()
                } label: {
                    Label("Import", systemImage: "photo.badge.plus")
                }

                Button {
                    editor.exportEditedPhoto()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .disabled(!editor.canExport)
            }
        }
        .fileImporter(
            isPresented: $editor.isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: editor.handleImportResults
        )
        .alert(
            "Film Chef",
            isPresented: Binding(
                get: { editor.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        editor.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                editor.errorMessage = nil
            }
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }
}
