import AppKit
import FilmChefCore
import SwiftUI

@main
struct FilmChefApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var editor = EditorStore(recipeStore: RecipeStore())

    var body: some Scene {
        WindowGroup("Film Chef") {
            ContentView(editor: editor)
                .frame(minWidth: 1040, minHeight: 680)
                .task {
                    appDelegate.editor = editor
                    editor.loadRecipesIfNeeded()
                }
        }
        .commands {
            FilmChefCommands(editor: editor)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // The bundle declares ownership of .filmchef documents, so Finder routes
    // double-clicked project files here. Files can arrive before the SwiftUI
    // scene assigns the editor, so buffer them until it does.
    var editor: EditorStore? {
        didSet {
            openPendingProjectURLs()
        }
    }
    private var pendingProjectURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingProjectURLs.append(contentsOf: urls.filter { $0.pathExtension.lowercased() == "filmchef" })
        openPendingProjectURLs()
    }

    private func openPendingProjectURLs() {
        guard let editor, !pendingProjectURLs.isEmpty else {
            return
        }

        let urls = pendingProjectURLs
        pendingProjectURLs = []
        for url in urls {
            editor.handleProjectOpenResults(.success([url]))
        }
    }
}

struct FilmChefCommands: Commands {
    @ObservedObject var editor: EditorStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Project...") {
                editor.beginProjectOpen()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Save Project...") {
                editor.saveProject()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Divider()

            Button("Import Photos...") {
                editor.beginImport()
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("Export Edited Photo...") {
                editor.exportEditedPhoto()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!editor.canExportCurrentSettings)

            Button("Export Project Photos...") {
                editor.exportProjectPhotos()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(!editor.canBatchExport)

            Button("Import Film Recipe...") {
                editor.beginRecipeImport()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Import Calibration Assets...") {
                editor.beginCalibrationImport()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Export Selected Recipe...") {
                editor.exportSelectedRecipe()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(editor.selectedRecipe == nil)

            Divider()

            Button("Reset Adjustments") {
                editor.resetControls()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        // Replace the system items: adding alongside them leaves two menu
        // items on Cmd+Z and makes keyboard undo focus-dependent.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Edit") {
                editor.undoEdit()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(!editor.canUndoEdit)

            Button("Redo Edit") {
                editor.redoEdit()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!editor.canRedoEdit)

            Button("Capture Variant") {
                editor.captureVariant()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
