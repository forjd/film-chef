import SwiftUI

struct PreviewPaneView: View {
    @ObservedObject var editor: EditorStore
    @State private var panDragStart = CGSize.zero
    @State private var isEditingLocalMaskDrag = false
    @State private var isDraggingSplitDivider = false
    @State private var liveSplitPosition = 0.5
    @State private var isDraggingSampler = false
    @State private var liveSamplerX = 0.5
    @State private var liveSamplerY = 0.5

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

            if editor.isRenderingPreview {
                ProgressView(value: editor.previewRenderProgress)
                    .frame(width: 120)
                    .help(editor.previewRenderStatus)
            }

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
                splitPreview(original: original, edited: edited)
            }
        }
    }

    private var interactivePreview: some View {
        GeometryReader { proxy in
            ZStack {
                previewContent
                maskOverlay(in: proxy.size)
                samplerOverlay(in: proxy.size)
                loupeOverlay(in: proxy.size)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !shouldReserveDragForSplitDivider(value, in: proxy.size) else {
                            return
                        }
                        if editor.localMaskEditingEnabled, editor.canEditLocalMaskOnPreview {
                            editLocalMask(at: value.location, in: proxy.size)
                        } else if editor.previewZoom > 1.0 {
                            editor.setPreviewPan(
                                x: panDragStart.width + value.translation.width,
                                y: panDragStart.height + value.translation.height
                            )
                            updateSampleMarker(at: value.location, in: proxy.size)
                        } else {
                            updateSampleMarker(at: value.location, in: proxy.size)
                        }
                    }
                    .onEnded { _ in
                        if isEditingLocalMaskDrag {
                            editor.endLocalMaskEditAtPreviewPoint()
                            isEditingLocalMaskDrag = false
                        }
                        if isDraggingSampler {
                            commitLiveSampleMarker()
                        }
                        isDraggingSplitDivider = false
                        panDragStart = CGSize(width: editor.previewPanX, height: editor.previewPanY)
                    }
            )
            .onChange(of: editor.previewZoom) {
                if editor.previewZoom <= 1.0 {
                    editor.setPreviewPan(x: 0, y: 0)
                    panDragStart = .zero
                } else {
                    editor.setPreviewPan(x: editor.previewPanX, y: editor.previewPanY)
                }
            }
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        editor.resetPreviewView()
                        panDragStart = .zero
                    }
            )
            .onAppear {
                syncLiveSampleMarker()
            }
            .onChange(of: editor.samplerX) { _, _ in
                guard !isDraggingSampler else {
                    return
                }
                syncLiveSampleMarker()
            }
            .onChange(of: editor.samplerY) { _, _ in
                guard !isDraggingSampler else {
                    return
                }
                syncLiveSampleMarker()
            }
        }
    }

    private func previewImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .scaleEffect(editor.previewZoom)
            .offset(x: editor.previewPanX, y: editor.previewPanY)
            .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
            .padding(32)
    }

    private func splitPreview(original: NSImage, edited: NSImage) -> some View {
        GeometryReader { proxy in
            let splitPosition = currentSplitPosition
            let dividerX = proxy.size.width * splitPosition

            ZStack {
                previewImage(edited)

                previewImage(original)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: dividerX)
                    }

                Rectangle()
                    .fill(.white.opacity(0.75))
                    .frame(width: 3)
                    .shadow(radius: 2)
                    .position(x: dividerX, y: proxy.size.height / 2)
                    .allowsHitTesting(false)

                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.72))
                    .padding(7)
                    .background(.white.opacity(0.82), in: Circle())
                    .shadow(radius: 2)
                    .position(x: dividerX, y: proxy.size.height / 2)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: 48)
                    .position(x: dividerX, y: proxy.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("splitPreview"))
                            .onChanged { value in
                                updateSplitDivider(with: value.location.x, width: proxy.size.width)
                            }
                            .onEnded { value in
                                updateSplitDivider(with: value.location.x, width: proxy.size.width)
                                editor.splitPosition = liveSplitPosition
                                isDraggingSplitDivider = false
                            }
                    )
                    .accessibilityLabel("Split preview divider")
                    .accessibilityValue("\(Int(splitPosition * 100)) percent")

                HStack {
                    comparisonBadge("Original")
                    Spacer()
                    comparisonBadge("Processed")
                }
                .padding(22)
                .allowsHitTesting(false)
            }
            .coordinateSpace(name: "splitPreview")
            .transaction { transaction in
                transaction.animation = nil
            }
            .onAppear {
                liveSplitPosition = editor.splitPosition
            }
            .onChange(of: editor.splitPosition) { _, newValue in
                guard !isDraggingSplitDivider else {
                    return
                }
                liveSplitPosition = newValue
            }
        }
    }

    private func comparisonBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
    }

    private func samplerOverlay(in size: CGSize) -> some View {
        let imageFrame = previewImageFrame(in: size)
        let samplerX = currentSamplerX
        let samplerY = currentSamplerY
        let markerX = imageFrame.minX + (imageFrame.width * samplerX)
        let markerY = imageFrame.minY + (imageFrame.height * (1 - samplerY))

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
                    Text(String(format: "X %.2f  Y %.2f  L %.2f", samplerX, samplerY, sample.luminance))
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

    private func maskOverlay(in size: CGSize) -> some View {
        ZStack {
            ForEach(editor.localAdjustments.filter(\.isEnabled)) { layer in
                maskShape(for: layer, in: size)
                    .fill(.white.opacity(0.10))
                    .overlay {
                        maskShape(for: layer, in: size)
                            .stroke(
                                layer.id == editor.selectedLocalAdjustmentID ? .yellow.opacity(0.95) : .white.opacity(0.65),
                                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                            )
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private func maskShape(for layer: LocalAdjustmentLayer, in size: CGSize) -> Path {
        let center = CGPoint(
            x: size.width * CGFloat(layer.centerX),
            y: size.height * CGFloat(1 - layer.centerY)
        )
        var path = Path()

        switch layer.mask {
        case .radial:
            let radius = min(size.width, size.height) * CGFloat(layer.radius)
            path.addEllipse(
                in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        case .linear:
            let width = max(18, size.width * CGFloat(layer.radius))
            path.addRect(
                CGRect(
                    x: center.x - width / 2,
                    y: 0,
                    width: width,
                    height: size.height
                )
            )
        case .brush:
            let points = layer.pathPoints.isEmpty ? [NormalizedMaskPoint(x: layer.centerX, y: layer.centerY)] : layer.pathPoints
            let radius = max(4, min(size.width, size.height) * CGFloat(layer.brushSize) / 2)
            for point in points {
                let mapped = CGPoint(
                    x: size.width * CGFloat(point.x),
                    y: size.height * CGFloat(1 - point.y)
                )
                path.addEllipse(
                    in: CGRect(
                        x: mapped.x - radius,
                        y: mapped.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }
        case .path:
            let points = layer.pathPoints.isEmpty ? LocalAdjustmentLayer.defaultPathPoints : layer.pathPoints
            guard let first = points.first else {
                return path
            }
            path.move(
                to: CGPoint(
                    x: size.width * CGFloat(first.x),
                    y: size.height * CGFloat(1 - first.y)
                )
            )
            for point in points.dropFirst() {
                path.addLine(
                    to: CGPoint(
                        x: size.width * CGFloat(point.x),
                        y: size.height * CGFloat(1 - point.y)
                    )
                )
            }
            path.closeSubpath()
        }

        return path
    }

    @ViewBuilder
    private func loupeOverlay(in size: CGSize) -> some View {
        if editor.loupeEnabled,
           let image = editor.displayedPreviewImage ?? editor.editedPreviewImage {
            let imageFrame = previewImageFrame(in: size)
            let samplerX = currentSamplerX
            let samplerY = currentSamplerY
            let markerX = imageFrame.minX + (imageFrame.width * samplerX)
            let markerY = imageFrame.minY + (imageFrame.height * (1 - samplerY))
            let diameter: CGFloat = 154
            let resolvedLoupePosition = loupePosition(
                placement: editor.loupePlacement,
                marker: CGPoint(x: markerX, y: markerY),
                diameter: diameter,
                size: size
            )

            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .scaleEffect(editor.loupeZoom)
                    .offset(
                        x: (0.5 - samplerX) * diameter * editor.loupeZoom,
                        y: (samplerY - 0.5) * diameter * editor.loupeZoom
                    )
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())

                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))

                Rectangle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 1, height: diameter * 0.78)
                Rectangle()
                    .fill(.white.opacity(0.8))
                    .frame(width: diameter * 0.78, height: 1)
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
            .position(resolvedLoupePosition)
            .allowsHitTesting(false)
        }
    }

    private func loupePosition(
        placement: LoupePlacement,
        marker: CGPoint,
        diameter: CGFloat,
        size: CGSize
    ) -> CGPoint {
        let inset = diameter / 2 + 12
        let right = max(inset, size.width - inset)
        let bottom = max(inset, size.height - inset)

        switch placement {
        case .nearSampler:
            return CGPoint(
                x: clamped(marker.x + 112, lower: inset, upper: right),
                y: clamped(marker.y + 96, lower: inset, upper: bottom)
            )
        case .topLeft:
            return CGPoint(x: inset, y: inset)
        case .topRight:
            return CGPoint(x: right, y: inset)
        case .bottomLeft:
            return CGPoint(x: inset, y: bottom)
        case .bottomRight:
            return CGPoint(x: right, y: bottom)
        }
    }

    private func updateSampleMarker(at location: CGPoint, in size: CGSize) {
        let imageFrame = previewImageFrame(in: size)
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            return
        }

        updateLiveSampleMarker(
            x: Double((location.x - imageFrame.minX) / imageFrame.width),
            y: Double(1 - ((location.y - imageFrame.minY) / imageFrame.height))
        )
    }

    private var currentSamplerX: Double {
        isDraggingSampler ? liveSamplerX : editor.samplerX
    }

    private var currentSamplerY: Double {
        isDraggingSampler ? liveSamplerY : editor.samplerY
    }

    private func updateLiveSampleMarker(x: Double, y: Double) {
        isDraggingSampler = true
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            liveSamplerX = clampedUnit(x)
            liveSamplerY = clampedUnit(y)
        }
    }

    private func commitLiveSampleMarker() {
        editor.schedulePreviewPixelSample(x: liveSamplerX, y: liveSamplerY)
        isDraggingSampler = false
    }

    private func syncLiveSampleMarker() {
        liveSamplerX = editor.samplerX
        liveSamplerY = editor.samplerY
    }

    private var currentSplitPosition: Double {
        isDraggingSplitDivider ? liveSplitPosition : editor.splitPosition
    }

    private func updateSplitDivider(with xPosition: CGFloat, width: CGFloat) {
        guard width > 0 else {
            return
        }

        isDraggingSplitDivider = true
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            liveSplitPosition = clampedUnit(Double(xPosition / width))
        }
    }

    private func shouldReserveDragForSplitDivider(_ value: DragGesture.Value, in size: CGSize) -> Bool {
        guard editor.comparisonMode == .split, size.width > 0 else {
            return false
        }

        let dividerX = size.width * CGFloat(currentSplitPosition)
        return isDraggingSplitDivider || abs(value.startLocation.x - dividerX) <= 32
    }

    private func previewImageFrame(in size: CGSize) -> CGRect {
        let padding: CGFloat = 32
        let availableSize = CGSize(
            width: max(size.width - (padding * 2), 1),
            height: max(size.height - (padding * 2), 1)
        )
        let imageSize = (editor.displayedPreviewImage ?? editor.editedPreviewImage)?.size ?? availableSize
        let imageAspect = max(imageSize.width, 1) / max(imageSize.height, 1)
        let availableAspect = availableSize.width / availableSize.height

        let fittedSize: CGSize
        if imageAspect > availableAspect {
            fittedSize = CGSize(width: availableSize.width, height: availableSize.width / imageAspect)
        } else {
            fittedSize = CGSize(width: availableSize.height * imageAspect, height: availableSize.height)
        }

        let scaledSize = CGSize(
            width: fittedSize.width * editor.previewZoom,
            height: fittedSize.height * editor.previewZoom
        )
        return CGRect(
            x: ((size.width - scaledSize.width) / 2) + editor.previewPanX,
            y: ((size.height - scaledSize.height) / 2) + editor.previewPanY,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    private func editLocalMask(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        let x = Double(location.x / size.width)
        let y = Double(1 - (location.y / size.height))
        if isEditingLocalMaskDrag {
            editor.updateLocalMaskEditAtPreviewPoint(x: x, y: y)
        } else {
            editor.beginLocalMaskEditAtPreviewPoint(x: x, y: y)
            isEditingLocalMaskDrag = true
        }
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
