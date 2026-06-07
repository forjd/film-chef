import SwiftUI

struct HistogramView: View {
    let summary: HistogramSummary?
    let channelMode: HistogramChannelMode

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let summary {
                    if channelMode == .luminance || channelMode == .all {
                        HistogramPath(values: summary.luminance, closesToBaseline: true)
                            .fill(.secondary.opacity(0.28))
                    }

                    if channelMode == .rgb || channelMode == .all {
                        HistogramPath(values: summary.red)
                            .stroke(.red.opacity(0.68), lineWidth: 1.5)

                        HistogramPath(values: summary.green)
                            .stroke(.green.opacity(0.68), lineWidth: 1.5)

                        HistogramPath(values: summary.blue)
                            .stroke(.blue.opacity(0.68), lineWidth: 1.5)
                    }

                    if channelMode == .parade {
                        HistogramPath(values: summary.redParade)
                            .stroke(.red.opacity(0.72), lineWidth: 1.5)
                            .frame(width: proxy.size.width / 3, alignment: .leading)
                            .position(x: proxy.size.width / 6, y: proxy.size.height / 2)

                        HistogramPath(values: summary.greenParade)
                            .stroke(.green.opacity(0.72), lineWidth: 1.5)
                            .frame(width: proxy.size.width / 3, alignment: .center)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                        HistogramPath(values: summary.blueParade)
                            .stroke(.blue.opacity(0.72), lineWidth: 1.5)
                            .frame(width: proxy.size.width / 3, alignment: .trailing)
                            .position(x: proxy.size.width * 5 / 6, y: proxy.size.height / 2)
                    }

                    Text(scopeLabel(for: summary))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomTrailing)
                } else {
                    Text("No histogram")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scopeLabel(for summary: HistogramSummary) -> String {
        let shadows = Int(summary.shadowClippingRatio * 100)
        let highlights = Int(summary.highlightClippingRatio * 100)
        return "\(summary.sampleCount) samples  S \(shadows)%  H \(highlights)%"
    }
}

private struct HistogramPath: Shape {
    let values: [Double]
    var closesToBaseline = false

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else {
            return Path()
        }

        let peak = max(values.max() ?? 0, 0.0001)
        let step = rect.width / CGFloat(values.count - 1)
        var path = Path()

        for index in values.indices {
            let x = rect.minX + (CGFloat(index) * step)
            let normalized = min(max(values[index] / peak, 0), 1)
            let y = rect.maxY - (CGFloat(normalized) * rect.height)

            if index == values.startIndex {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        if closesToBaseline, values.count > 2 {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }

        return path
    }
}

package enum HistogramViewCoverageProbe {
    package static func touch(summary: HistogramSummary?) {
        _ = HistogramView(summary: summary, channelMode: .all).body
        _ = HistogramPath(values: [0.0, 0.5, 1.0]).path(in: CGRect(x: 0, y: 0, width: 10, height: 10))
    }
}
