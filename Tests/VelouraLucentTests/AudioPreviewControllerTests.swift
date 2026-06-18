import Foundation
import AVFoundation
import Testing
@testable import VelouraLucent

@MainActor
struct AudioPreviewControllerTests {
    @Test
    func comparisonDefaultsToInputAndCorrectedAudio() {
        let controller = AudioPreviewController()

        #expect(controller.comparisonPair == .inputVsCorrected)
        #expect(controller.comparisonTarget(for: .a) == .input)
    }

    @Test
    func comparisonPairSwitchesTargets() {
        let controller = AudioPreviewController()

        controller.setComparisonPair(.inputVsCorrected)

        #expect(controller.comparisonTarget(for: .a) == .input)
        #expect(controller.comparisonTarget(for: .b) == .corrected)

        controller.setComparisonPair(.inputVsMastered)

        #expect(controller.comparisonTarget(for: .a) == .input)
        #expect(controller.comparisonTarget(for: .b) == .mastered)

        controller.setComparisonPair(.correctedVsMastered)

        #expect(controller.comparisonTarget(for: .a) == .corrected)
        #expect(controller.comparisonTarget(for: .b) == .mastered)
    }

    @Test
    func loudnessMatchedComparisonToggleUpdatesState() {
        let controller = AudioPreviewController()

        controller.setLoudnessMatchedComparisonEnabled(true)
        #expect(controller.isLoudnessMatchedComparisonEnabled)

        controller.setLoudnessMatchedComparisonEnabled(false)
        #expect(controller.isLoudnessMatchedComparisonEnabled == false)
    }

    @Test
    func playbackVolumeUpdatesState() {
        let controller = AudioPreviewController()

        controller.setPlaybackVolume(0.42)
        #expect(controller.playbackVolume == 0.42)

        controller.setPlaybackVolume(1.5)
        #expect(controller.playbackVolume == 1.0)
    }

