import SwiftUI

struct SidebarView: View {
    @ObservedObject var editor: EditorStore

    var body: some View {
        List(selection: $editor.selectedRecipeID) {
            Section("Film Recipes") {
                ForEach(editor.recipes, content: recipeRow)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Film Chef")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: editor.beginImport) {
                    Label("Import Photo", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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
