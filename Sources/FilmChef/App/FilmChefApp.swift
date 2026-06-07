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
                    editor.loadRecipesIfNeeded()
                }
        }
        .commands {
            FilmChefCommands(editor: editor)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
            .disabled(!editor.canExport)

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

        CommandGroup(after: .undoRedo) {
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
