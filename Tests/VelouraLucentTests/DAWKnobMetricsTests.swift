import Foundation
import Testing
@testable import VelouraLucent

struct DAWKnobMetricsTests {
    @Test
    func sourceSizeUsesCurrentSquareMaterials() {
        #expect(DAWKnobMetrics.sourceSize.width == 1024)
        #expect(DAWKnobMetrics.sourceSize.height == 1024)
    }

    @Test
    func artworkUsesFullImageScaleWithoutCroppingBasis() {
        #expect(DAWKnobMetrics.artworkSize == 226)
        #expect(DAWKnobMetrics.controlWidth == 118)
        #expect(DAWKnobMetrics.controlHeight == 181)
        #expect(DAWKnobMetrics.knobSourceDiameter == 342)
        #expect(abs(DAWKnobMetrics.knobHitDiameter - 75.48046875) < 0.000001)
        #expect(DAWKnobMetrics.knobHitRect.midX == DAWKnobMetrics.scaledPoint(DAWKnobMetrics.knobCenter).x)
        #expect(DAWKnobMetrics.knobHitRect.midY == DAWKnobMetrics.scaledPoint(DAWKnobMetrics.knobCenter).y)
        #expect(DAWKnobMetrics.knobHitRect.width == DAWKnobMetrics.knobHitDiameter)
        #expect(DAWKnobMetrics.knobHitRect.height == DAWKnobMetrics.knobHitDiameter)
        #expect(abs(DAWKnobMetrics.stepButtonHitSize.width - 29.904296875) < 0.000001)
        #expect(abs(DAWKnobMetrics.stepButtonHitSize.height - 30.345703125) < 0.000001)
        #expect(DAWKnobMetrics.columnSpacing == 7)
        #expect(DAWKnobMetrics.rowSpacing == 8)
        #expect(abs(DAWKnobMetrics.artworkScale - (226.0 / 1024.0)) < 0.000001)
        #expect(abs(DAWKnobMetrics.artworkOrigin.x - -54.0) < 0.000001)
        #expect(DAWKnobMetrics.artworkOrigin.y == -22)
    }

    @Test
    func rotaryKnobResourcesAreBundled() {
        #expect(DAWKnobMetrics.resourceURL(named: "2") != nil)
        #expect(DAWKnobMetrics.resourceURL(named: "3") != nil)
        #expect(DAWKnobMetrics.rotatingArtworkImage != nil)
        #expect(DAWKnobMetrics.fixedArtworkImage != nil)
    }

    @Test
    func rotationAnchorUsesMeasuredKnobCenter() {
        #expect(abs(DAWKnobMetrics.knobCenter.x - 510.03954) < 0.000001)
        #expect(abs(DAWKnobMetrics.knobCenter.y - 544.94518) < 0.000001)
        #expect(abs(DAWKnobMetrics.rotationAnchor.x - 0.498085488281) < 0.000001)
        #expect(abs(DAWKnobMetrics.rotationAnchor.y - 0.532173027344) < 0.000001)
    }

    @Test
    func displayAngleIncludesMeasuredBlueDotOffset() {
        #expect(abs(DAWKnobMetrics.rotationOffsetDegrees - -41.892183586331) < 0.000001)
        #expect(abs(DAWKnobMetrics.displayAngleDegrees(value: 0, range: 0 ... 1) - -176.892183586331) < 0.000001)
        #expect(abs(DAWKnobMetrics.displayAngleDegrees(value: 0.5, range: 0 ... 1) - -41.892183586331) < 0.000001)
        #expect(abs(DAWKnobMetrics.displayAngleDegrees(value: 1, range: 0 ... 1) - 93.107816413669) < 0.000001)
    }

    @Test
    func smallValueChangeProducesSmallAngleChange() {
        let first = DAWKnobMetrics.displayAngleDegrees(value: 0.50, range: 0 ... 1)
        let second = DAWKnobMetrics.displayAngleDegrees(value: 0.51, range: 0 ... 1)

        #expect(abs((second - first) - 2.7) < 0.00001)
    }

    @Test
    func dragUpIncreasesValueAndDragDownDecreasesValue() {
        #expect(DAWKnobMetrics.dragValueDelta(forTranslationHeight: -150) == 1)
        #expect(DAWKnobMetrics.dragValueDelta(forTranslationHeight: 150) == -1)
    }

