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
            Button("Import Photo...") {
                editor.beginImport()
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("Export Edited Photo...") {
                editor.exportEditedPhoto()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!editor.canExport)

            Divider()

            Button("Reset Adjustments") {
                editor.resetControls()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