    @Test
    func waveformSeekSynchronizesAllAvailableTargetsByPlaybackTime() {
        let controller = AudioPreviewController()
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 10),
            for: .input,
            sourceURL: URL(filePath: "/tmp/input.wav")
        )
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 8),
            for: .corrected,
            sourceURL: URL(filePath: "/tmp/corrected.wav")
        )
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 12),
            for: .mastered,
            sourceURL: URL(filePath: "/tmp/mastered.wav")
        )

        controller.seek(to: 0.6, target: .input)

        #expect(controller.cardState(for: .input).playbackPosition == 6)
        #expect(controller.cardState(for: .input).playbackProgress == 0.6)
        #expect(controller.cardState(for: .corrected).playbackPosition == 6)
        #expect(controller.cardState(for: .corrected).playbackProgress == 0.75)
        #expect(controller.cardState(for: .mastered).playbackPosition == 6)
        #expect(controller.cardState(for: .mastered).playbackProgress == 0.5)
    }

    @Test
    func waveformSeekClampsShorterABTargetToItsDuration() {
        let controller = AudioPreviewController()
        controller.setComparisonPair(.inputVsCorrected)
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 10),
            for: .input,
            sourceURL: URL(filePath: "/tmp/input.wav")
        )
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 8),
            for: .corrected,
            sourceURL: URL(filePath: "/tmp/corrected.wav")
        )

        controller.seek(to: 0.9, target: .input)

        #expect(controller.cardState(for: controller.comparisonTarget(for: .a)).playbackPosition == 9)
        #expect(controller.cardState(for: controller.comparisonTarget(for: .b)).playbackPosition == 8)
        #expect(controller.cardState(for: controller.comparisonTarget(for: .b)).playbackProgress == 1)
    }

    @Test
    func globalStopResetsAllSynchronizedPlaybackPositions() {
        let controller = AudioPreviewController()
        for target in AudioPreviewTarget.allCases {
            controller.setPreviewSnapshot(
                previewSnapshot(duration: 10),
                for: target,
                sourceURL: URL(filePath: "/tmp/\(target.rawValue).wav")
            )
        }

        controller.seek(to: 0.6, target: .input)
        controller.stopPlayback()

        for target in AudioPreviewTarget.allCases {
            #expect(controller.cardState(for: target).playbackPosition == 0)
            #expect(controller.cardState(for: target).playbackProgress == 0)
            #expect(controller.playbackState(for: target) == .stopped)
        }
    }

    @Test
    func setPreviewSnapshotStoresMeasuredLoudness() {
        let controller = AudioPreviewController()
        let snapshot = AudioPreviewSnapshot(
            waveform: [0, 0.5, 0],
            duration: 1,
            bandLevels: [:],
            bandLevelDBs: [:]
        )
        let sourceURL = URL(filePath: "/tmp/veloura-preview.wav")

        controller.setPreviewSnapshot(
            snapshot,
            for: .corrected,
            sourceURL: sourceURL,
            integratedLoudnessLUFS: -16.25
        )

        #expect(controller.previewSnapshots[.corrected]?.duration == 1)
        #expect(controller.integratedLoudnessLUFS(for: .corrected) == Float(-16.25))
    }

    @Test
    func previewCardStatesAreStoredPerTarget() {
        let controller = AudioPreviewController()
        let inputSnapshot = AudioPreviewSnapshot(
            waveform: [0, 0.25, 0],
            duration: 1,
            bandLevels: [:],
            bandLevelDBs: [:]
        )
        let correctedSnapshot = AudioPreviewSnapshot(
            waveform: [0, 0.75, 0],
            duration: 2,
            bandLevels: [:],
            bandLevelDBs: [:]
        )

        controller.setPreviewSnapshot(inputSnapshot, for: .input, sourceURL: URL(filePath: "/tmp/input.wav"))
        controller.setPreviewSnapshot(correctedSnapshot, for: .corrected, sourceURL: URL(filePath: "/tmp/corrected.wav"))

        #expect(controller.cardState(for: .input).snapshot?.duration == 1)
        #expect(controller.cardState(for: .corrected).snapshot?.duration == 2)
        #expect(controller.cardState(for: .mastered).snapshot == nil)
    }

    @Test
    func preparePreviewPlaceholderClearsSnapshotWithoutLoadingAudio() {
        let controller = AudioPreviewController()
        let oldSnapshot = AudioPreviewSnapshot(
            waveform: [0, 0.25, 0],
            duration: 1,
            bandLevels: [:],
            bandLevelDBs: [:]
        )
        let oldURL = URL(filePath: "/tmp/old-input.wav")
        let newURL = URL(filePath: "/tmp/missing-input.wav")

        controller.setPreviewSnapshot(oldSnapshot, for: .input, sourceURL: oldURL, integratedLoudnessLUFS: -18)
        controller.cardState(for: .input).playbackProgress = 0.5
        controller.cardState(for: .input).playbackPosition = 0.5
        controller.cardState(for: .input).vectorScopeSnapshot = VectorScopeSnapshot(
            inputState: .stereo,
            points: [VectorScopePoint(id: 0, x: 0.2, y: 0.4)]
        )
        controller.cardState(for: .input).liveLoudnessMeterSnapshot = liveLoudnessSnapshot()

        controller.preparePreviewPlaceholder(for: newURL, target: .input)

        #expect(controller.cardState(for: .input).sourceURL == newURL)
        #expect(controller.cardState(for: .input).snapshot == nil)
        #expect(controller.cardState(for: .input).liveBandLevels.isEmpty)
        #expect(controller.integratedLoudnessLUFS(for: .input) == nil)
        #expect(controller.cardState(for: .input).playbackProgress == 0)
        #expect(controller.cardState(for: .input).playbackPosition == 0)
        #expect(controller.cardState(for: .input).vectorScopeSnapshot == .unavailable)
        #expect(controller.cardState(for: .input).liveLoudnessMeterSnapshot == .unavailable)
        guard case .stopped = controller.cardState(for: .input).playbackState else {
            Issue.record("Placeholder should stop input playback state")
            return
        }
    }

    @Test
    func stoppingOnePreviewCardDoesNotResetOtherCardState() {
        let controller = AudioPreviewController()
        let snapshot = AudioPreviewSnapshot(
            waveform: [0, 0.5, 0],
            duration: 1,
            bandLevels: [:],
            bandLevelDBs: [:]
        )

        controller.setPreviewSnapshot(snapshot, for: .input, sourceURL: URL(filePath: "/tmp/input.wav"))
        controller.setPreviewSnapshot(snapshot, for: .corrected, sourceURL: URL(filePath: "/tmp/corrected.wav"))
        controller.cardState(for: .input).playbackProgress = 0.4
        controller.cardState(for: .input).playbackPosition = 0.4
        controller.cardState(for: .corrected).playbackProgress = 0.7
        controller.cardState(for: .corrected).playbackPosition = 0.7

        controller.stopPlayback(target: .input)

        #expect(controller.cardState(for: .input).playbackProgress == 0)
        #expect(controller.cardState(for: .input).playbackPosition == 0)
        #expect(controller.cardState(for: .corrected).playbackProgress == 0.7)
        #expect(controller.cardState(for: .corrected).playbackPosition == 0.7)
    }

    @Test
    func finishingActivePlaybackResetsAllSynchronizedCardState() {
        let controller = AudioPreviewController()
        let snapshot = AudioPreviewSnapshot(
            waveform: [0, 0.5, 0],
            duration: 10,
            bandLevels: [:],
            bandLevelDBs: [:]
        )

        controller.setPreviewSnapshot(snapshot, for: .input, sourceURL: URL(filePath: "/tmp/input.wav"))
        controller.setPreviewSnapshot(snapshot, for: .corrected, sourceURL: URL(filePath: "/tmp/corrected.wav"))
        controller.setPreviewSnapshot(snapshot, for: .mastered, sourceURL: URL(filePath: "/tmp/mastered.wav"))
        controller.seek(to: 0.6, target: .input)
        controller.activeTarget = .input
        controller.cardState(for: .input).playbackState = .playing
        for target in AudioPreviewTarget.allCases {
            controller.cardState(for: target).vectorScopeSnapshot = VectorScopeSnapshot(
                inputState: .stereo,
                points: [VectorScopePoint(id: 0, x: 0.2, y: 0.4)]
            )
            controller.cardState(for: target).liveLoudnessMeterSnapshot = liveLoudnessSnapshot()
        }

        controller.finishActivePlayback()

        #expect(controller.cardState(for: .input).playbackProgress == 0)
        #expect(controller.cardState(for: .input).playbackPosition == 0)
        #expect(controller.cardState(for: .corrected).playbackProgress == 0)
        #expect(controller.cardState(for: .corrected).playbackPosition == 0)
        #expect(controller.cardState(for: .mastered).playbackProgress == 0)
        #expect(controller.cardState(for: .mastered).playbackPosition == 0)
        for target in AudioPreviewTarget.allCases {
            #expect(controller.cardState(for: target).vectorScopeSnapshot == .unavailable)
            #expect(controller.cardState(for: target).liveLoudnessMeterSnapshot == .unavailable)
        }
    }

    @Test
    func preparePreviewCanSkipLoudnessMeasurementWhenAnalysisWillProvideIt() async throws {
        let fixture = try makePreviewFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        controller.preparePreview(for: fixture.url, target: .input, measureLoudness: false)

        for _ in 0..<50 where controller.previewSnapshots[.input] == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(controller.previewSnapshots[.input] != nil)
        #expect(controller.integratedLoudnessLUFS(for: .input) == nil)
    }

    @Test
    func preparePreviewMeasuresMissingLoudnessForExistingSnapshot() async throws {
        let fixture = try makePreviewFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        controller.preparePreview(for: fixture.url, target: .input, measureLoudness: false)

        for _ in 0..<50 where controller.previewSnapshots[.input] == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(controller.previewSnapshots[.input] != nil)
        #expect(controller.integratedLoudnessLUFS(for: .input) == nil)

        controller.preparePreview(for: fixture.url, target: .input, measureLoudness: true)

        for _ in 0..<50 where controller.integratedLoudnessLUFS(for: .input) == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(controller.previewSnapshots[.input] != nil)
        #expect(controller.integratedLoudnessLUFS(for: .input) != nil)
    }

    @Test
    func realtimeSpectrumAnalyzerCreatesDisplayPointsFromPCMBuffer() throws {
        let sampleRate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = Float(sin(2 * Double.pi * 1_000 * Double(index) / sampleRate) * 0.5)
        }

        let points = RealtimeSpectrumAnalyzer.points(from: buffer)

        #expect(points.isEmpty == false)
        #expect(points.contains { $0.frequencyHz == 1_000 })
        #expect(points.allSatisfy { $0.levelDB >= -100 && $0.levelDB <= 0 })
        #expect((points.map(\.levelDB).max() ?? -100) > -60)
    }

    @Test
    func realtimeSpectrumTapBufferSizeKeepsLowSampleRateAnalyzable() throws {
        let sampleRate = 16_000.0
        let bufferSize = RealtimeSpectrumAnalyzer.tapBufferSize(for: sampleRate)

        #expect(bufferSize == AVAudioFrameCount(RealtimeSpectrumAnalyzer.analysisSampleCount))

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!
        buffer.frameLength = bufferSize
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = Float(sin(2 * Double.pi * 1_000 * Double(index) / sampleRate) * 0.5)
        }

        let points = RealtimeSpectrumAnalyzer.points(from: buffer)

        #expect(points.isEmpty == false)
        #expect(points.contains { $0.frequencyHz == 1_000 })
    }

    @Test
    func vectorScopeShowsInPhaseSignalVertically() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, sample) })

        #expect(snapshot.inputState == .stereo)
        #expect(snapshot.points.count == VectorScopeAnalyzer.maximumPointCount)
        #expect(snapshot.points.allSatisfy { abs($0.x) < 0.000_001 })
        #expect((snapshot.points.map { abs($0.y) }.max() ?? 0) > 0.4)
    }

    @Test
    func vectorScopeShowsReversePhaseSignalHorizontally() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, -sample) })

        #expect(snapshot.inputState == .stereo)
        #expect(snapshot.points.allSatisfy { abs($0.y) < 0.000_001 })
        #expect((snapshot.points.map { abs($0.x) }.max() ?? 0) > 0.4)
    }

    @Test
    func vectorScopeShowsLeftOnlySignalDiagonally() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, 0) })

        #expect(snapshot.inputState == .stereo)
        #expect(snapshot.points.allSatisfy { abs($0.x - $0.y) < 0.000_001 })
        #expect((snapshot.points.map { abs($0.x) }.max() ?? 0) > 0.2)
    }

    @Test
    func vectorScopeDoesNotDrawSilence() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { _ in (0, 0) })

        #expect(snapshot.inputState == .stereo)
        #expect(snapshot.points.isEmpty)
    }

    @Test
    func vectorScopeReportsMonoWithoutDrawing() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_048)!
        buffer.frameLength = 2_048

        let snapshot = VectorScopeAnalyzer.snapshot(from: buffer)

        #expect(snapshot.inputState == .mono)
        #expect(snapshot.points.isEmpty)
    }

    @Test
    func vectorScopeReportsMultichannelAsUnsupported() {
        #expect(VectorScopeAnalyzer.inputState(forChannelCount: 3) == .multichannel(3))
    }

    @Test
    func globalStopClearsAllVectorScopeSnapshots() {
        let controller = AudioPreviewController()
        for target in AudioPreviewTarget.allCases {
            controller.cardState(for: target).vectorScopeSnapshot = VectorScopeSnapshot(
                inputState: .stereo,
                points: [VectorScopePoint(id: 0, x: 0.2, y: 0.4)]
            )
            controller.cardState(for: target).liveLoudnessMeterSnapshot = liveLoudnessSnapshot()
        }

        controller.stopPlayback()

        for target in AudioPreviewTarget.allCases {
            #expect(controller.cardState(for: target).vectorScopeSnapshot == .unavailable)
            #expect(controller.cardState(for: target).liveLoudnessMeterSnapshot == .unavailable)
        }
    }

    @Test
    func pausingActiveTargetPreservesVectorScopeSnapshot() {
        let controller = AudioPreviewController()
        controller.activeTarget = .corrected
        let snapshot = VectorScopeSnapshot(
            inputState: .stereo,
            points: [VectorScopePoint(id: 0, x: 0.2, y: 0.4)]
        )
        controller.cardState(for: .corrected).vectorScopeSnapshot = snapshot

        controller.pausePlayback(target: .corrected)

        #expect(controller.cardState(for: .corrected).vectorScopeSnapshot == snapshot)
    }

    @Test
    func delayedVectorScopeResultDoesNotReplacePausedSnapshot() {
        let controller = AudioPreviewController()
        controller.activeTarget = .corrected
        let retainedSnapshot = VectorScopeSnapshot(
            inputState: .stereo,
            points: [VectorScopePoint(id: 0, x: 0.2, y: 0.4)]
        )
        controller.cardState(for: .corrected).vectorScopeSnapshot = retainedSnapshot
        controller.cardState(for: .corrected).playbackState = .paused

        controller.storeVectorScopeSnapshotIfPlaying(
            VectorScopeSnapshot(inputState: .stereo, points: []),
            for: .corrected
        )

        #expect(controller.cardState(for: .corrected).vectorScopeSnapshot == retainedSnapshot)
    }

    @Test
    func delayedLoudnessMeterResultDoesNotReplacePausedSnapshot() {
        let controller = AudioPreviewController()
        controller.activeTarget = .corrected
        let retainedSnapshot = liveLoudnessSnapshot(momentary: -22)
        controller.cardState(for: .corrected).liveLoudnessMeterSnapshot = retainedSnapshot
        controller.cardState(for: .corrected).playbackState = .paused

        controller.storeLiveLoudnessMeterSnapshotIfPlaying(
            liveLoudnessSnapshot(momentary: -12),
            for: .corrected
        )

        #expect(controller.cardState(for: .corrected).liveLoudnessMeterSnapshot == retainedSnapshot)
    }

    private struct PreviewFixture {
        let directory: URL
        let url: URL
    }

    private func previewSnapshot(duration: TimeInterval) -> AudioPreviewSnapshot {
        AudioPreviewSnapshot(
            waveform: [0, 0.5, 0],
            duration: duration,
            bandLevels: [:],
            bandLevelDBs: [:]
        )
    }

    private func liveLoudnessSnapshot(momentary: Double = -18) -> LiveLoudnessMeterSnapshot {
        LiveLoudnessMeterSnapshot(
            state: .measuring,
            momentaryLUFS: momentary,
            shortTermLUFS: -19,
            integratedLUFS: -20,
            truePeakDBTP: -1
        )
    }

    private func stereoBuffer(
        transform: (Float) -> (Float, Float)
    ) -> AVAudioPCMBuffer {
        let sampleRate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_048)!
        buffer.frameLength = 2_048
        let channels = buffer.floatChannelData!
        for index in 0..<Int(buffer.frameLength) {
            let sample = Float(sin(2 * Double.pi * 1_000 * Double(index) / sampleRate) * 0.5)
            let transformed = transform(sample)
            channels[0][index] = transformed.0
            channels[1][index] = transformed.1
        }
        return buffer
    }

    private func makePreviewFixture() throws -> PreviewFixture {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appending(path: "preview.wav")
        let sampleRate = 44_100.0
        let samples = (0..<4_410).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.1)
        }
        try AudioFileService.saveAudio(AudioSignal(channels: [samples], sampleRate: sampleRate), to: sourceURL)
        return PreviewFixture(directory: tempDirectory, url: sourceURL)
    }
}
