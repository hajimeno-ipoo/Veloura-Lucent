import Testing
@testable import VelouraLucent

@MainActor
struct WaveformTrackResizeHandleTests {
    @Test
    func defaultHeightIsLargerThanThePreviousCompactHeight() {
        #expect(
            WaveformTrackResizeHandle.defaultHeight
                > WaveformTrackResizeHandle.minimumHeight
        )
        #expect(WaveformTrackResizeHandle.defaultHeight == 96)
    }

    @Test
    func heightIsClampedToTheApprovedContinuousRange() {
        #expect(
            WaveformTrackResizeHandle.clampedHeight(40)
                == WaveformTrackResizeHandle.minimumHeight
        )
        #expect(WaveformTrackResizeHandle.clampedHeight(120) == 120)
        #expect(
            WaveformTrackResizeHandle.clampedHeight(240)
                == WaveformTrackResizeHandle.maximumHeight
        )
    }

    @Test
    func dragTranslationChangesHeightContinuously() {
        #expect(
            WaveformTrackResizeHandle.resizedHeight(
                from: 96,
                verticalTranslation: 0.5
            ) == 96.5
        )
        #expect(
            WaveformTrackResizeHandle.resizedHeight(
                from: 96,
                verticalTranslation: 17.25
            ) == 113.25
        )
        #expect(
            WaveformTrackResizeHandle.resizedHeight(
                from: 96,
                verticalTranslation: -12.75
            ) == 83.25
        )
    }

    @Test
    func dragTranslationStillRespectsTheApprovedRange() {
        #expect(
            WaveformTrackResizeHandle.resizedHeight(
                from: 96,
                verticalTranslation: -200
            ) == WaveformTrackResizeHandle.minimumHeight
        )
        #expect(
            WaveformTrackResizeHandle.resizedHeight(
                from: 96,
                verticalTranslation: 200
            ) == WaveformTrackResizeHandle.maximumHeight
        )
    }
}
