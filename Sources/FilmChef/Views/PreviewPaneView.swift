import SwiftUI

struct PreviewPaneView: View {
    @ObservedObject var editor: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            previewHeader

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if let image = editor.displayedPreviewImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
                        .padding(32)
                } else {
                    emptyState
                }
            }
        }
        .navigationTitle(editor.importedImageName ?? "Preview")
    }

    private var previewHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.importedImageName ?? "No Photo")
                    .font(.headline)
                    .lineLimit(1)

                Text(editor.selectedRecipe?.name ?? "No recipe selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("Original", isOn: $editor.showOriginal)
                .toggleStyle(.switch)
                .disabled(!editor.hasImportedImage)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("No Photo")
                .font(.title3)
                .fontWeight(.semibold)

            Button {
                editor.beginImport()
            } label: {
                Label("Import Photo", systemImage: "photo.badge.plus")
            }
            .controlSize(.large)
        }
        .foregroundStyle(.secondary)
    }
}
