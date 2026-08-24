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
        #expect(DAWKnobMetrics.stepRailHitSize == CGSize(width: 18, height: 70))
        #expect(DAWKnobMetrics.stepRailVisibleSize == CGSize(width: 8, height: 58))
        #expect(DAWKnobMetrics.columnSpacing == 7)
        #expect(DAWKnobMetrics.rowSpacing == 8)
        #expect(abs(DAWKnobMetrics.artworkScale - (226.0 / 1024.0)) < 0.000001)
        #expect(abs(DAWKnobMetrics.artworkOrigin.x - -54.0) < 0.000001)
        #expect(DAWKnobMetrics.artworkOrigin.y == -22)
    }

    @Test
    func rotaryKnobResourcesAreBundled() {
        #expect(DAWKnobMetrics.resourceURL(named: "2") != nil)
        #expect(DAWKnobMetrics.rotatingArtworkImage != nil)
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
    func ringTicksCoverTheSameRotaryRangeAsTheKnob() {
        #expect(DAWKnobMetrics.ringTickCount == 37)
        #expect(DAWKnobMetrics.ringTickAngleDegrees(at: 0) == 135)
        #expect(DAWKnobMetrics.ringTickAngleDegrees(at: 18) == 270)
        #expect(DAWKnobMetrics.ringTickAngleDegrees(at: 36) == 405)
        #expect(DAWKnobMetrics.ringTickIsActive(at: 0, value: 0, range: 0 ... 1))
        #expect(!DAWKnobMetrics.ringTickIsActive(at: 1, value: 0, range: 0 ... 1))
        #expect(DAWKnobMetrics.ringTickIsActive(at: 18, value: 0.5, range: 0 ... 1))
        #expect(!DAWKnobMetrics.ringTickIsActive(at: 19, value: 0.5, range: 0 ... 1))
        #expect(DAWKnobMetrics.ringTickIsActive(at: 36, value: 1, range: 0 ... 1))
    }

    @Test
    func valuesAreClampedToRange() {
        #expect(DAWKnobMetrics.clamped(-0.1, to: 0 ... 1) == 0)
        #expect(DAWKnobMetrics.clamped(1.1, to: 0 ... 1) == 1)
        #expect(DAWKnobMetrics.clamped(0.25, to: 0 ... 1) == 0.25)
    }

    @Test
    func overlayAndRailCoordinatesMatchTheSelectedCompactLayout() {
        #expect(DAWKnobMetrics.valueCenter == CGPoint(x: 59, y: 20))
        #expect(DAWKnobMetrics.valueUnitSpacing == 4)
        #expect(DAWKnobMetrics.topLabelCenter == CGPoint(x: 59, y: 40))
        #expect(DAWKnobMetrics.decrementRailCenter == CGPoint(x: 7, y: 102))
        #expect(DAWKnobMetrics.incrementRailCenter == CGPoint(x: 111, y: 102))
        #expect(DAWKnobMetrics.decrementRailCenter.x + DAWKnobMetrics.incrementRailCenter.x == 118)
        #expect(DAWKnobMetrics.titleCenter.y > DAWKnobMetrics.leftLabelCenter.y)
    }

    @Test
    func stepRailHitAreaIsWiderAndTallerThanItsVisibleLine() {
        #expect(DAWKnobMetrics.stepRailHitSize.width > DAWKnobMetrics.stepRailVisibleSize.width)
        #expect(DAWKnobMetrics.stepRailHitSize.height > DAWKnobMetrics.stepRailVisibleSize.height)
    }

    @Test
    func labelsAndTitleRemainOutsideTheKnobRing() {
        let ringTop = DAWKnobMetrics.knobDisplayCenter.y - DAWKnobMetrics.ringDiameter / 2

        #expect(ringTop - DAWKnobMetrics.topLabelCenter.y >= 8)
        #expect(DAWKnobMetrics.leftLabelCenter.y > DAWKnobMetrics.knobDisplayCenter.y)
        #expect(DAWKnobMetrics.rightLabelCenter.y > DAWKnobMetrics.knobDisplayCenter.y)
        #expect(DAWKnobMetrics.titleCenter.y > DAWKnobMetrics.decrementRailCenter.y)
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
    func responsiveThreeControlLayoutKeepsTheExistingColumnBreakpoints() {
        #expect(
            DAWResponsiveThreeControlLayout.arrangement(
                for: DAWKnobMetrics.threeColumnWidth
            ) == .threeColumns
        )
        #expect(
            DAWResponsiveThreeControlLayout.arrangement(
                for: DAWKnobMetrics.threeColumnWidth - 1
            ) == .twoColumns
        )
        #expect(
            DAWResponsiveThreeControlLayout.arrangement(
                for: DAWKnobMetrics.twoColumnWidth
            ) == .twoColumns
        )
        #expect(
            DAWResponsiveThreeControlLayout.arrangement(
                for: DAWKnobMetrics.twoColumnWidth - 1
            ) == .oneColumn
        )
        #expect(
            DAWResponsiveThreeControlLayout.arrangement(for: nil)
                == .threeColumns
        )
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
