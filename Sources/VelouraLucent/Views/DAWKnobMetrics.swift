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
