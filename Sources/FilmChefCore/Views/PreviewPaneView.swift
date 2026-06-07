import SwiftUI

struct PreviewPaneView: View {
    @ObservedObject var editor: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            previewHeader

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if editor.hasImportedImage {
                    interactivePreview
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

            Picker("Compare", selection: $editor.comparisonMode) {
                ForEach(PreviewComparisonMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 300, idealWidth: 340)
            .disabled(!editor.hasImportedImage)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch editor.comparisonMode {
        case .edited, .original:
            if let image = editor.displayedPreviewImage {
                previewImage(image)
            }
        case .split:
            if let original = editor.originalPreviewImage, let edited = editor.editedPreviewImage {
                splitPreview(original: original, edited: edited)
            }
        case .sideBySide:
            if let original = editor.originalPreviewImage, let edited = editor.editedPreviewImage {
                HStack(spacing: 0) {
                    labelledPreview(title: "Original", image: original)
                    Divider()
                    labelledPreview(title: "Edited", image: edited)
                }
            }
        }
    }

    private var interactivePreview: some View {
        GeometryReader { proxy in
            ZStack {
                previewContent
                samplerOverlay(in: proxy.size)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        samplePreview(at: value.location, in: proxy.size)
                    }
            )
        }
    }

    private func previewImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .scaleEffect(editor.previewZoom)
            .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
            .padding(32)
    }

    private func labelledPreview(title: String, image: NSImage) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            previewImage(image)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func splitPreview(original: NSImage, edited: NSImage) -> some View {
        GeometryReader { proxy in
            ZStack {
                previewImage(edited)

                HStack(spacing: 0) {
                    previewImage(original)
                        .frame(width: proxy.size.width * editor.splitPosition)
                        .clipped()
                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(.white.opacity(0.75))
                    .frame(width: 3)
                    .shadow(radius: 2)
                    .position(x: proxy.size.width * editor.splitPosition, y: proxy.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("splitPreview"))
                            .onChanged { value in
                                editor.splitPosition = clampedUnit(Double(value.location.x / proxy.size.width))
                            }
                    )

                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.72))
                    .padding(7)
                    .background(.white.opacity(0.82), in: Circle())
                    .shadow(radius: 2)
                    .position(x: proxy.size.width * editor.splitPosition, y: proxy.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("splitPreview"))
                            .onChanged { value in
                                editor.splitPosition = clampedUnit(Double(value.location.x / proxy.size.width))
                            }
                    )
            }
            .coordinateSpace(name: "splitPreview")
        }
    }

    private func samplerOverlay(in size: CGSize) -> some View {
        let markerX = size.width * editor.samplerX
        let markerY = size.height * (1 - editor.samplerY)

        return ZStack(alignment: .topLeading) {
            Circle()
                .stroke(.white.opacity(0.95), lineWidth: 2)
                .background(Circle().stroke(.black.opacity(0.55), lineWidth: 4))
                .frame(width: 18, height: 18)
                .position(x: markerX, y: markerY)
                .allowsHitTesting(false)

            if let sample = editor.pixelSample {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sampleRGBText(sample))
                        .font(.caption2.monospacedDigit())
                        .fontWeight(.semibold)
                    Text(String(format: "X %.2f  Y %.2f  L %.2f", sample.x, sample.y, sample.luminance))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
                .position(
                    x: clamped(markerX + 76, lower: 78, upper: max(78, size.width - 78)),
                    y: clamped(markerY - 34, lower: 28, upper: max(28, size.height - 28))
                )
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }

    private func samplePreview(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        editor.samplePreviewPixel(
            x: Double(location.x / size.width),
            y: Double(1 - (location.y / size.height))
        )
    }

    private func sampleRGBText(_ sample: PixelSample) -> String {
        let red = Int((sample.red * 255).rounded())
        let green = Int((sample.green * 255).rounded())
        let blue = Int((sample.blue * 255).rounded())
        return "RGB \(red) \(green) \(blue)"
    }

    private func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0.05), 0.95)
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private var originalToggle: some View {
        Toggle("Original", isOn: $editor.showOriginal)
            .toggleStyle(.switch)
                .disabled(!editor.hasImportedImage)
    }

    fileprivate var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)

            Text("No Photo")
                .font(.title3)
                .fontWeight(.semibold)

            Button(action: editor.beginImport) {
                Label("Import Photo", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(34)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

}

package enum PreviewPaneViewCoverageProbe {
    @MainActor
    package static func touch(editor: EditorStore) {
        let previewPaneView = PreviewPaneView(editor: editor)
        _ = previewPaneView.body
        _ = previewPaneView.emptyState
    }
}
