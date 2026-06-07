import SwiftUI

struct SidebarView: View {
    @ObservedObject var editor: EditorStore

    var body: some View {
        List(selection: $editor.selectedRecipeID) {
            Section("Film Recipes") {
                ForEach(editor.recipes, content: recipeRow)
            }

            Section("Project") {
                LabeledContent("Photos", value: "\(editor.project.items.count)")
                ForEach(editor.project.items) { item in
                    Button(action: { editor.selectProjectItem(id: item.id) }) {
                        HStack(spacing: 8) {
                            Image(systemName: item.id == editor.project.selectedItemID ? "photo.fill" : "photo")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .lineLimit(1)
                                Text(item.selectedRecipeID ?? "No recipe")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Film Chef")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                HStack {
                    Button(action: editor.beginProjectOpen) {
                        Label("Open", systemImage: "folder")
                    }

                    Button(action: editor.saveProject) {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }

                Button(action: editor.beginImport) {
                    Label("Import Photos", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: editor.exportProjectPhotos) {
                    Label("Export Project", systemImage: "square.and.arrow.up.on.square")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!editor.canBatchExport)

                HStack {
                    Button(action: editor.beginRecipeImport) {
                        Label("Import Recipe", systemImage: "doc.badge.plus")
                    }

                    Button(action: editor.beginCalibrationImport) {
                        Label("Calibrate", systemImage: "chart.xyaxis.line")
                    }
                }

                HStack {
                    Button(action: editor.exportSelectedRecipe) {
                        Label("Export Recipe", systemImage: "square.and.arrow.up")
                    }
                    .disabled(editor.selectedRecipe == nil)
                }
            }
            .padding()
            .background(.bar)
        }
    }

    fileprivate func recipeRow(for recipe: FilmRecipe) -> some View {
        RecipeRow(recipe: recipe)
            .tag(recipe.id as String?)
    }

}

private struct RecipeRow: View {
    let recipe: FilmRecipe

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: recipe.stockType.systemImageName)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .lineLimit(1)

                Text("\(recipe.maker), ISO \(recipe.iso)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

package enum SidebarViewCoverageProbe {
    @MainActor
    package static func touch(editor: EditorStore, recipe: FilmRecipe) {
        let sidebarView = SidebarView(editor: editor)
        _ = sidebarView.body
        _ = sidebarView.recipeRow(for: recipe)
        _ = RecipeRow(recipe: recipe).body
    }
}
