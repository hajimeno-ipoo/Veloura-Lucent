import SwiftUI

struct VectorScopeView: View {
    let preview: AudioPreviewController

    private var activeTarget: AudioPreviewTarget? {
        preview.activeTarget
    }

    private var snapshot: VectorScopeSnapshot {
        guard let activeTarget else { return .unavailable }
        return preview.cardState(for: activeTarget).vectorScopeSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("ベクトルスコープ")
                    .font(.headline)
                TermHelpButton(
                    title: "ベクトルスコープ",
                    reading: "べくとるすこーぷ",
                    description: "左右チャンネルの瞬間的な関係を点の軌跡で表示します。縦に近いほど同相、横に広がるほど逆相成分が多く、斜め方向は左右どちらかへ偏った状態を示します。"
                )
                Spacer()
                if let activeTarget {
                    Label(activeTarget.rawValue, systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(targetColor(activeTarget))
                }
            }

            Text("縦=同相 / 横=逆相 / 斜め=左右偏り。再生中の1音源だけを表示します。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {
                VectorScopePlot(
                    points: snapshot.points,
                    color: activeTarget.map(targetColor) ?? .secondary
                )

                if let message = statusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(24)
                }
            }
            .frame(width: 280, height: 240)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
        }
    }

    private var statusMessage: String? {
        switch snapshot.inputState {
        case .unavailable:
            return nil
        case .mono:
            return "モノラル音源のため、左右の関係は表示しません"
        case .stereo:
            return snapshot.points.isEmpty ? "音声信号を待っています" : nil
        case let .multichannel(channelCount):
            return "\(channelCount)チャンネル音源はベクトルスコープ未対応です"
        }
    }

    private var accessibilityDescription: String {
        guard activeTarget != nil else {
            return "ベクトルスコープ。停止中です"
        }
        if let statusMessage {
            return "ベクトルスコープ。\(statusMessage)"
        }
        let targetName = activeTarget?.rawValue ?? "音源"
        return "ベクトルスコープ。\(targetName)の左右チャンネルの軌跡を表示中です"
    }

    private func targetColor(_ target: AudioPreviewTarget) -> Color {
        switch target {
        case .input: .blue
        case .corrected: .green
        case .mastered: .orange
        }
    }
}

private struct VectorScopePlot: View {
    let points: [VectorScopePoint]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let sideLabelInset: CGFloat = 52
            let verticalLabelInset: CGFloat = 30
            let plotRect = CGRect(
                x: sideLabelInset,
                y: verticalLabelInset,
                width: max(0, size.width - sideLabelInset * 2),
                height: max(0, size.height - verticalLabelInset * 2)
            )
            let center = CGPoint(x: plotRect.midX, y: plotRect.midY)
            let radius = min(plotRect.width, plotRect.height) * 0.5

            var grid = Path()
            for fraction in stride(from: 0.25, through: 0.75, by: 0.25) {
                let x = plotRect.minX + plotRect.width * fraction
                grid.move(to: CGPoint(x: x, y: plotRect.minY))
                grid.addLine(to: CGPoint(x: x, y: plotRect.maxY))

                let y = plotRect.minY + plotRect.height * fraction
                grid.move(to: CGPoint(x: plotRect.minX, y: y))
                grid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.08)), lineWidth: 1)

            for scale in [0.5, 0.75] {
                let ringRadius = radius * scale
                var ring = Path()
                ring.addEllipse(in: CGRect(
                    x: center.x - ringRadius,
                    y: center.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                ))
                context.stroke(ring, with: .color(.secondary.opacity(0.12)), lineWidth: 1)
            }

            var boundary = Path()
            boundary.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.stroke(boundary, with: .color(.secondary.opacity(0.35)), lineWidth: 1)

            var axes = Path()
            axes.move(to: CGPoint(x: center.x, y: center.y - radius))
            axes.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            axes.move(to: CGPoint(x: center.x - radius, y: center.y))
            axes.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            axes.move(to: CGPoint(x: center.x - radius * 0.71, y: center.y + radius * 0.71))
            axes.addLine(to: CGPoint(x: center.x + radius * 0.71, y: center.y - radius * 0.71))
            axes.move(to: CGPoint(x: center.x - radius * 0.71, y: center.y - radius * 0.71))
            axes.addLine(to: CGPoint(x: center.x + radius * 0.71, y: center.y + radius * 0.71))
            context.stroke(axes, with: .color(.secondary.opacity(0.24)), lineWidth: 1)

            var centerPoint = Path()
            centerPoint.addEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
            context.fill(centerPoint, with: .color(.secondary.opacity(0.5)))

            for point in points {
                let position = CGPoint(
                    x: center.x + CGFloat(point.x) * radius,
                    y: center.y - CGFloat(point.y) * radius
                )
                let dot = Path(ellipseIn: CGRect(x: position.x - 1.2, y: position.y - 1.2, width: 2.4, height: 2.4))
                context.fill(dot, with: .color(color.opacity(0.58)))
            }

            context.draw(Text("同相").font(.caption2.bold()).foregroundStyle(.secondary), at: CGPoint(x: center.x, y: center.y - radius - 10), anchor: .bottom)
            context.draw(Text("逆相成分").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: center.x - radius - 8, y: center.y), anchor: .trailing)
            context.draw(Text("逆相成分").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: center.x + radius + 8, y: center.y), anchor: .leading)
            context.draw(Text("L").font(.caption2.bold()).foregroundStyle(.secondary), at: CGPoint(x: center.x - radius * 0.78 - 8, y: center.y + radius * 0.78 + 8), anchor: .topTrailing)
            context.draw(Text("R").font(.caption2.bold()).foregroundStyle(.secondary), at: CGPoint(x: center.x + radius * 0.78 + 8, y: center.y + radius * 0.78 + 8), anchor: .topLeading)
        }
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
    }
}
