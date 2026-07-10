import Charts
import SwiftUI

struct GraphHoverValue: Identifiable {
    let label: String
    let value: String
    let color: Color

    var id: String { label }
}

struct GraphHoverReadout {
    let axisLabel: String
    let values: [GraphHoverValue]
}

extension View {
    func graphHoverOverlay(
        readout: @escaping (_ xValue: Double, _ yValue: Double) -> GraphHoverReadout?
    ) -> some View {
        modifier(GraphHoverOverlayModifier(readoutProvider: readout))
    }
}

private struct GraphHoverOverlayModifier: ViewModifier {
    let readoutProvider: (_ xValue: Double, _ yValue: Double) -> GraphHoverReadout?

    @State private var cursorX: CGFloat?
    @State private var readout: GraphHoverReadout?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let readout {
                    GraphHoverReadoutView(readout: readout)
                } else {
                    Color.clear
                }
            }
            .frame(height: 28, alignment: .leading)

            content.chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geometry[plotFrameAnchor]
                        hoverLayer(proxy: proxy)
                            .frame(width: plotFrame.width, height: plotFrame.height)
                            .position(x: plotFrame.midX, y: plotFrame.midY)
                    }
                }
            }
        }
    }

    private func hoverLayer(proxy: ChartProxy) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())

            if let cursorX {
                Rectangle()
                    .fill(Color.primary.opacity(0.36))
                    .frame(width: 1)
                    .offset(x: cursorX)
                    .allowsHitTesting(false)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard
                    let xValue: Double = proxy.value(atX: location.x),
                    let yValue: Double = proxy.value(atY: location.y),
                    let nextReadout = readoutProvider(xValue, yValue)
                else {
                    cursorX = nil
                    readout = nil
                    return
                }
                cursorX = location.x
                readout = nextReadout
            case .ended:
                cursorX = nil
                readout = nil
            }
        }
    }
}

private struct GraphHoverReadoutView: View {
    let readout: GraphHoverReadout

    var body: some View {
        HStack(spacing: 10) {
            Text(readout.axisLabel)
                .fontWeight(.semibold)

            ForEach(readout.values) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 6, height: 6)
                    Text("\(item.label) \(item.value)")
                }
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.clear, in: .capsule)
    }
}