    @Test
    func wideRangeMasteringKnobsUseExplicitDragScales() {
        #expect(DAWKnobMetrics.targetLoudnessDragValueScale == 9)
        #expect(DAWKnobMetrics.deEsserThresholdDragValueScale == 18)
        #expect(DAWKnobMetrics.compressorThresholdDragValueScale == 24)
        #expect(
            DAWKnobMetrics.dragValueDelta(
                forTranslationHeight: -150,
                valueScale: DAWKnobMetrics.targetLoudnessDragValueScale
            ) == 9
        )
        #expect(
            DAWKnobMetrics.dragValueDelta(
                forTranslationHeight: -150,
                valueScale: DAWKnobMetrics.deEsserThresholdDragValueScale
            ) == 18
        )
        #expect(
            DAWKnobMetrics.dragValueDelta(
                forTranslationHeight: -150,
                valueScale: DAWKnobMetrics.compressorThresholdDragValueScale
            ) == 24
        )
        #expect(DAWKnobMetrics.dragValueDelta(forTranslationHeight: -150) == 1)
    }

    @Test
    func longMasteringUnitsUseWiderTextFrameThanPercent() {
        #expect(DAWKnobMetrics.unitTextWidth(for: "%") == DAWKnobMetrics.defaultUnitTextWidth)
        #expect(DAWKnobMetrics.unitTextWidth(for: nil) == DAWKnobMetrics.defaultUnitTextWidth)
        #expect(DAWKnobMetrics.unitTextWidth(for: "LUFS") == DAWKnobMetrics.wideUnitTextWidth)
        #expect(DAWKnobMetrics.unitTextWidth(for: "dB") == DAWKnobMetrics.wideUnitTextWidth)
        #expect(DAWKnobMetrics.wideUnitTextWidth > DAWKnobMetrics.defaultUnitTextWidth)
    }

    @Test
    func valuesAreClampedToRange() {
        #expect(DAWKnobMetrics.clamped(-0.1, to: 0 ... 1) == 0)
        #expect(DAWKnobMetrics.clamped(1.1, to: 0 ... 1) == 1)
        #expect(DAWKnobMetrics.clamped(0.25, to: 0 ... 1) == 0.25)
    }

    @Test
    func overlayCoordinatesUseSameSourceScaleAsArtwork() {
        let valueCenter = DAWKnobMetrics.scaledPoint(DAWKnobMetrics.valueCenter)
        let minusCenter = DAWKnobMetrics.scaledPoint(DAWKnobMetrics.minusButtonCenter)
        let plusCenter = DAWKnobMetrics.scaledPoint(DAWKnobMetrics.plusButtonCenter)
        let unitCenter = DAWKnobMetrics.scaledPoint(DAWKnobMetrics.unitCenter)

        #expect(abs(valueCenter.x - 57.5654296875) < 0.000001)
        #expect(abs(valueCenter.y - 31.630859375) < 0.000001)
        #expect(abs(minusCenter.x - 21.701171875) < 0.000001)
        #expect(abs(minusCenter.y - 141.982421875) < 0.000001)
        #expect(abs(plusCenter.x - 94.75390625) < 0.000001)
        #expect(abs(plusCenter.y - 141.982421875) < 0.000001)
        #expect(abs(unitCenter.x - 58.2275390625) < 0.000001)
        #expect(abs(unitCenter.y - 141.982421875) < 0.000001)
        #expect(unitCenter.x == (minusCenter.x + plusCenter.x) / 2)
    }

    @Test
    func stepButtonHitAreaAddsEightPointsOutsideScaledArtwork() {
        let visibleSize = DAWKnobMetrics.scaledSize(DAWKnobMetrics.stepButtonSize)

        #expect(DAWKnobMetrics.stepButtonHitSize.width - visibleSize.width == 16)
        #expect(DAWKnobMetrics.stepButtonHitSize.height - visibleSize.height == 16)
    }

    @Test
    func labelsAndTitleMoveBelowScaleDotsAndButtons() {
        let topLabel = DAWKnobMetrics.scaledPoint(DAWKnobMetrics.topLabelCenter)
        let leftLabel = DAWKnobMetrics.scaledPoint(DAWKnobMetrics.leftLabelCenter)
        let rightLabel = DAWKnobMetrics.scaledPoint(DAWKnobMetrics.rightLabelCenter)
        let title = DAWKnobMetrics.scaledPoint(DAWKnobMetrics.titleCenter)
        let minusCenter = DAWKnobMetrics.scaledPoint(DAWKnobMetrics.minusButtonCenter)

        #expect(abs(topLabel.y - 55.24609375) < 0.000001)
        #expect(abs(leftLabel.y - 130.28515625) < 0.000001)
        #expect(abs(rightLabel.y - 130.28515625) < 0.000001)
        #expect(abs(title.y - 163.83203125) < 0.000001)
        #expect(title.y > minusCenter.y)
    }

    @Test
    func threeKnobRowFitsWithoutScalingInOriginalMaximumInspectorWidth() {
        #expect(DAWKnobMetrics.threeColumnWidth == 368)
        #expect(DAWKnobMetrics.twoColumnWidth == 243)
        #expect(DAWKnobMetrics.fourColumnWidth == 493)
        #expect(DAWKnobMetrics.fiveColumnWidth == 618)

        let originalMaximumPanelContentWidth: CGFloat = 440 - 28 - 24

        #expect(DAWKnobMetrics.threeColumnWidth <= originalMaximumPanelContentWidth)
        #expect(DAWKnobMetrics.controlWidth >= 118)
    }

    @Test
    func fiveRepairKnobsRequireThreePlusTwoRowsInInspectorWidth() {
        let originalMaximumPanelContentWidth: CGFloat = 440 - 28 - 24

        #expect(DAWKnobMetrics.fiveColumnWidth > originalMaximumPanelContentWidth)
        #expect(DAWKnobMetrics.threeColumnWidth <= originalMaximumPanelContentWidth)
        #expect(DAWKnobMetrics.twoColumnWidth < DAWKnobMetrics.threeColumnWidth)
    }

    @Test
    func fourAdvancedKnobsRequireTwoPlusTwoRowsInInspectorWidth() {
        let originalMaximumPanelContentWidth: CGFloat = 440 - 28 - 24

        #expect(DAWKnobMetrics.fourColumnWidth > originalMaximumPanelContentWidth)
        #expect(DAWKnobMetrics.twoColumnWidth <= originalMaximumPanelContentWidth)
    }
}
