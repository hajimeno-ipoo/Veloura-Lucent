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
    static let buttonHitExpansion: CGFloat = 8
    static let stepAnimationDuration: Double = 0.12
    static let defaultUnitTextWidth: CGFloat = 50
    static let wideUnitTextWidth: CGFloat = 190
    static let valueTextWidth: CGFloat = 206
    static let targetLoudnessDragValueScale: Float = 9
    static let deEsserThresholdDragValueScale: Float = 18
    static let compressorThresholdDragValueScale: Float = 24
    static let knobCenter = CGPoint(x: 510.03954, y: 544.94518)
    static let knobSourceDiameter: CGFloat = 342
    static let blueDotCenter = CGPoint(x: 596.3423423423424, y: 448.73273273273276)
    static let rotationAnchor = UnitPoint(x: knobCenter.x / sourceSize.width, y: knobCenter.y / sourceSize.height)
    static let rotationOffsetDegrees = -41.892183586331

    static let valueCenter = CGPoint(x: 505.5, y: 243)
    static let topLabelCenter = CGPoint(x: 510, y: 350)
    static let leftLabelCenter = CGPoint(x: 300, y: 690)
    static let rightLabelCenter = CGPoint(x: 720, y: 690)
    static let titleCenter = CGPoint(x: 510, y: 842)
    static let minusButtonCenter = CGPoint(x: 343, y: 743)
    static let plusButtonCenter = CGPoint(x: 674, y: 743)
    static let unitCenter = CGPoint(x: 508.5, y: 743)
    static let stepButtonSize = CGSize(width: 63, height: 65)

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
        let center = scaledPoint(knobCenter)
        let radius = knobHitDiameter / 2
        return CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: knobHitDiameter,
            height: knobHitDiameter
        )
    }

    static var stepButtonHitSize: CGSize {
        let visibleSize = scaledSize(stepButtonSize)
        return CGSize(
            width: visibleSize.width + buttonHitExpansion * 2,
            height: visibleSize.height + buttonHitExpansion * 2
        )
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

    static let fixedArtworkImage = loadImage(named: "3")
    static let rotatingArtworkImage = loadImage(named: "2")

    static func resourceURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "png")
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

    static func scaledSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width * artworkScale, height: size.height * artworkScale)
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

    static func unitTextWidth(for unitText: String?) -> CGFloat {
        switch unitText {
        case "LUFS", "dB":
            wideUnitTextWidth
        default:
            defaultUnitTextWidth
        }
    }

    static func dragValueDelta(forTranslationHeight height: CGFloat, valueScale: Float = 1) -> Float {
        Float(-height / dragSensitivity) * valueScale
    }

    static func clamped(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
