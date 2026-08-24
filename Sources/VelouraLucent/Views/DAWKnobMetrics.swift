import SwiftUI
import AppKit

enum DAWKnobMetrics {
    static let sourceSize = CGSize(width: 1024, height: 1024)
    static let artworkSize: CGFloat = 226
    static let controlWidth: CGFloat = 118
    static let controlHeight: CGFloat = 181
    static let columnSpacing: CGFloat = 7
    static let rowSpacing: CGFloat = 8
    static let artworkVerticalOffset: CGFloat = -22
    static let dragSensitivity: CGFloat = 150
    static let stepAnimationDuration: Double = 0.12
    static let valueTextWidth: CGFloat = 108
    static let valueUnitSpacing: CGFloat = 4
    static let targetLoudnessDragValueScale: Float = 9
    static let deEsserThresholdDragValueScale: Float = 18
    static let compressorThresholdDragValueScale: Float = 24
    static let knobCenter = CGPoint(x: 510.03954, y: 544.94518)
    static let knobSourceDiameter: CGFloat = 342
    static let blueDotCenter = CGPoint(x: 596.3423423423424, y: 448.73273273273276)
    static let rotationAnchor = UnitPoint(x: knobCenter.x / sourceSize.width, y: knobCenter.y / sourceSize.height)
    static let rotationOffsetDegrees = -41.892183586331

    static let valueCenter = CGPoint(x: 59, y: 20)
    static let topLabelCenter = CGPoint(x: 59, y: 40)
    static let leftLabelCenter = CGPoint(x: 21, y: 140)
    static let rightLabelCenter = CGPoint(x: 97, y: 140)
    static let titleCenter = CGPoint(x: 59, y: 165)
    static let decrementRailCenter = CGPoint(x: 7, y: 102)
    static let incrementRailCenter = CGPoint(x: 111, y: 102)
    static let stepRailHitSize = CGSize(width: 18, height: 70)
    static let stepRailVisibleSize = CGSize(width: 8, height: 58)
    static let ringDiameter: CGFloat = 98
    static let ringTickCount = 37
    static let ringStartAngleDegrees = 135.0
    static let ringSweepAngleDegrees = 270.0

    static var artworkScale: CGFloat {
        artworkSize / sourceSize.width
    }

    static var artworkOrigin: CGPoint {
        CGPoint(x: (controlWidth - artworkSize) / 2, y: artworkVerticalOffset)
    }

    static var knobHitDiameter: CGFloat {
        knobSourceDiameter * artworkScale
    }

