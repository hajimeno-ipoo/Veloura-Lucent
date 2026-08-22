import Testing
@testable import VelouraLucent

struct WaveformViewportTests {
    @Test
    func continuousZoomCentersVisibleRangeAndZoomsBackOut() {
        var viewport = WaveformViewport()
        let maximumZoomScale = 16.0

        viewport.setZoomPosition(
            0.5,
            maximumZoomScale: maximumZoomScale,
            centeredAt: 0.5
        )
        #expect(abs(viewport.zoomScale - 4) < 0.000_001)
        #expect(abs(viewport.startProgress - 0.375) < 0.000_001)
        #expect(abs(viewport.endProgress - 0.625) < 0.000_001)

        viewport.zoomIn(
            maximumZoomScale: maximumZoomScale,
            centeredAt: 0.5
        )
        let zoomedInScale = viewport.zoomScale
        #expect(zoomedInScale > 4)

        viewport.zoomOut(
            maximumZoomScale: maximumZoomScale,
            centeredAt: 0.5
        )
        #expect(abs(viewport.zoomScale - 4) < 0.000_001)
        #expect(viewport.zoomScale < zoomedInScale)
        #expect(viewport.canZoomOut)
    }

    @Test
    func zoomCentersOnPlayheadAndClampsAtWaveformEnds() {
        var viewport = WaveformViewport()
        let maximumZoomScale = 16.0

        viewport.setZoomPosition(
            0.5,
            maximumZoomScale: maximumZoomScale,
            centeredAt: 0
        )
        #expect(abs(viewport.startProgress - 0) < 0.000_001)
        #expect(abs(viewport.endProgress - 0.25) < 0.000_001)

        viewport.setZoomPosition(
            0.5,
            maximumZoomScale: maximumZoomScale,
            centeredAt: 0.5
        )
        #expect(abs(viewport.startProgress - 0.375) < 0.000_001)
        #expect(abs(viewport.endProgress - 0.625) < 0.000_001)

        viewport.setZoomPosition(
            0.5,
            maximumZoomScale: maximumZoomScale,
            centeredAt: 1
        )
        #expect(abs(viewport.startProgress - 0.75) < 0.000_001)
        #expect(abs(viewport.endProgress - 1) < 0.000_001)
    }

    @Test
    func localAndGlobalProgressConvertWithinVisibleRange() {
        var viewport = WaveformViewport()
        viewport.setZoomPosition(
            0.25,
            maximumZoomScale: 16,
            centeredAt: 0.5
        )

        #expect(abs(viewport.globalProgress(forLocalProgress: 0) - 0.25) < 0.000_001)
        #expect(abs(viewport.globalProgress(forLocalProgress: 0.5) - 0.5) < 0.000_001)
        #expect(abs(viewport.globalProgress(forLocalProgress: 1) - 0.75) < 0.000_001)
        #expect(abs(viewport.localProgress(forGlobalProgress: 0.625) - 0.75) < 0.000_001)
    }

    @Test
    func playbackContinuouslyCentersTheVisibleRange() {
        var viewport = WaveformViewport()
        viewport.setZoomPosition(
            0.5,
            maximumZoomScale: 16,
            centeredAt: 0.5
        )

        #expect(abs(viewport.startProgress - 0.375) < 0.000_001)
        viewport.followPlayback(0.625)

        #expect(abs(viewport.startProgress - 0.5) < 0.000_001)
        #expect(abs(viewport.endProgress - 0.75) < 0.000_001)

        viewport.followPlayback(0.626)
        #expect(abs(viewport.startProgress - 0.501) < 0.000_001)
    }

    @Test
    func waveformPanMovesTheVisibleRangeAndClampsAtBothEnds() {
        var viewport = WaveformViewport()
        viewport.setZoomPosition(
            0.5,
            maximumZoomScale: 16,
            centeredAt: 0.5
        )
        let initialStart = viewport.startProgress

        viewport.pan(
            from: initialStart,
            horizontalTranslationFraction: -0.5
        )
        #expect(abs(viewport.startProgress - 0.5) < 0.000_001)

        viewport.pan(
            from: initialStart,
            horizontalTranslationFraction: 0.25
        )
        #expect(abs(viewport.startProgress - 0.3125) < 0.000_001)

        viewport.pan(
            from: initialStart,
            horizontalTranslationFraction: 10
        )
        #expect(viewport.startProgress == 0)

        viewport.pan(
            from: initialStart,
            horizontalTranslationFraction: -10
        )
        #expect(abs(viewport.startProgress - 0.75) < 0.000_001)
    }

    @Test
    func fullWaveformDoesNotPan() {
        var viewport = WaveformViewport()

        viewport.pan(
            from: 0,
            horizontalTranslationFraction: -0.5
        )

        #expect(viewport.startProgress == 0)
        #expect(viewport.endProgress == 1)
    }

    @Test
    func keyboardStylePanMovesByTenPercentOfVisibleRangeAndClamps() {
        var viewport = WaveformViewport()
        viewport.setZoomPosition(
            0.5,
            maximumZoomScale: 16,
            centeredAt: 0.5
        )

        viewport.moveVisibleRange(byVisibleSpanFraction: -0.1)
        #expect(abs(viewport.startProgress - 0.35) < 0.000_001)

        viewport.moveVisibleRange(byVisibleSpanFraction: 0.1)
        #expect(abs(viewport.startProgress - 0.375) < 0.000_001)

        viewport.moveVisibleRange(byVisibleSpanFraction: -10)
        #expect(viewport.startProgress == 0)

        viewport.moveVisibleRange(byVisibleSpanFraction: 10)
        #expect(abs(viewport.startProgress - 0.75) < 0.000_001)
    }

    @Test
    func resetReturnsToTheFullWaveform() {
        var viewport = WaveformViewport()
        viewport.setZoomPosition(
            0.5,
            maximumZoomScale: 16,
            centeredAt: 0.5
        )

        viewport.reset()
        #expect(viewport.zoomScale == 1)
        #expect(viewport.startProgress == 0)
        #expect(viewport.endProgress == 1)
    }

    @Test
    func maximumZoomStopsBeforeEnvelopeWouldBeStretchedPastItsResolution() {
        let maximumZoomScale = WaveformViewport.maximumZoomScale(
            sampleCount: 16_384,
            displayWidth: 1_024
        )

        #expect(abs(maximumZoomScale - 16) < 0.000_001)
    }
}
