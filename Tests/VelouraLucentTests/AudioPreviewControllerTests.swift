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
    func commandAvailabilityFollowsComparisonSourcesAndPlaybackState() {
        let controller = AudioPreviewController()

        #expect(controller.canToggleComparisonPlayback == false)
        #expect(controller.canToggleComparisonSide == false)
        #expect(controller.isComparisonPlaybackRunning == false)

        controller.cardState(for: .input).sourceURL = URL(filePath: "/tmp/input.wav")
        #expect(controller.canToggleComparisonPlayback)
        #expect(controller.canToggleComparisonSide == false)

        controller.cardState(for: .corrected).sourceURL = URL(filePath: "/tmp/corrected.wav")
        #expect(controller.canToggleComparisonSide)

        controller.activeTarget = .input
        controller.cardState(for: .input).playbackState = .playing
        #expect(controller.isComparisonPlaybackRunning)
    }

    @Test
    func comparisonSideToggleDoesNotStartStoppedPlayback() {
        let controller = AudioPreviewController()

        controller.toggleComparisonSide()

        #expect(controller.activeComparisonSide == .b)
        #expect(controller.activeTarget == nil)
        #expect(controller.playbackState(for: .input) == .stopped)
        #expect(controller.playbackState(for: .corrected) == .stopped)
    }

    @Test
    func comparisonSideToggleDoesNotResumePausedPlayback() {
        let controller = AudioPreviewController()
        controller.activeTarget = .input
        controller.cardState(for: .input).playbackState = .paused

        controller.toggleComparisonSide()

        #expect(controller.activeComparisonSide == .b)
        #expect(controller.activeTarget == .input)
        #expect(controller.playbackState(for: .input) == .paused)
        #expect(controller.playbackState(for: .corrected) == .stopped)
    }

    @Test
    func switchingComparisonPairPreservesPausedPlaybackPosition() {
        let controller = AudioPreviewController()
        let snapshot = previewSnapshot(duration: 10)
        controller.setPreviewSnapshot(snapshot, for: .input, sourceURL: URL(filePath: "/tmp/input.wav"))
        controller.setPreviewSnapshot(snapshot, for: .corrected, sourceURL: URL(filePath: "/tmp/corrected.wav"))
        controller.setPreviewSnapshot(snapshot, for: .mastered, sourceURL: URL(filePath: "/tmp/mastered.wav"))
        controller.setComparisonPair(.inputVsMastered)
        controller.seek(to: 0.4, target: .input)
        controller.activeTarget = .input
        controller.activeComparisonSide = .a
        controller.cardState(for: .input).playbackState = .paused

        controller.setComparisonPair(.correctedVsMastered)

        #expect(controller.comparisonPair == .correctedVsMastered)
        #expect(controller.activeComparisonSide == .a)
        #expect(controller.cardState(for: .input).playbackPosition == 4)
        #expect(controller.cardState(for: .corrected).playbackPosition == 4)
        #expect(controller.cardState(for: .mastered).playbackPosition == 4)
        #expect(controller.cardState(for: .corrected).playbackProgress == 0.4)
        #expect(controller.cardState(for: .mastered).playbackProgress == 0.4)
    }

    @Test
    func switchingComparisonPairKeepsCommonActiveTargetSide() {
        let controller = AudioPreviewController()
        let snapshot = previewSnapshot(duration: 10)
        controller.setPreviewSnapshot(snapshot, for: .input, sourceURL: URL(filePath: "/tmp/input.wav"))
        controller.setPreviewSnapshot(snapshot, for: .corrected, sourceURL: URL(filePath: "/tmp/corrected.wav"))
        controller.setPreviewSnapshot(snapshot, for: .mastered, sourceURL: URL(filePath: "/tmp/mastered.wav"))
        controller.setComparisonPair(.inputVsMastered)
        controller.seek(to: 0.5, target: .mastered)
        controller.activeTarget = .mastered
        controller.activeComparisonSide = .b
        controller.cardState(for: .mastered).playbackState = .paused

        controller.setComparisonPair(.correctedVsMastered)

        #expect(controller.comparisonPair == .correctedVsMastered)
        #expect(controller.activeTarget == .mastered)
        #expect(controller.activeComparisonSide == .b)
        #expect(controller.cardState(for: .corrected).playbackPosition == 5)
        #expect(controller.cardState(for: .mastered).playbackPosition == 5)
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
    func pausingPlaybackSynchronizesAllAvailableTargetsAtTheFinalPlaybackTime() async throws {
        let fixture = try makePreviewFixture(duration: 1)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        let snapshot = previewSnapshot(duration: 1)
        for target in AudioPreviewTarget.allCases {
            controller.setPreviewSnapshot(snapshot, for: target, sourceURL: fixture.url)
        }

        controller.startPlayback(for: fixture.url, target: .input)
        try await Task.sleep(nanoseconds: 135_000_000)
        controller.pausePlayback(target: .input)

        let pausedPosition = controller.cardState(for: .input).playbackPosition
        #expect(pausedPosition > 0.05)
        #expect(controller.cardState(for: .input).playbackState == .paused)
        for target in AudioPreviewTarget.allCases {
            #expect(abs(controller.cardState(for: target).playbackPosition - pausedPosition) < 0.001)
            #expect(abs(controller.cardState(for: target).playbackProgress - pausedPosition) < 0.001)
        }
    }

    @Test
    func switchingComparisonSideDuringPlaybackKeepsPreparedPlayersAndSynchronizesAllCardsImmediately() async throws {
        let fixture = try makeComparisonPreviewFixture(duration: 2)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        configureComparisonFixture(fixture, controller: controller)
        defer {
            controller.stopPlayback()
        }

        controller.startPlayback(for: fixture.inputURL, target: .input)
        try await Task.sleep(for: .milliseconds(150))

        let before = controller.playbackDiagnosticState()
        let engineBefore = try #require(before.engineIdentifier)
        let inputPlayerBefore = try #require(before.playerNodeIdentifiers[.input])
        let correctedPlayerBefore = try #require(before.playerNodeIdentifiers[.corrected])
        let positionBefore = controller.cardState(for: .input).playbackPosition
        #expect(before.playerNodeIsPlaying[.input] == true)
        #expect(before.playerNodeIsPlaying[.corrected] == true)
        #expect((before.playerNodeVolumes[.input] ?? 0) > 0)
        #expect(before.playerNodeVolumes[.corrected] == 0)
        #expect(before.analysisTarget == .input)

        controller.toggleComparisonSide()

        let after = controller.playbackDiagnosticState()
        let engineAfter = try #require(after.engineIdentifier)
        let inputPlayerAfter = try #require(after.playerNodeIdentifiers[.input])
        let correctedPlayerAfter = try #require(after.playerNodeIdentifiers[.corrected])
        #expect(engineBefore == engineAfter)
        #expect(inputPlayerBefore == inputPlayerAfter)
        #expect(correctedPlayerBefore == correctedPlayerAfter)
        #expect(after.playerNodeIsPlaying[.input] == true)
        #expect(after.playerNodeIsPlaying[.corrected] == true)
        #expect(after.playerNodeVolumes[.input] == 0)
        #expect((after.playerNodeVolumes[.corrected] ?? 0) > 0)
        #expect(after.analysisTarget == .corrected)
        #expect(after.analysisID != before.analysisID)
        #expect(controller.activeTarget == .corrected)
        #expect(controller.activeComparisonSide == .b)
        #expect(controller.playbackState(for: .input) == .paused)
        #expect(controller.playbackState(for: .corrected) == .playing)

        let switchedPositions = AudioPreviewTarget.allCases.map {
            controller.cardState(for: $0).playbackPosition
        }
        #expect((switchedPositions.max() ?? 0) - (switchedPositions.min() ?? 0) < 0.001)
        #expect((switchedPositions.first ?? 0) >= positionBefore)

        let switchedPosition = controller.cardState(for: .corrected).playbackPosition
        let didAdvance = await waitUntil {
            controller.cardState(for: .corrected).playbackPosition > switchedPosition + 0.03
        }
        #expect(didAdvance)
        let advancedPositions = AudioPreviewTarget.allCases.map {
            controller.cardState(for: $0).playbackPosition
        }
        #expect((advancedPositions.max() ?? 0) - (advancedPositions.min() ?? 0) < 0.001)
    }

    @Test
    func switchingToComparisonSideThatAlreadyEndedStopsWithoutRebuildingOrRewinding() async throws {
        let fixture = try makeComparisonPreviewFixture(duration: 1, correctedDuration: 0.12)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        configureComparisonFixture(fixture, controller: controller)
        defer {
            controller.stopPlayback()
        }

        controller.startPlayback(for: fixture.inputURL, target: .input)
        let didFinishInactiveSide = await waitUntil {
            controller.playbackDiagnosticState().completedTargets.contains(.corrected)
        }
        #expect(didFinishInactiveSide)

        let before = controller.playbackDiagnosticState()
        _ = try #require(before.engineIdentifier)
        #expect(before.completedTargets.contains(.corrected))
        #expect(controller.playbackState(for: .input) == .playing)
        #expect(controller.cardState(for: .input).playbackPosition >= fixture.correctedDuration)

        controller.toggleComparisonSide()

        #expect(controller.playbackDiagnosticState().engineIdentifier == nil)
        #expect(controller.activeTarget == nil)
        for target in AudioPreviewTarget.allCases {
            #expect(controller.playbackState(for: target) == .stopped)
            #expect(controller.cardState(for: target).playbackPosition == 0)
        }
    }

    @Test
    func seekingLongerComparisonSidePastShorterDurationDoesNotRewindPlayback() async throws {
        let fixture = try makeComparisonPreviewFixture(duration: 1, correctedDuration: 0.4)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        configureComparisonFixture(fixture, controller: controller)
        defer {
            controller.stopPlayback()
        }

        controller.startPlayback(for: fixture.inputURL, target: .input)
        controller.seek(to: 0.8, target: .input)

        #expect(abs(controller.cardState(for: .input).playbackPosition - 0.8) < 0.01)
        #expect(abs(controller.cardState(for: .corrected).playbackPosition - 0.4) < 0.001)
        #expect(abs(controller.cardState(for: .mastered).playbackPosition - 0.8) < 0.01)
        #expect(controller.playbackDiagnosticState().completedTargets.contains(.corrected))
        #expect(controller.playbackState(for: .input) == .playing)
    }

    @Test
    func switchingComparisonSideRoutesRealtimeAnalysisToTheAudiblePlayer() async throws {
        let fixture = try makeComparisonPreviewFixture(duration: 3)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        configureComparisonFixture(fixture, controller: controller)
        defer {
            controller.stopPlayback()
        }

        controller.startPlayback(for: fixture.inputURL, target: .input)
        let inputCorrelation = try await waitForCorrelation(
            controller: controller,
            target: .input,
            satisfying: { $0 > 0.9 }
        )
        #expect(inputCorrelation > 0.9)
        let inputAnalysisID = controller.playbackDiagnosticState().analysisID

        controller.toggleComparisonSide()

        let correctedAnalysisState = controller.playbackDiagnosticState()
        #expect(correctedAnalysisState.analysisTarget == .corrected)
        #expect(correctedAnalysisState.analysisID != inputAnalysisID)
        #expect(controller.cardState(for: .input).vectorScopeSnapshot == .unavailable)
        let correctedCorrelation = try await waitForCorrelation(
            controller: controller,
            target: .corrected,
            satisfying: { $0 < -0.9 }
        )
        #expect(correctedCorrelation < -0.9)
        #expect(controller.cardState(for: .input).vectorScopeSnapshot == .unavailable)

        let correctedAnalysisID = controller.playbackDiagnosticState().analysisID
        controller.toggleComparisonSide()

        let returnedAnalysisState = controller.playbackDiagnosticState()
        #expect(returnedAnalysisState.analysisTarget == .input)
        #expect(returnedAnalysisState.analysisID != correctedAnalysisID)
        #expect(controller.acceptsRealtimeAnalysis(for: .input, analysisID: inputAnalysisID) == false)
        #expect(controller.acceptsRealtimeAnalysis(for: .corrected, analysisID: correctedAnalysisID) == false)
        #expect(controller.acceptsRealtimeAnalysis(for: .input, analysisID: returnedAnalysisState.analysisID))
        #expect(controller.cardState(for: .corrected).vectorScopeSnapshot == .unavailable)
        let returnedInputCorrelation = try await waitForCorrelation(
            controller: controller,
            target: .input,
            satisfying: { $0 > 0.9 }
        )
        #expect(returnedInputCorrelation > 0.9)
        #expect(controller.cardState(for: .corrected).vectorScopeSnapshot == .unavailable)
    }

    @Test
    func comparisonAnalysisKeepsEachSourcesNativeFormatAcrossSwitches() async throws {
        let fixture = try makeComparisonPreviewFixture(duration: 2, inputChannelCount: 1)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        configureComparisonFixture(fixture, controller: controller)
        defer {
            controller.stopPlayback()
        }

        controller.startPlayback(for: fixture.inputURL, target: .input)
        let inputState = controller.playbackDiagnosticState()
        #expect(inputState.analysisOutputSampleRate == 44_100)
        #expect(inputState.analysisOutputChannelCount == 1)
        #expect(controller.cardState(for: .input).vectorScopeSnapshot.inputState == .mono)

        controller.toggleComparisonSide()

        let correctedState = controller.playbackDiagnosticState()
        #expect(correctedState.playbackSessionID == inputState.playbackSessionID)
        #expect(correctedState.engineIdentifier == inputState.engineIdentifier)
        #expect(correctedState.analysisOutputSampleRate == 48_000)
        #expect(correctedState.analysisOutputChannelCount == 2)
        #expect(controller.cardState(for: .corrected).vectorScopeSnapshot.inputState == .stereo)
    }

    @Test
    func comparisonAnalysisReflectsPlaybackVolume() async throws {
        let fixture = try makeComparisonPreviewFixture(duration: 2)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let fullVolumeController = AudioPreviewController()
        configureComparisonFixture(fixture, controller: fullVolumeController)
        fullVolumeController.startPlayback(for: fixture.inputURL, target: .input)
        let fullVolumePeak = try await waitForTruePeak(
            controller: fullVolumeController,
            target: .input
        )
        fullVolumeController.stopPlayback()

        let halfVolumeController = AudioPreviewController()
        configureComparisonFixture(fixture, controller: halfVolumeController)
        halfVolumeController.setPlaybackVolume(0.5)
        halfVolumeController.startPlayback(for: fixture.inputURL, target: .input)
        let halfVolumePeak = try await waitForTruePeak(
            controller: halfVolumeController,
            target: .input
        )
        halfVolumeController.stopPlayback()

        #expect(abs((fullVolumePeak - halfVolumePeak) - 6.02) < 0.75)
    }

    @Test
    func changingComparisonPairRefreshesPreparedPlayersBeforeTheNextABSwitch() async throws {
        let fixture = try makeComparisonPreviewFixture(duration: 2)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        configureComparisonFixture(fixture, controller: controller)
        defer {
            controller.stopPlayback()
        }

        controller.startPlayback(for: fixture.inputURL, target: .input)
        let originalSession = controller.playbackDiagnosticState().playbackSessionID

        controller.setComparisonPair(.inputVsMastered)

        let refreshedState = controller.playbackDiagnosticState()
        #expect(refreshedState.playbackSessionID != originalSession)
        #expect(refreshedState.engineIsRunning)
        #expect(refreshedState.playerNodeIdentifiers.keys.contains(.input))
        #expect(refreshedState.playerNodeIdentifiers.keys.contains(.mastered))
        #expect(controller.activeTarget == .input)

        controller.toggleComparisonSide()

        let switchedState = controller.playbackDiagnosticState()
        #expect(switchedState.playbackSessionID == refreshedState.playbackSessionID)
        #expect(switchedState.engineIdentifier == refreshedState.engineIdentifier)
        #expect(controller.activeTarget == .mastered)
        let positions = AudioPreviewTarget.allCases.map {
            controller.cardState(for: $0).playbackPosition
        }
        #expect((positions.max() ?? 0) - (positions.min() ?? 0) < 0.001)
    }

    @Test
    func changingComparisonPairWhilePausedPreservesTheResumePosition() async throws {
        let fixture = try makeComparisonPreviewFixture(duration: 2)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        configureComparisonFixture(fixture, controller: controller)
        defer {
            controller.stopPlayback()
        }

        controller.startPlayback(for: fixture.inputURL, target: .input)
        let didAdvance = await waitUntil {
            controller.cardState(for: .input).playbackPosition > 0.05
        }
        #expect(didAdvance)
        controller.pausePlayback(target: .input)
        let pausedPosition = controller.cardState(for: .input).playbackPosition

        controller.setComparisonPair(.inputVsMastered)

        #expect(controller.playbackDiagnosticState().engineIdentifier == nil)
        #expect(controller.activeTarget == .input)
        #expect(controller.playbackState(for: .input) == .paused)
        #expect(abs(controller.cardState(for: .input).playbackPosition - pausedPosition) < 0.01)

        controller.toggleComparisonPlayback()

        let resumedState = controller.playbackDiagnosticState()
        #expect(resumedState.engineIsRunning)
        #expect(resumedState.playerNodeIdentifiers.keys.contains(.input))
        #expect(resumedState.playerNodeIdentifiers.keys.contains(.mastered))
        #expect(controller.playbackState(for: .input) == .playing)
        #expect(controller.cardState(for: .input).playbackPosition >= pausedPosition - 0.01)
    }

    @Test
    func preparedComparisonPlaybackPreservesPauseSeekAndStopContracts() async throws {
        let fixture = try makeComparisonPreviewFixture(duration: 2)
        defer {
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let controller = AudioPreviewController()
        configureComparisonFixture(fixture, controller: controller)

        controller.startPlayback(for: fixture.inputURL, target: .input)
        try await Task.sleep(for: .milliseconds(120))
        controller.pausePlayback(target: .input)

        let paused = controller.playbackDiagnosticState()
        #expect(paused.playerNodeIdentifiers.count == 2)
        #expect(paused.playerNodeIsPlaying.values.allSatisfy { !$0 })
        let pausedPositions = AudioPreviewTarget.allCases.map {
            controller.cardState(for: $0).playbackPosition
        }
        #expect((pausedPositions.max() ?? 0) - (pausedPositions.min() ?? 0) < 0.001)

        controller.toggleComparisonPlayback()
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.playbackDiagnosticState().playerNodeIsPlaying.values.allSatisfy { $0 })

        controller.seek(to: 0.6, target: .input)
        let soughtPositions = AudioPreviewTarget.allCases.map {
            controller.cardState(for: $0).playbackPosition
        }
        #expect(soughtPositions.allSatisfy { abs($0 - 1.2) < 0.001 })
        #expect(controller.playbackDiagnosticState().playerNodeIsPlaying.values.allSatisfy { $0 })

        controller.stopPlayback()
        let stopped = controller.playbackDiagnosticState()
        #expect(stopped.engineIdentifier == nil)
        #expect(stopped.playerNodeIdentifiers.isEmpty)
        #expect(stopped.analysisTarget == nil)
        for target in AudioPreviewTarget.allCases {
            #expect(controller.cardState(for: target).playbackPosition == 0)
            #expect(controller.cardState(for: target).playbackProgress == 0)
            #expect(controller.playbackState(for: target) == .stopped)
        }
    }

    @Test
    func realtimeSpectrumUsesSelectedPairAtTheSamePlaybackPosition() {
        let controller = AudioPreviewController()
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 10, spectrumLevels: [-11, -21]),
            for: .input,
            sourceURL: URL(filePath: "/tmp/input.wav")
        )
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 10, spectrumLevels: [-31, -41]),
            for: .corrected,
            sourceURL: URL(filePath: "/tmp/corrected.wav")
        )
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 10, spectrumLevels: [-51, -61]),
            for: .mastered,
            sourceURL: URL(filePath: "/tmp/mastered.wav")
        )
        controller.activeTarget = .input
        controller.cardState(for: .input).playbackState = .paused

        controller.seek(to: 1, target: .input)

        #expect(controller.cardState(for: .input).realtimeSpectrum.first?.levelDB == -21)
        #expect(controller.cardState(for: .corrected).realtimeSpectrum.first?.levelDB == -41)
        #expect(controller.cardState(for: .mastered).realtimeSpectrum.isEmpty)

        controller.setComparisonPair(.inputVsMastered)

        #expect(controller.cardState(for: .input).realtimeSpectrum.first?.levelDB == -21)
        #expect(controller.cardState(for: .corrected).realtimeSpectrum.isEmpty)
        #expect(controller.cardState(for: .mastered).realtimeSpectrum.first?.levelDB == -61)

        controller.stopPlayback()

        for target in AudioPreviewTarget.allCases {
            #expect(controller.cardState(for: target).realtimeSpectrum.isEmpty)
        }
    }

    @Test
    func realtimeSpectrumAlignsDifferentDurationTargetsBySeconds() {
        let controller = AudioPreviewController()
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 10, spectrumLevels: [-10, -11, -12]),
            for: .input,
            sourceURL: URL(filePath: "/tmp/input.wav")
        )
        controller.setPreviewSnapshot(
            previewSnapshot(duration: 20, spectrumLevels: [-20, -21, -22, -23, -24]),
            for: .corrected,
            sourceURL: URL(filePath: "/tmp/corrected.wav")
        )
        controller.activeTarget = .input
        controller.cardState(for: .input).playbackState = .paused

        controller.seek(to: 0.5, target: .input)

        #expect(controller.cardState(for: .input).playbackPosition == 5)
        #expect(controller.cardState(for: .corrected).playbackPosition == 5)
        #expect(controller.cardState(for: .input).realtimeSpectrum.first?.levelDB == -11)
        #expect(controller.cardState(for: .corrected).realtimeSpectrum.first?.levelDB == -21)
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
            waveform: [.zero, .symmetric(0.5), .zero],
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
            waveform: [.zero, .symmetric(0.25), .zero],
            duration: 1,
            bandLevels: [:],
            bandLevelDBs: [:]
        )
        let correctedSnapshot = AudioPreviewSnapshot(
            waveform: [.zero, .symmetric(0.75), .zero],
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
            waveform: [.zero, .symmetric(0.25), .zero],
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
            waveform: [.zero, .symmetric(0.5), .zero],
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
            waveform: [.zero, .symmetric(0.5), .zero],
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

        for _ in 0..<500 where controller.previewSnapshots[.input] == nil {
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

        for _ in 0..<500 where controller.integratedLoudnessLUFS(for: .input) == nil {
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
    func realtimeSpectrumAnalyzerCreatesTenthSecondTimeline() throws {
        let sampleRate = 48_000.0
        let samples = (0..<Int(sampleRate)).map { index in
            Float(sin(2 * Double.pi * 1_000 * Double(index) / sampleRate) * 0.5)
        }

        let timeline = RealtimeSpectrumAnalyzer.timeline(
            from: samples,
            sampleRate: sampleRate
        )

        #expect(RealtimeSpectrumAnalyzer.timelineInterval == 0.1)
        #expect(timeline.count == 11)
        #expect(timeline.allSatisfy { frame in
            frame.contains { $0.frequencyHz == 1_000 && $0.levelDB > -60 }
        })
    }

    @Test
    func realtimeSpectrumTimelineKeepsOppositePhaseStereoEnergy() throws {
        let sampleRate = 48_000.0
        let left = (0..<Int(sampleRate)).map { index in
            Float(sin(2 * Double.pi * 1_000 * Double(index) / sampleRate) * 0.5)
        }
        let inPhase = RealtimeSpectrumAnalyzer.timeline(
            from: [left, left],
            sampleRate: sampleRate
        )
        let oppositePhase = RealtimeSpectrumAnalyzer.timeline(
            from: [left, left.map { -$0 }],
            sampleRate: sampleRate
        )

        #expect(inPhase.count == oppositePhase.count)
        for (inPhaseFrame, oppositePhaseFrame) in zip(inPhase, oppositePhase) {
            let inPhaseLevel = try #require(inPhaseFrame.first { $0.frequencyHz == 1_000 }?.levelDB)
            let oppositePhaseLevel = try #require(oppositePhaseFrame.first { $0.frequencyHz == 1_000 }?.levelDB)
            #expect(abs(inPhaseLevel - oppositePhaseLevel) < 0.000_001)
            #expect(oppositePhaseLevel > -60)
        }
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
        #expect(snapshot.polarSamplePoints.allSatisfy { abs($0.x) < 0.000_001 })
        #expect((snapshot.polarSamplePoints.map { abs($0.y) }.max() ?? 0) > 0.6)
        #expect((snapshot.correlation ?? 0) > 0.99)
        #expect(abs(snapshot.balance ?? 1) < 0.000_001)
    }

    @Test
    func vectorScopeShowsReversePhaseSignalHorizontally() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, -sample) })

        #expect(snapshot.inputState == .stereo)
        #expect(snapshot.points.allSatisfy { abs($0.y) < 0.000_001 })
        #expect((snapshot.points.map { abs($0.x) }.max() ?? 0) > 0.4)
        #expect(snapshot.polarSamplePoints.allSatisfy { abs($0.y) < 0.000_001 })
        #expect((snapshot.polarSamplePoints.map { abs($0.x) }.max() ?? 0) > 0.6)
        #expect((snapshot.correlation ?? 0) < -0.99)
    }

    @Test
    func vectorScopeShowsLeftOnlySignalDiagonally() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, 0) })

        #expect(snapshot.inputState == .stereo)
        #expect(snapshot.points.allSatisfy { abs($0.x + $0.y) < 0.000_001 })
        #expect((snapshot.points.map { $0.x }.min() ?? 0) < -0.2)
        #expect(snapshot.polarSamplePoints.allSatisfy { abs(abs($0.x) - $0.y) < 0.000_001 })
        #expect((snapshot.polarSamplePoints.map { $0.x }.min() ?? 0) < -0.3)
        #expect((snapshot.balance ?? 0) < -0.99)
    }

    @Test
    func vectorScopeReportsRightOnlySignalAsRightBalanced() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (0, sample) })

        #expect(snapshot.inputState == .stereo)
        #expect((snapshot.balance ?? 0) > 0.99)
        #expect((snapshot.polarSamplePoints.map { $0.x }.max() ?? 0) > 0.3)
        let line = try #require(snapshot.polarLevelLines.first)
        #expect(line.x > 0.2)
        #expect(line.y > 0.2)
    }

    @Test
    func polarSampleMarksClippedSamples() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in
            sample > 0 ? (1, 1) : (sample, sample)
        })

        #expect(snapshot.polarSamplePoints.contains { $0.isClipped })
        #expect(snapshot.polarLevelLines.first?.isClipped == true)
        #expect(snapshot.polarLevelLines(for: .peak).first?.isClipped == true)
    }

    @Test
    func polarLevelShowsInPhaseVerticallyAndReversePhaseHorizontally() throws {
        let inPhase = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, sample) })
        let reversePhase = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, -sample) })

        let inPhaseLine = try #require(inPhase.polarLevelLines.first)
        #expect(abs(inPhaseLine.x) < 0.000_001)
        #expect(inPhaseLine.y > 0.4)

        let reverseLine = try #require(reversePhase.polarLevelLines.first)
        #expect(abs(reverseLine.y) < 0.000_001)
        #expect(abs(reverseLine.x) > 0.4)
    }

    @Test
    func polarLevelStoresRMSAndPeakLines() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, sample) })

        let rmsLine = try #require(snapshot.polarLevelLines(for: .rms).first)
        let peakLine = try #require(snapshot.polarLevelLines(for: .peak).first)

        #expect(abs(rmsLine.x) < 0.000_001)
        #expect(abs(peakLine.x) < 0.000_001)
        #expect(peakLine.y > rmsLine.y)
        #expect(abs(rmsLine.y - 0.5) < 0.01)
        #expect(abs(peakLine.y - sqrt(0.5)) < 0.01)
    }

    @Test
    func polarLevelPeakUsesMidSideMaximum() throws {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, -sample) })

        let rmsLine = try #require(snapshot.polarLevelLines(for: .rms).first)
        let peakLine = try #require(snapshot.polarLevelLines(for: .peak).first)

        #expect(abs(rmsLine.y) < 0.000_001)
        #expect(abs(peakLine.y) < 0.000_001)
        #expect(abs(peakLine.x) > abs(rmsLine.x))
        #expect(abs(abs(rmsLine.x) - 0.5) < 0.01)
        #expect(abs(abs(peakLine.x) - sqrt(0.5)) < 0.01)
    }

    @Test
    func polarLevelPeakKeepsMidSideValuesFromSameSample() throws {
        var samples = Array(repeating: (Float(0), Float(0)), count: 2_048)
        samples[0] = (0.8, 0.8)
        samples[1] = (-0.7, 0.7)
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer(samples: samples))

        let peakLine = try #require(snapshot.polarLevelLines(for: .peak).first)

        #expect(abs(peakLine.x) < 0.000_001)
        #expect(abs(peakLine.y - 1) < 0.000_001)
    }

    @Test
    func vectorScopeHistoryFadesForThreeSeconds() {
        #expect(VectorScopeAnalyzer.historyDurationSeconds == 3.0)
    }

    @Test
    func vectorScopeSnapshotStoresActualBufferDuration() {
        let snapshot = VectorScopeAnalyzer.snapshot(from: stereoBuffer { sample in (sample, sample) })

        #expect(abs(snapshot.updateDurationSeconds - (2_048.0 / 48_000.0)) < 0.000_001)
    }

    @Test
    func vectorScopeMergingKeepsAgedHistory() {
        let previous = VectorScopeSnapshot(
            inputState: .stereo,
            points: [VectorScopePoint(id: 1, x: 0.1, y: 0.2)],
            polarSamplePoints: [VectorScopePoint(id: 2, x: 0.2, y: 0.3)],
            polarLevelLinesByDetectionMode: [
                .rms: [VectorScopeLine(id: 3, x: 0.1, y: 0.5)],
                .peak: [VectorScopeLine(id: 4, x: 0.2, y: 0.6)]
            ]
        )
        let current = VectorScopeSnapshot(
            inputState: .stereo,
            points: [VectorScopePoint(id: 4, x: 0.3, y: 0.4)],
            polarSamplePoints: [VectorScopePoint(id: 5, x: 0.4, y: 0.5)],
            polarLevelLinesByDetectionMode: [
                .rms: [VectorScopeLine(id: 6, x: 0.2, y: 0.6)],
                .peak: [VectorScopeLine(id: 7, x: 0.3, y: 0.7)]
            ],
            updateDurationSeconds: 0.5
        )

        let merged = VectorScopeAnalyzer.merging(current, with: previous, generationID: 8)

        #expect(merged.points.count == 2)
        #expect(merged.polarSamplePoints.count == 2)
        #expect(merged.polarLevelLines.count == 2)
        #expect(merged.polarLevelLines(for: .peak).count == 2)
        #expect(merged.points.contains { $0.age > 0 })
        #expect(merged.points.contains { $0.age == 0 })
        #expect(merged.points.contains { abs($0.age - (0.5 / VectorScopeAnalyzer.historyDurationSeconds)) < 0.000_001 })
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
    func resetVectorScopeHistoryClearsActiveSnapshotOnly() {
        let controller = AudioPreviewController()
        controller.activeTarget = .input
        controller.cardState(for: .input).vectorScopeSnapshot = VectorScopeSnapshot(
            inputState: .stereo,
            points: [VectorScopePoint(id: 0, x: 0.2, y: 0.4)],
            polarSamplePoints: [VectorScopePoint(id: 1, x: 0.2, y: 0.4)],
            polarLevelLines: [VectorScopeLine(id: 2, x: 0.1, y: 0.5)]
        )
        controller.cardState(for: .corrected).vectorScopeSnapshot = VectorScopeSnapshot(
            inputState: .stereo,
            points: [VectorScopePoint(id: 3, x: 0.2, y: 0.4)]
        )

        controller.resetVectorScopeHistory()

        #expect(controller.cardState(for: .input).vectorScopeSnapshot.inputState == .stereo)
        #expect(controller.cardState(for: .input).vectorScopeSnapshot.points.isEmpty)
        #expect(controller.cardState(for: .input).vectorScopeSnapshot.polarSamplePoints.isEmpty)
        #expect(controller.cardState(for: .input).vectorScopeSnapshot.polarLevelLines.isEmpty)
        #expect(controller.cardState(for: .input).vectorScopeSnapshot.polarLevelLines(for: .peak).isEmpty)
        #expect(controller.cardState(for: .corrected).vectorScopeSnapshot.points.isEmpty == false)
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

    private struct ComparisonPreviewFixture {
        let directory: URL
        let inputURL: URL
        let correctedURL: URL
        let inputDuration: TimeInterval
        let correctedDuration: TimeInterval
    }

    private func previewSnapshot(
        duration: TimeInterval,
        spectrumLevels: [Double] = []
    ) -> AudioPreviewSnapshot {
        AudioPreviewSnapshot(
            waveform: [.zero, .symmetric(0.5), .zero],
            duration: duration,
            bandLevels: [:],
            bandLevelDBs: [:],
            realtimeSpectrumTimeline: spectrumLevels.map { level in
                [
                    RealtimeSpectrumPoint(
                        id: "1000",
                        frequencyHz: 1_000,
                        levelDB: level
                    )
                ]
            }
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

    private func configureComparisonFixture(
        _ fixture: ComparisonPreviewFixture,
        controller: AudioPreviewController
    ) {
        controller.setPreviewSnapshot(
            previewSnapshot(duration: fixture.inputDuration),
            for: .input,
            sourceURL: fixture.inputURL
        )
        controller.setPreviewSnapshot(
            previewSnapshot(duration: fixture.correctedDuration),
            for: .corrected,
            sourceURL: fixture.correctedURL
        )
        controller.setPreviewSnapshot(
            previewSnapshot(duration: fixture.inputDuration),
            for: .mastered,
            sourceURL: fixture.inputURL
        )
    }

    private func waitForCorrelation(
        controller: AudioPreviewController,
        target: AudioPreviewTarget,
        satisfying predicate: (Double) -> Bool
    ) async throws -> Double {
        for _ in 0..<100 {
            if
                let correlation = controller.cardState(for: target).vectorScopeSnapshot.correlation,
                predicate(correlation)
            {
                return correlation
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try #require(controller.cardState(for: target).vectorScopeSnapshot.correlation)
    }

    private func waitForTruePeak(
        controller: AudioPreviewController,
        target: AudioPreviewTarget
    ) async throws -> Double {
        for _ in 0..<100 {
            if let truePeak = controller.cardState(for: target).liveLoudnessMeterSnapshot.truePeakDBTP {
                return truePeak
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try #require(controller.cardState(for: target).liveLoudnessMeterSnapshot.truePeakDBTP)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(10),
        _ predicate: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if predicate() {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }
        return predicate()
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

    private func stereoBuffer(samples: [(Float, Float)]) -> AVAudioPCMBuffer {
        let sampleRate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channels = buffer.floatChannelData!
        for (index, sample) in samples.enumerated() {
            channels[0][index] = sample.0
            channels[1][index] = sample.1
        }
        return buffer
    }

    private func makePreviewFixture(duration: TimeInterval = 0.1) throws -> PreviewFixture {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appending(path: "preview.wav")
        let sampleRate = 44_100.0
        let sampleCount = max(Int((sampleRate * duration).rounded()), 1)
        let samples = (0..<sampleCount).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.1)
        }
        try AudioFileService.saveAudio(AudioSignal(channels: [samples], sampleRate: sampleRate), to: sourceURL)
        return PreviewFixture(directory: tempDirectory, url: sourceURL)
    }

    private func makeComparisonPreviewFixture(
        duration: TimeInterval,
        correctedDuration: TimeInterval? = nil,
        inputChannelCount: Int = 2
    ) throws -> ComparisonPreviewFixture {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appending(path: "input.wav")
        let correctedURL = tempDirectory.appending(path: "corrected.wav")
        let inputSampleRate = 44_100.0
        let correctedSampleRate = 48_000.0
        let resolvedCorrectedDuration = correctedDuration ?? duration
        let inputSamples = (0..<max(Int((inputSampleRate * duration).rounded()), 1)).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / inputSampleRate) * 0.1)
        }
        let correctedSamples = (0..<max(Int((correctedSampleRate * resolvedCorrectedDuration).rounded()), 1)).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / correctedSampleRate) * 0.1)
        }
        let inputChannels = Array(repeating: inputSamples, count: max(inputChannelCount, 1))
        try AudioFileService.saveAudio(
            AudioSignal(channels: inputChannels, sampleRate: inputSampleRate),
            to: inputURL
        )
        try AudioFileService.saveAudio(
            AudioSignal(
                channels: [correctedSamples, correctedSamples.map(-)],
                sampleRate: correctedSampleRate
            ),
            to: correctedURL
        )
        return ComparisonPreviewFixture(
            directory: tempDirectory,
            inputURL: inputURL,
            correctedURL: correctedURL,
            inputDuration: duration,
            correctedDuration: resolvedCorrectedDuration
        )
    }
}