    static var knobHitRect: CGRect {
        let center = knobDisplayCenter
        let radius = knobHitDiameter / 2
        return CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: knobHitDiameter,
            height: knobHitDiameter
        )
    }

    static var knobDisplayCenter: CGPoint {
        scaledPoint(knobCenter)
    }

    static var threeColumnWidth: CGFloat {
        controlWidth * 3 + columnSpacing * 2
    }

    static var fourColumnWidth: CGFloat {
        controlWidth * 4 + columnSpacing * 3
    }

    static var fiveColumnWidth: CGFloat {
        controlWidth * 5 + columnSpacing * 4
    }

    static var twoColumnWidth: CGFloat {
        controlWidth * 2 + columnSpacing
    }

    static let rotatingArtworkImage = loadImage(named: "2")

    static func resourceURL(named name: String) -> URL? {
        AppResourceBundle.url(forResource: name, withExtension: "png")
    }

    private static func loadImage(named name: String) -> NSImage? {
        guard let url = resourceURL(named: name) else { return nil }
        return NSImage(contentsOf: url)
    }

    static func scaledPoint(sourceX: CGFloat, sourceY: CGFloat) -> CGPoint {
        CGPoint(
            x: artworkOrigin.x + sourceX * artworkScale,
            y: artworkOrigin.y + sourceY * artworkScale
        )
    }

    static func scaledPoint(_ point: CGPoint) -> CGPoint {
        scaledPoint(sourceX: point.x, sourceY: point.y)
    }

    static func normalizedValue(_ value: Float, in range: ClosedRange<Float>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span != 0 else { return 0 }
        let clampedValue = clamped(value, to: range)
        return Double((clampedValue - range.lowerBound) / span)
    }

    static func baseAngleDegrees(value: Float, range: ClosedRange<Float>) -> Double {
        -135.0 + normalizedValue(value, in: range) * 270.0
    }

    static func displayAngleDegrees(value: Float, range: ClosedRange<Float>) -> Double {
        baseAngleDegrees(value: value, range: range) + rotationOffsetDegrees
    }

    static func ringTickProgress(at index: Int) -> Double {
        guard ringTickCount > 1 else { return 0 }
        let clampedIndex = min(max(index, 0), ringTickCount - 1)
        return Double(clampedIndex) / Double(ringTickCount - 1)
    }

    static func ringTickAngleDegrees(at index: Int) -> Double {
        ringStartAngleDegrees + ringTickProgress(at: index) * ringSweepAngleDegrees
    }

    static func ringTickIsActive(at index: Int, value: Float, range: ClosedRange<Float>) -> Bool {
        ringTickProgress(at: index) <= normalizedValue(value, in: range)
    }

    static func dragValueDelta(forTranslationHeight height: CGFloat, valueScale: Float = 1) -> Float {
        Float(-height / dragSensitivity) * valueScale
    }

    static func clamped(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct DAWResponsiveThreeControlLayout: Layout {
    enum Arrangement: Equatable {
        case threeColumns
        case twoColumns
        case oneColumn
    }

    static func arrangement(for availableWidth: CGFloat?) -> Arrangement {
        guard let availableWidth else { return .threeColumns }
        if availableWidth >= DAWKnobMetrics.threeColumnWidth {
            return .threeColumns
        }
        if availableWidth >= DAWKnobMetrics.twoColumnWidth {
            return .twoColumns
        }
        return .oneColumn
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = measuredSizes(for: subviews)
        guard !sizes.isEmpty else { return .zero }

        switch Self.arrangement(for: proposal.width) {
        case .threeColumns:
            return CGSize(
                width: rowWidth(for: min(3, sizes.count)),
                height: sizes.map(\.height).max() ?? 0
            )
        case .twoColumns:
            let firstRow = Array(sizes.prefix(2))
            let firstRowHeight = firstRow.map(\.height).max() ?? 0
            let remainingHeight = sizes.dropFirst(2).reduce(CGFloat.zero) { partial, size in
                partial + DAWKnobMetrics.rowSpacing + size.height
            }
            return CGSize(
                width: rowWidth(for: min(2, sizes.count)),
                height: firstRowHeight + remainingHeight
            )
        case .oneColumn:
            return CGSize(
                width: sizes.map(\.width).max() ?? 0,
                height: stackedHeight(for: sizes)
            )
        }
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = measuredSizes(for: subviews)
        guard !sizes.isEmpty else { return }

        switch Self.arrangement(for: proposal.width) {
        case .threeColumns:
            placeRow(
                subviews: subviews,
                sizes: sizes,
                indexes: Array(sizes.indices.prefix(3)),
                origin: bounds.origin
            )
        case .twoColumns:
            let firstRowIndexes = Array(sizes.indices.prefix(2))
            placeRow(
                subviews: subviews,
                sizes: sizes,
                indexes: firstRowIndexes,
                origin: bounds.origin
            )

            var y = bounds.minY
                + (firstRowIndexes.map { sizes[$0].height }.max() ?? 0)
                + DAWKnobMetrics.rowSpacing
            for index in sizes.indices.dropFirst(2) {
                let x = bounds.midX - sizes[index].width / 2
                place(
                    subviews[index],
                    size: sizes[index],
                    at: CGPoint(x: x, y: y)
                )
                y += sizes[index].height + DAWKnobMetrics.rowSpacing
            }
        case .oneColumn:
            var y = bounds.minY
            for index in sizes.indices {
                let x = bounds.midX - sizes[index].width / 2
                place(
                    subviews[index],
                    size: sizes[index],
                    at: CGPoint(x: x, y: y)
                )
                y += sizes[index].height + DAWKnobMetrics.rowSpacing
            }
        }
    }

    private func measuredSizes(for subviews: Subviews) -> [CGSize] {
        subviews.map {
            $0.sizeThatFits(
                ProposedViewSize(
                    width: DAWKnobMetrics.controlWidth,
                    height: nil
                )
            )
        }
    }

    private func rowWidth(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return DAWKnobMetrics.controlWidth * CGFloat(count)
            + DAWKnobMetrics.columnSpacing * CGFloat(count - 1)
    }

    private func stackedHeight(for sizes: [CGSize]) -> CGFloat {
        guard !sizes.isEmpty else { return 0 }
        return sizes.map(\.height).reduce(0, +)
            + DAWKnobMetrics.rowSpacing * CGFloat(sizes.count - 1)
    }

    private func placeRow(
        subviews: Subviews,
        sizes: [CGSize],
        indexes: [Int],
        origin: CGPoint
    ) {
        var x = origin.x
        for index in indexes {
            place(
                subviews[index],
                size: sizes[index],
                at: CGPoint(x: x, y: origin.y)
            )
            x += sizes[index].width + DAWKnobMetrics.columnSpacing
        }
    }

    private func place(_ subview: LayoutSubview, size: CGSize, at point: CGPoint) {
        subview.place(
            at: point,
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
        )
    }
}
