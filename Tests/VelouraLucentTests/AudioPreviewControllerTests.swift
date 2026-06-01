import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct AudioPreviewControllerTests {
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

        controller.preparePreviewPlaceholder(for: newURL, target: .input)

        #expect(controller.cardState(for: .input).sourceURL == newURL)
        #expect(controller.cardState(for: .input).snapshot == nil)
        #expect(controller.cardState(for: .input).liveBandLevels.isEmpty)
        #expect(controller.integratedLoudnessLUFS(for: .input) == nil)
        #expect(controller.cardState(for: .input).playbackProgress == 0)
        #expect(controller.cardState(for: .input).playbackPosition == 0)
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

    private struct PreviewFixture {
        let directory: URL
        let url: URL
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
