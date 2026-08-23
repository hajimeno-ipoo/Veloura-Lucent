import AVFoundation
import Accelerate
import Foundation

enum AudioPreviewTarget: String, CaseIterable {
    case input = "入力"
    case corrected = "補正後"
    case mastered = "最終版"
}

enum AudioPlaybackState {
    case stopped
    case paused
    case playing
}

private enum PreparedComparisonSwitchResult {
    case switched
    case targetEnded
    case unavailable
}

struct AudioPreviewPlaybackDiagnosticState {
    let engineIdentifier: ObjectIdentifier?
    let engineIsRunning: Bool
    let playerNodeIdentifiers: [AudioPreviewTarget: ObjectIdentifier]
    let playerNodeIsPlaying: [AudioPreviewTarget: Bool]
    let playerNodeVolumes: [AudioPreviewTarget: Float]
    let playbackSessionID: UUID
    let analysisTarget: AudioPreviewTarget?
    let analysisID: UUID
    let completedTargets: Set<AudioPreviewTarget>
    let analysisOutputSampleRate: Double?
    let analysisOutputChannelCount: AVAudioChannelCount?
}

@MainActor
@Observable
final class AudioPreviewCardState {
    let target: AudioPreviewTarget
    var sourceURL: URL?
    var snapshot: AudioPreviewSnapshot?
    var liveBandLevels: [LiveBandSample] = []
    var realtimeSpectrum: [RealtimeSpectrumPoint] = []
    var vectorScopeSnapshot = VectorScopeSnapshot.unavailable
    var liveLoudnessMeterSnapshot = LiveLoudnessMeterSnapshot.unavailable
    var playbackProgress: Double = 0
    var playbackPosition: TimeInterval = 0
    var playbackState: AudioPlaybackState = .stopped

    init(target: AudioPreviewTarget) {
        self.target = target
    }
}

@MainActor
@Observable
final class AudioPreviewController {
    var activeTarget: AudioPreviewTarget?
    var playbackLabel = "未再生"
    var playbackVolume: Float = 1.0
    var comparisonPair: AudioComparisonPair = .inputVsCorrected
    var activeComparisonSide: AudioComparisonSide = .a
    var isLoudnessMatchedComparisonEnabled = false
    let inputCardState = AudioPreviewCardState(target: .input)
    let correctedCardState = AudioPreviewCardState(target: .corrected)
    let masteredCardState = AudioPreviewCardState(target: .mastered)

    var previewSnapshots: [AudioPreviewTarget: AudioPreviewSnapshot] {
        Dictionary(uniqueKeysWithValues: AudioPreviewTarget.allCases.compactMap { target in
            guard let snapshot = cardState(for: target).snapshot else { return nil }
            return (target, snapshot)
        })
    }

    var liveBandLevels: [AudioPreviewTarget: [LiveBandSample]] {
        Dictionary(uniqueKeysWithValues: AudioPreviewTarget.allCases.map { target in
            (target, cardState(for: target).liveBandLevels)
        })
    }

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var analysisMixer: AVAudioMixerNode?
    private var activeAudioFile: AVAudioFile?
    private var comparisonPlayerNodes: [AudioPreviewTarget: AVAudioPlayerNode] = [:]
    private var comparisonAnalysisMixers: [AudioPreviewTarget: AVAudioMixerNode] = [:]
    private var comparisonAudioFiles: [AudioPreviewTarget: AVAudioFile] = [:]
    private var comparisonPlaybackDurations: [AudioPreviewTarget: TimeInterval] = [:]
    private var completedComparisonTargets: Set<AudioPreviewTarget> = []
    private var activePlaybackStartTime: TimeInterval = 0
    private var activePlaybackDuration: TimeInterval = 0
    private var activePlaybackID = UUID()
    private var activeAnalysisID = UUID()
    private var activeAnalysisTarget: AudioPreviewTarget?
    private var hasInstalledAnalysisTap = false
    private var meterTimer: Timer?
    private var previewTasks: [AudioPreviewTarget: Task<Void, Never>] = [:]
    private var integratedLoudnessByTarget: [AudioPreviewTarget: Float] = [:]
    private var vectorScopeHistoryCounters: [AudioPreviewTarget: Int] = [:]
    private let realtimeAnalysisQueue = DispatchQueue(
        label: "com.codex.VelouraLucent.realtimeAnalysis",
        qos: .userInitiated
    )
    private let meterInterval: TimeInterval = 0.05
    private let smoothingFactor = 0.25

    func startPlayback(for url: URL?, target: AudioPreviewTarget) {
        guard let url else { return }

        if activeTarget == target, let playerNode, playerNode.isPlaying {
            return
        }

        switch switchToPreparedComparisonTargetIfPossible(target, sourceURL: url) {
        case .switched:
            return
        case .targetEnded:
            finishActivePlayback()
            return
        case .unavailable:
            break
        }

        do {
            preparePreview(for: url, target: target)
            syncComparisonPositionIfNeeded(for: target)
            transitionAwayFromCurrentTarget(keepingPosition: true)
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            let targetState = cardState(for: target)
            let resumeTime = min(targetState.playbackPosition, max(duration - 0.05, 0))
            let playbackStartTime: TimeInterval
            if let comparisonFiles = loadComparisonAudioFiles(activeAudioFile: audioFile, activeTarget: target) {
                playbackStartTime = try prepareComparisonEnginePlayback(
                    audioFiles: comparisonFiles,
                    target: target,
                    startTime: resumeTime
                )
            } else {
                playbackStartTime = try prepareEnginePlayback(
                    audioFile: audioFile,
                    target: target,
                    startTime: resumeTime,
                    duration: duration
                )
            }
            targetState.playbackState = .playing
            updatePlaybackLabel(for: target)
            synchronizePlaybackPositions(to: playbackStartTime, updatesLiveBandLevels: false)
            updateComparisonSpectra(at: playbackStartTime)
            startMetering(target: target)
            playPreparedNodes()
        } catch {
            stopActivePlaybackEngine()
            activeTarget = nil
            stopPlayback(target: target)
            playbackLabel = "再生できませんでした"
        }
    }

    func playComparisonSide(_ side: AudioComparisonSide) {
        activeComparisonSide = side
        let target = comparisonTarget(for: side)
        startPlayback(for: cardState(for: target).sourceURL, target: target)
    }

    func toggleComparisonPlayback() {
        let target = comparisonTarget(for: activeComparisonSide)
        if activeTarget == target, cardState(for: target).playbackState == .playing {
            pausePlayback(target: target)
        } else {
            playComparisonSide(activeComparisonSide)
        }
    }

    var canToggleComparisonPlayback: Bool {
        let target = comparisonTarget(for: activeComparisonSide)
        return cardState(for: target).sourceURL != nil
    }

    var canToggleComparisonSide: Bool {
        comparisonPair.targets.allSatisfy { cardState(for: $0).sourceURL != nil }
    }

    var isComparisonPlaybackRunning: Bool {
        guard let activeTarget else { return false }
        return cardState(for: activeTarget).playbackState == .playing
    }

    func toggleComparisonSide() {
        let next: AudioComparisonSide = activeComparisonSide == .a ? .b : .a
        if isComparisonPlaybackRunning {
            playComparisonSide(next)
        } else {
            activeComparisonSide = next
        }
    }

    func setComparisonPair(_ pair: AudioComparisonPair) {
        guard pair != comparisonPair else { return }

        let previousActiveTarget = activeTarget
        let previousActiveSide = activeComparisonSide
        let preservedPosition = comparisonPositionForPairChange()
        let wasPlaying = previousActiveTarget.map {
            cardState(for: $0).playbackState == .playing
        } ?? false
        let wasPaused = previousActiveTarget.map {
            cardState(for: $0).playbackState == .paused
        } ?? false
        let previousSourceURL = previousActiveTarget.flatMap {
            cardState(for: $0).sourceURL
        }
        let preparedTargets = Set(comparisonPlayerNodes.keys)
        let needsPreparedPairRefresh = engine != nil
            && preparedTargets != Set(pair.targets)
        if
            let previousActiveTarget,
            !pair.targets.contains(previousActiveTarget) || needsPreparedPairRefresh
        {
            transitionAwayFromCurrentTarget(keepingPosition: true)
        }

        comparisonPair = pair
        if
            let previousActiveTarget,
            pair.targets.contains(previousActiveTarget),
            let newSide = comparisonSide(for: previousActiveTarget)
        {
            activeComparisonSide = newSide
        } else {
            activeComparisonSide = previousActiveSide
        }

        if let preservedPosition {
            synchronizePlaybackPositions(to: preservedPosition, updatesLiveBandLevels: true)
            updateComparisonSpectra(at: preservedPosition)
        } else {
            updateComparisonSpectra(at: nil)
        }

        if
            wasPlaying,
            let previousActiveTarget,
            pair.targets.contains(previousActiveTarget),
            let previousSourceURL
        {
            startPlayback(for: previousSourceURL, target: previousActiveTarget)
        } else if
            wasPaused,
            needsPreparedPairRefresh,
            let previousActiveTarget,
            pair.targets.contains(previousActiveTarget)
        {
            activeTarget = previousActiveTarget
            cardState(for: previousActiveTarget).playbackState = .paused
            playbackLabel = "\(previousActiveTarget.rawValue)を一時停止中"
        } else {
            refreshPlaybackVolumeIfNeeded()
        }
    }

    func setLoudnessMatchedComparisonEnabled(_ isEnabled: Bool) {
        isLoudnessMatchedComparisonEnabled = isEnabled
        refreshPlaybackVolumeIfNeeded()
    }

    func setPlaybackVolume(_ volume: Float) {
        playbackVolume = min(max(volume, 0), 1)
        refreshPlaybackVolumeIfNeeded()
    }

    func seek(to progress: Double, target: AudioPreviewTarget) {
        guard let sourceSnapshot = cardState(for: target).snapshot, sourceSnapshot.duration > 0 else {
            return
        }

        let requestedTime = sourceSnapshot.duration * min(max(progress, 0), 1)

        synchronizePlaybackPositions(to: requestedTime, updatesLiveBandLevels: true)
        if activeTarget != nil {
            updateComparisonSpectra(at: requestedTime)
        }

        guard let activeTarget, playerNode != nil else { return }
        let activeState = cardState(for: activeTarget)
        guard let url = activeState.sourceURL else { return }
        let wasPlaying = activeState.playbackState == .playing
        stopActivePlaybackEngine()
        activeState.playbackPosition = min(requestedTime, snapshot(for: activeTarget).duration)
        activeState.playbackProgress = snapshot(for: activeTarget).duration > 0 ? activeState.playbackPosition / snapshot(for: activeTarget).duration : 0
        if wasPlaying {
            startPlayback(for: url, target: activeTarget)
        }
    }

    func comparisonTarget(for side: AudioComparisonSide) -> AudioPreviewTarget {
        switch side {
        case .a:
            return comparisonPair.firstTarget
        case .b:
            return comparisonPair.secondTarget
        }
    }

    func comparisonSide(for target: AudioPreviewTarget) -> AudioComparisonSide? {
        if comparisonPair.firstTarget == target {
            return .a
        }
        if comparisonPair.secondTarget == target {
            return .b
        }
        return nil
    }

    func isInComparisonPair(_ target: AudioPreviewTarget) -> Bool {
        comparisonPair.targets.contains(target)
    }

    func pausePlayback(target: AudioPreviewTarget) {
        guard activeTarget == target else { return }
        let targetState = cardState(for: target)
        guard let playerNode else { return }
        let currentTime = currentPlaybackPosition()
        synchronizePlaybackPositions(to: currentTime, updatesLiveBandLevels: false)
        updateComparisonSpectra(at: currentTime)
        meterTimer?.invalidate()
        meterTimer = nil
        if comparisonPlayerNodes.isEmpty {
            playerNode.pause()
        } else {
            comparisonPlayerNodes.values.forEach { $0.pause() }
        }
        targetState.playbackState = .paused
        playbackLabel = "\(target.rawValue)を一時停止中"
    }

    func stopPlayback(target: AudioPreviewTarget? = nil) {
        let targetsToReset = target.map { [$0] } ?? AudioPreviewTarget.allCases
        guard !targetsToReset.isEmpty else {
            playbackLabel = "停止中"
            return
        }

        if target == nil || activeTarget == target {
            meterTimer?.invalidate()
            meterTimer = nil
            stopActivePlaybackEngine()
            activeTarget = nil
        }

        for targetToReset in targetsToReset {
            let state = cardState(for: targetToReset)
            state.playbackPosition = 0
            state.playbackProgress = 0
            state.playbackState = .stopped
            state.realtimeSpectrum = []
            state.vectorScopeSnapshot = .unavailable
            state.liveLoudnessMeterSnapshot = .unavailable
            vectorScopeHistoryCounters[targetToReset] = nil
            if let snapshot = state.snapshot {
                state.liveBandLevels = makeInitialLiveBandLevels(from: snapshot, target: targetToReset)
            }
        }
        playbackLabel = "停止中"
    }

    func preparePreview(for url: URL?, target: AudioPreviewTarget, measureLoudness: Bool = true) {
        previewTasks[target]?.cancel()

        guard let url else {
            clearPreviewState(for: target)
            return
        }

        let targetState = cardState(for: target)
        if targetState.sourceURL == url, targetState.snapshot != nil {
            if measureLoudness, integratedLoudnessByTarget[target] == nil {
                prepareLoudness(for: url, target: target)
            }
            return
        }

        targetState.sourceURL = url
        targetState.snapshot = nil
        targetState.liveBandLevels = []
        targetState.realtimeSpectrum = []
        targetState.vectorScopeSnapshot = .unavailable
        targetState.liveLoudnessMeterSnapshot = .unavailable
        vectorScopeHistoryCounters[target] = nil
        integratedLoudnessByTarget[target] = nil

        previewTasks[target] = Task {
            let preview = try? await Task.detached(priority: .utility) {
                let signal = try AudioFileService.loadAudio(from: url)
                async let snapshot = AudioFileService.makePreviewSnapshot(from: signal)
                async let loudness: Float? = measureLoudness ? MasteringAnalysisService.integratedLoudness(signal: signal) : nil
                return await (snapshot, loudness)
            }.value

            guard !Task.isCancelled else { return }
            guard self.cardState(for: target).sourceURL == url else { return }
            if let preview {
                if let loudness = preview.1 {
                    integratedLoudnessByTarget[target] = loudness
                }
                setPreviewSnapshot(preview.0, for: target, sourceURL: url)
            }
            previewTasks[target] = nil
        }
    }

    func preparePreviewPlaceholder(for url: URL?, target: AudioPreviewTarget) {
        previewTasks[target]?.cancel()
        guard let url else {
            clearPreviewState(for: target)
            return
        }

        let targetState = cardState(for: target)
        targetState.sourceURL = url
        targetState.snapshot = nil
        targetState.liveBandLevels = []
        targetState.realtimeSpectrum = []
        targetState.vectorScopeSnapshot = .unavailable
        targetState.liveLoudnessMeterSnapshot = .unavailable
        vectorScopeHistoryCounters[target] = nil
        integratedLoudnessByTarget[target] = nil
        targetState.playbackPosition = 0
        targetState.playbackProgress = 0
        targetState.playbackState = .stopped
        if activeTarget == target {
            stopActivePlaybackEngine()
            activeTarget = nil
        } else if comparisonPlayerNodes[target] != nil {
            transitionAwayFromCurrentTarget(keepingPosition: true)
        }
        previewTasks[target] = nil
    }

    private func prepareLoudness(for url: URL, target: AudioPreviewTarget) {
        previewTasks[target] = Task {
            let loudness = try? await Task.detached(priority: .utility) {
                let signal = try AudioFileService.loadAudio(from: url)
                return MasteringAnalysisService.integratedLoudness(signal: signal)
            }.value

            guard !Task.isCancelled else { return }
            guard self.cardState(for: target).sourceURL == url else { return }
            if let loudness {
                integratedLoudnessByTarget[target] = loudness
                refreshPlaybackVolumeIfNeeded()
            }
            previewTasks[target] = nil
        }
    }

    private func clearPreviewState(for target: AudioPreviewTarget) {
        previewTasks[target] = nil
        let targetState = cardState(for: target)
        targetState.sourceURL = nil
        targetState.snapshot = nil
        targetState.liveBandLevels = []
        targetState.realtimeSpectrum = []
        targetState.vectorScopeSnapshot = .unavailable
        targetState.liveLoudnessMeterSnapshot = .unavailable
        vectorScopeHistoryCounters[target] = nil
        integratedLoudnessByTarget[target] = nil
        targetState.playbackPosition = 0
        targetState.playbackProgress = 0
        targetState.playbackState = .stopped
        if activeTarget == target {
            stopActivePlaybackEngine()
            activeTarget = nil
        } else if comparisonPlayerNodes[target] != nil {
            transitionAwayFromCurrentTarget(keepingPosition: true)
        }
    }

    func setPreviewSnapshot(_ snapshot: AudioPreviewSnapshot, for target: AudioPreviewTarget, sourceURL: URL, integratedLoudnessLUFS: Double? = nil) {
        let targetState = cardState(for: target)
        targetState.sourceURL = sourceURL
        targetState.snapshot = snapshot
        targetState.playbackProgress = normalizedProgress(for: target, duration: snapshot.duration)
        targetState.liveBandLevels = makeInitialLiveBandLevels(from: snapshot, target: target)
        if targetState.playbackState == .stopped {
            targetState.realtimeSpectrum = []
            targetState.vectorScopeSnapshot = .unavailable
            targetState.liveLoudnessMeterSnapshot = .unavailable
            vectorScopeHistoryCounters[target] = nil
        }
        if let integratedLoudnessLUFS {
            setIntegratedLoudnessLUFS(integratedLoudnessLUFS, for: target)
        }
    }

    func setIntegratedLoudnessLUFS(_ loudness: Double, for target: AudioPreviewTarget) {
        integratedLoudnessByTarget[target] = Float(loudness)
        refreshPlaybackVolumeIfNeeded()
    }

    func integratedLoudnessLUFS(for target: AudioPreviewTarget) -> Float? {
        integratedLoudnessByTarget[target]
    }

    func durationText(for target: AudioPreviewTarget) -> String {
        if let snapshot = cardState(for: target).snapshot, snapshot.duration > 0 {
            return format(duration: snapshot.duration)
        }
        return "--:--"
    }

    func playbackTimeText(for target: AudioPreviewTarget) -> String {
        let targetState = cardState(for: target)
        guard let snapshot = targetState.snapshot, snapshot.duration > 0 else {
            return "--:-- / --:--"
        }

        let elapsed: TimeInterval
        if activeTarget == target {
            elapsed = currentPlaybackPosition()
        } else {
            elapsed = targetState.playbackPosition
        }

        return "\(format(duration: elapsed)) / \(format(duration: snapshot.duration))"
    }

    func snapshot(for target: AudioPreviewTarget) -> AudioPreviewSnapshot {
        cardState(for: target).snapshot ?? AudioPreviewSnapshot(
            waveform: Array(repeating: .zero, count: AudioFileService.waveformPreviewBucketCount),
            duration: 0,
            bandLevels: Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map { ($0.id, Array(repeating: 0, count: AudioFileService.previewBucketCount)) }),
            bandLevelDBs: Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map { ($0.id, Array(repeating: Float(-120), count: AudioFileService.previewBucketCount)) })
        )
    }

    func finishActivePlayback() {
        guard activeTarget != nil else { return }
        stopPlayback()
    }

    func resetVectorScopeHistory() {
        guard let activeTarget else { return }
        let currentState = cardState(for: activeTarget).vectorScopeSnapshot.inputState
        cardState(for: activeTarget).vectorScopeSnapshot = VectorScopeSnapshot(inputState: currentState)
        vectorScopeHistoryCounters[activeTarget] = nil
    }

    private func startMetering(target: AudioPreviewTarget) {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: meterInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateMeters(target: target)
            }
        }
    }

    private func updateMeters(target: AudioPreviewTarget) {
        guard playerNode != nil else { return }

        if activePlaybackDuration > 0 {
            let currentPosition = currentPlaybackPosition()
            synchronizePlaybackPositions(to: currentPosition, updatesLiveBandLevels: false)
            updateComparisonSpectra(at: currentPosition)
        }

        let snapshot = snapshot(for: target)
        let bucketIndex = bandBucketIndex(
            for: cardState(for: target).playbackProgress,
            snapshot: snapshot
        )

        if let sharedLevels = sharedComparisonLevels(for: target, bucketIndex: bucketIndex) {
            let targetState = cardState(for: target)
            let previousLevels = Dictionary(uniqueKeysWithValues: targetState.liveBandLevels.map { ($0.id, $0.level) })
            targetState.liveBandLevels = sharedLevels.map { sample in
                let previousLevel = previousLevels[sample.id] ?? sample.level
                let smoothedLevel = previousLevel + (sample.level - previousLevel) * smoothingFactor
                return LiveBandSample(id: sample.id, label: sample.label, level: smoothedLevel)
            }
            return
        }

        let targetState = cardState(for: target)
        let previousLevels = Dictionary(uniqueKeysWithValues: targetState.liveBandLevels.map { ($0.id, $0.level) })
        targetState.liveBandLevels = AudioBandCatalog.previewBands.map { band in
            let targetLevel = Double(snapshot.bandLevels[band.id]?[bucketIndex] ?? 0)
            let previousLevel = previousLevels[band.id] ?? targetLevel
            let smoothedLevel = previousLevel + (targetLevel - previousLevel) * smoothingFactor
            return LiveBandSample(id: band.id, label: band.label, level: smoothedLevel)
        }
    }

    private func sharedComparisonLevels(for target: AudioPreviewTarget, bucketIndex: Int) -> [LiveBandSample]? {
        guard isInComparisonPair(target) else {
            return nil
        }
        let comparisonTarget = comparisonPair.firstTarget == target ? comparisonPair.secondTarget : comparisonPair.firstTarget
        let targetSnapshot = cardState(for: target).snapshot
        let comparisonSnapshot = cardState(for: comparisonTarget).snapshot
        guard
            let targetSnapshot,
            let comparisonSnapshot,
            targetSnapshot.duration > 0,
            comparisonSnapshot.duration > 0
        else {
            return nil
        }

        var nextLevels: [LiveBandSample] = []

        for band in AudioBandCatalog.previewBands {
            let targetDB = bandLevelDB(from: targetSnapshot, bandID: band.id, bucketIndex: bucketIndex)
            let comparisonDB = bandLevelDB(from: comparisonSnapshot, bandID: band.id, bucketIndex: bucketIndex)
            let levels = normalizePair(primaryDB: targetDB, comparisonDB: comparisonDB)

            nextLevels.append(
                LiveBandSample(
                    id: band.id,
                    label: band.label,
                    level: levels.primary
                )
            )
        }

        return nextLevels
    }

    private func bandLevelDB(from snapshot: AudioPreviewSnapshot, bandID: String, bucketIndex: Int) -> Double {
        guard let levels = snapshot.bandLevelDBs[bandID], !levels.isEmpty else {
            return -120
        }
        let safeIndex = min(max(bucketIndex, 0), levels.count - 1)
        return Double(levels[safeIndex])
    }

    private func normalizePair(primaryDB: Double, comparisonDB: Double) -> (primary: Double, comparison: Double) {
        let peak = max(primaryDB, comparisonDB)
        let ceiling = max(-12.0, peak + 6.0)
        let floor = max(-84.0, ceiling - 30.0)
        let span = max(ceiling - floor, 1.0)

        func normalize(_ value: Double) -> Double {
            let clamped = max(0, min(1, (value - floor) / span))
            return pow(clamped, 0.72)
        }

        return (normalize(primaryDB), normalize(comparisonDB))
    }

    private func storeCurrentPlaybackPosition() {
        guard let activeTarget, playerNode != nil else { return }
        let targetState = cardState(for: activeTarget)
        let currentTime = currentPlaybackPosition()
        targetState.playbackPosition = currentTime
        targetState.playbackProgress = activePlaybackDuration > 0 ? max(0, min(1, currentTime / activePlaybackDuration)) : 0
    }

    private func makeInitialLiveBandLevels(from snapshot: AudioPreviewSnapshot, target: AudioPreviewTarget) -> [LiveBandSample] {
        let bucketIndex: Int
        if snapshot.duration > 0 {
            let progress = min(max(cardState(for: target).playbackPosition / snapshot.duration, 0), 1)
            bucketIndex = bandBucketIndex(for: progress, snapshot: snapshot)
        } else {
            bucketIndex = 0
        }

        return AudioBandCatalog.previewBands.map { band in
            let level = Double(snapshot.bandLevels[band.id]?[bucketIndex] ?? 0)
            return LiveBandSample(id: band.id, label: band.label, level: level)
        }
    }

    private func bandBucketIndex(
        for progress: Double,
        snapshot: AudioPreviewSnapshot
    ) -> Int {
        let bucketCount = snapshot.bandLevels.values.first?.count
            ?? snapshot.bandLevelDBs.values.first?.count
            ?? 0
        guard bucketCount > 0 else { return 0 }
        return min(
            max(Int(round(min(max(progress, 0), 1) * Double(bucketCount - 1))), 0),
            bucketCount - 1
        )
    }

    private func synchronizePlaybackPositions(to requestedTime: TimeInterval, updatesLiveBandLevels: Bool) {
        for target in AudioPreviewTarget.allCases {
            guard let snapshot = cardState(for: target).snapshot, snapshot.duration > 0 else {
                continue
            }

            let state = cardState(for: target)
            state.playbackPosition = min(max(requestedTime, 0), snapshot.duration)
            state.playbackProgress = state.playbackPosition / snapshot.duration
            if updatesLiveBandLevels {
                state.liveBandLevels = makeInitialLiveBandLevels(from: snapshot, target: target)
            }
        }
    }

    private func updateComparisonSpectra(at requestedTime: TimeInterval?) {
        for target in AudioPreviewTarget.allCases {
            let state = cardState(for: target)
            guard
                comparisonPair.targets.contains(target),
                let requestedTime,
                let snapshot = state.snapshot,
                snapshot.duration > 0,
                !snapshot.realtimeSpectrumTimeline.isEmpty
            else {
                if !state.realtimeSpectrum.isEmpty {
                    state.realtimeSpectrum = []
                }
                continue
            }

            let progress = min(max(requestedTime / snapshot.duration, 0), 1)
            let frameIndex = min(
                max(Int((progress * Double(snapshot.realtimeSpectrumTimeline.count - 1)).rounded()), 0),
                snapshot.realtimeSpectrumTimeline.count - 1
            )
            let nextSpectrum = snapshot.realtimeSpectrumTimeline[frameIndex]
            if state.realtimeSpectrum != nextSpectrum {
                state.realtimeSpectrum = nextSpectrum
            }
        }
    }

    func playbackProgress(for target: AudioPreviewTarget) -> Double {
        if activeTarget == target, activePlaybackDuration > 0 {
            return max(0, min(1, currentPlaybackPosition() / activePlaybackDuration))
        }
        return cardState(for: target).playbackProgress
    }

    func playbackState(for target: AudioPreviewTarget) -> AudioPlaybackState {
        cardState(for: target).playbackState
    }

    private func transitionAwayFromCurrentTarget(keepingPosition: Bool) {
        guard let activeTarget else { return }
        let activeState = cardState(for: activeTarget)
        clearRealtimeVisualSnapshots()
        if keepingPosition {
            storeCurrentPlaybackPosition()
            activeState.playbackState = .paused
        } else {
            activeState.playbackPosition = 0
            activeState.playbackProgress = 0
            activeState.playbackState = .stopped
        }
        meterTimer?.invalidate()
        meterTimer = nil
        stopActivePlaybackEngine()
        self.activeTarget = nil
    }

    private func refreshPlaybackVolumeIfNeeded() {
        guard let activeTarget else { return }
        if let activePlayerNode = comparisonPlayerNodes[activeTarget] {
            // Make the next side audible before muting the previous side so the
            // A/B command never creates a silent interval between assignments.
            activePlayerNode.volume = effectivePlaybackVolume(for: activeTarget)
            for (target, node) in comparisonPlayerNodes where target != activeTarget {
                node.volume = 0
            }
        } else {
            playerNode?.volume = effectivePlaybackVolume(for: activeTarget)
        }
    }

    private func effectivePlaybackVolume(for target: AudioPreviewTarget) -> Float {
        playbackVolume * comparisonPlaybackGain(for: target)
    }

    private func comparisonPlaybackGain(for target: AudioPreviewTarget) -> Float {
        guard isLoudnessMatchedComparisonEnabled, isInComparisonPair(target) else {
            return 1.0
        }

        let pairedTarget = comparisonPair.firstTarget == target ? comparisonPair.secondTarget : comparisonPair.firstTarget
        guard
            let currentLoudness = integratedLoudnessByTarget[target],
            let pairedLoudness = integratedLoudnessByTarget[pairedTarget]
        else {
            return 1.0
        }

        // Match by attenuating the louder side only, so comparison playback stays safe.
        let targetLoudness = min(currentLoudness, pairedLoudness)
        let attenuationDB = min(0, targetLoudness - currentLoudness)
        return max(0.1, min(1.0, powf(10, attenuationDB / 20)))
    }

    private func syncComparisonPositionIfNeeded(for target: AudioPreviewTarget) {
        guard isInComparisonPair(target) else { return }

        if let activeTarget, isInComparisonPair(activeTarget), activeTarget != target {
            let currentTime = playerNode == nil ? cardState(for: activeTarget).playbackPosition : currentPlaybackPosition()
            synchronizePlaybackPositions(to: currentTime, updatesLiveBandLevels: false)
            return
        }

        let targetPosition = cardState(for: target).playbackPosition
        if targetPosition > 0 {
            synchronizePlaybackPositions(to: targetPosition, updatesLiveBandLevels: false)
            return
        }

        let pairedTarget = comparisonPair.firstTarget == target ? comparisonPair.secondTarget : comparisonPair.firstTarget
        let pairedPosition = cardState(for: pairedTarget).playbackPosition
        if pairedPosition > 0 {
            synchronizePlaybackPositions(to: pairedPosition, updatesLiveBandLevels: false)
        }
    }

    private func switchToPreparedComparisonTargetIfPossible(
        _ target: AudioPreviewTarget,
        sourceURL: URL
    ) -> PreparedComparisonSwitchResult {
        guard
            let previousTarget = activeTarget,
            previousTarget != target,
            isInComparisonPair(previousTarget),
            isInComparisonPair(target),
            engine?.isRunning == true,
            comparisonPair.targets.allSatisfy({ comparisonAudioFiles[$0]?.url == cardState(for: $0).sourceURL }),
            comparisonAudioFiles[target]?.url == sourceURL,
            let nextAudioFile = comparisonAudioFiles[target],
            let nextDuration = comparisonPlaybackDurations[target]
        else {
            return .unavailable
        }

        let currentTime = currentPlaybackPosition()
        synchronizePlaybackPositions(to: currentTime, updatesLiveBandLevels: false)
        let endTolerance = 1 / max(nextAudioFile.processingFormat.sampleRate, 1)
        if completedComparisonTargets.contains(target) || currentTime >= nextDuration - endTolerance {
            return .targetEnded
        }
        guard
            let nextPlayerNode = comparisonPlayerNodes[target],
            nextPlayerNode.isPlaying
        else {
            return .unavailable
        }
        cardState(for: previousTarget).playbackState = .paused

        activeTarget = target
        playerNode = nextPlayerNode
        activeAudioFile = nextAudioFile
        activePlaybackDuration = nextDuration
        cardState(for: target).playbackState = .playing
        if let comparisonSide = comparisonSide(for: target) {
            activeComparisonSide = comparisonSide
        }

        refreshPlaybackVolumeIfNeeded()
        replaceRealtimeAnalysisTap(for: target)
        updateComparisonSpectra(at: currentTime)
        startMetering(target: target)
        updatePlaybackLabel(for: target)
        return .switched
    }

    private func updatePlaybackLabel(for target: AudioPreviewTarget) {
        if let comparisonSide = comparisonSide(for: target) {
            activeComparisonSide = comparisonSide
            playbackLabel = "\(comparisonPair.title(for: comparisonSide)) \(target.rawValue)を再生中"
        } else {
            playbackLabel = "\(target.rawValue)を再生中"
        }
    }

    private func loadComparisonAudioFiles(
        activeAudioFile: AVAudioFile,
        activeTarget: AudioPreviewTarget
    ) -> [AudioPreviewTarget: AVAudioFile]? {
        guard isInComparisonPair(activeTarget) else { return nil }

        var audioFiles = [activeTarget: activeAudioFile]
        for target in comparisonPair.targets where target != activeTarget {
            guard
                let url = cardState(for: target).sourceURL,
                let audioFile = try? AVAudioFile(forReading: url)
            else {
                return nil
            }
            audioFiles[target] = audioFile
        }
        return audioFiles.count == comparisonPair.targets.count ? audioFiles : nil
    }

    private func comparisonPositionForPairChange() -> TimeInterval? {
        if let activeTarget {
            let position = playerNode == nil ? cardState(for: activeTarget).playbackPosition : currentPlaybackPosition()
            if position > 0 {
                return position
            }
        }

        let selectedTarget = comparisonTarget(for: activeComparisonSide)
        let selectedPosition = cardState(for: selectedTarget).playbackPosition
        if selectedPosition > 0 {
            return selectedPosition
        }

        let otherSide: AudioComparisonSide = activeComparisonSide == .a ? .b : .a
        let otherTarget = comparisonTarget(for: otherSide)
        let otherPosition = cardState(for: otherTarget).playbackPosition
        return otherPosition > 0 ? otherPosition : nil
    }

    private func prepareComparisonEnginePlayback(
        audioFiles: [AudioPreviewTarget: AVAudioFile],
        target: AudioPreviewTarget,
        startTime: TimeInterval
    ) throws -> TimeInterval {
        let engine = AVAudioEngine()
        let playbackID = UUID()
        let durations = Dictionary(uniqueKeysWithValues: audioFiles.map { target, audioFile in
            (target, Double(audioFile.length) / audioFile.processingFormat.sampleRate)
        })
        let activeDuration = durations[target] ?? 0
        let safeStartTime = min(max(startTime, 0), max(activeDuration - 0.05, 0))
        var playerNodes: [AudioPreviewTarget: AVAudioPlayerNode] = [:]
        var analysisMixers: [AudioPreviewTarget: AVAudioMixerNode] = [:]
        var initiallyCompletedTargets: Set<AudioPreviewTarget> = []

        for (busIndex, comparisonTarget) in comparisonPair.targets.enumerated() {
            guard let audioFile = audioFiles[comparisonTarget] else { continue }
            let node = AVAudioPlayerNode()
            let sourceMixer = AVAudioMixerNode()
            let format = audioFile.processingFormat
            engine.attach(node)
            engine.attach(sourceMixer)
            engine.connect(
                node,
                to: sourceMixer,
                format: format
            )
            engine.connect(
                sourceMixer,
                to: engine.mainMixerNode,
                fromBus: 0,
                toBus: AVAudioNodeBus(busIndex),
                format: format
            )
            playerNodes[comparisonTarget] = node
            analysisMixers[comparisonTarget] = sourceMixer
        }

        guard let activeAnalysisMixer = analysisMixers[target] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        installRealtimeAnalysisTap(
            on: activeAnalysisMixer,
            target: target,
            sourceFormat: audioFiles[target]?.processingFormat
        )

        for comparisonTarget in comparisonPair.targets {
            guard
                let audioFile = audioFiles[comparisonTarget],
                let node = playerNodes[comparisonTarget]
            else {
                continue
            }
            let sampleRate = audioFile.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(safeStartTime * sampleRate)
            guard startFrame < audioFile.length else {
                initiallyCompletedTargets.insert(comparisonTarget)
                continue
            }
            let remainingFrames = max(AVAudioFramePosition(0), audioFile.length - startFrame)
            let frameCount = AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(UInt32.max)))
            node.scheduleSegment(
                audioFile,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishPlaybackIfCurrent(target: comparisonTarget, playbackID: playbackID)
                }
            }
        }

        try engine.start()

        self.engine = engine
        self.analysisMixer = activeAnalysisMixer
        comparisonPlayerNodes = playerNodes
        comparisonAnalysisMixers = analysisMixers
        comparisonAudioFiles = audioFiles
        comparisonPlaybackDurations = durations
        completedComparisonTargets = initiallyCompletedTargets
        activeTarget = target
        playerNode = playerNodes[target]
        activeAudioFile = audioFiles[target]
        activePlaybackStartTime = safeStartTime
        activePlaybackDuration = durations[target] ?? 0
        activePlaybackID = playbackID
        refreshPlaybackVolumeIfNeeded()
        return safeStartTime
    }

    private func prepareEnginePlayback(
        audioFile: AVAudioFile,
        target: AudioPreviewTarget,
        startTime: TimeInterval,
        duration: TimeInterval
    ) throws -> TimeInterval {
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let analysisMixer = AVAudioMixerNode()
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let safeStartTime = min(max(startTime, 0), max(duration - 0.05, 0))
        let startFrame = AVAudioFramePosition(safeStartTime * sampleRate)
        let remainingFrames = max(AVAudioFramePosition(0), audioFile.length - startFrame)
        let frameCount = AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(UInt32.max)))
        let playbackID = UUID()

        engine.attach(playerNode)
        engine.attach(analysisMixer)
        engine.connect(playerNode, to: analysisMixer, format: format)
        engine.connect(analysisMixer, to: engine.mainMixerNode, format: format)

        installRealtimeAnalysisTap(on: analysisMixer, target: target, sourceFormat: format)

        try engine.start()
        playerNode.volume = effectivePlaybackVolume(for: target)

        self.engine = engine
        self.playerNode = playerNode
        self.analysisMixer = analysisMixer
        self.activeAudioFile = audioFile
        activeTarget = target
        activePlaybackStartTime = safeStartTime
        activePlaybackDuration = duration
        activePlaybackID = playbackID

        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishPlaybackIfCurrent(target: target, playbackID: playbackID)
            }
        }
        return safeStartTime
    }

    private func playPreparedNodes() {
        guard !comparisonPlayerNodes.isEmpty else {
            playerNode?.play()
            return
        }

        let sharedStartTime = AVAudioTime(
            hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.02)
        )
        for target in comparisonPair.targets {
            guard !completedComparisonTargets.contains(target) else { continue }
            comparisonPlayerNodes[target]?.play(at: sharedStartTime)
        }
    }

    private func installRealtimeAnalysisTap(
        on mixer: AVAudioMixerNode,
        target: AudioPreviewTarget,
        sourceFormat: AVAudioFormat?
    ) {
        let analysisID = UUID()
        let outputFormat = mixer.outputFormat(forBus: 0)
        let sourceInputState = VectorScopeAnalyzer.inputState(
            forChannelCount: Int(sourceFormat?.channelCount ?? outputFormat.channelCount)
        )
        clearRealtimeVisualSnapshots()
        vectorScopeHistoryCounters[target] = nil
        cardState(for: target).vectorScopeSnapshot = VectorScopeSnapshot(
            inputState: sourceInputState,
            points: []
        )
        cardState(for: target).liveLoudnessMeterSnapshot = .unavailable

        let tapBufferSize = RealtimeSpectrumAnalyzer.tapBufferSize(for: outputFormat.sampleRate)
        RealtimeSpectrumTapInstaller.installTap(
            on: mixer,
            bufferSize: tapBufferSize,
            analysisFormat: outputFormat,
            analysisQueue: realtimeAnalysisQueue,
            controller: self,
            target: target,
            analysisID: analysisID
        )
        activeAnalysisID = analysisID
        activeAnalysisTarget = target
        hasInstalledAnalysisTap = true
    }

    private func replaceRealtimeAnalysisTap(for target: AudioPreviewTarget) {
        guard let nextAnalysisMixer = comparisonAnalysisMixers[target] ?? analysisMixer else { return }
        if hasInstalledAnalysisTap {
            analysisMixer?.removeTap(onBus: 0)
            hasInstalledAnalysisTap = false
        }
        analysisMixer = nextAnalysisMixer
        installRealtimeAnalysisTap(
            on: nextAnalysisMixer,
            target: target,
            sourceFormat: comparisonAudioFiles[target]?.processingFormat ?? activeAudioFile?.processingFormat
        )
    }

    fileprivate func storeVectorScopeSnapshot(
        _ snapshot: VectorScopeSnapshot,
        for target: AudioPreviewTarget,
        analysisID: UUID
    ) {
        guard acceptsRealtimeAnalysis(for: target, analysisID: analysisID) else { return }
        storeVectorScopeSnapshotIfPlaying(snapshot, for: target)
    }

    fileprivate func storeLiveLoudnessMeterSnapshot(
        _ snapshot: LiveLoudnessMeterSnapshot,
        for target: AudioPreviewTarget,
        analysisID: UUID
    ) {
        guard acceptsRealtimeAnalysis(for: target, analysisID: analysisID) else { return }
        storeLiveLoudnessMeterSnapshotIfPlaying(snapshot, for: target)
    }

    func acceptsRealtimeAnalysis(for target: AudioPreviewTarget, analysisID: UUID) -> Bool {
        activeTarget == target
            && activeAnalysisTarget == target
            && activeAnalysisID == analysisID
    }

    func storeVectorScopeSnapshotIfPlaying(
        _ snapshot: VectorScopeSnapshot,
        for target: AudioPreviewTarget
    ) {
        guard activeTarget == target, cardState(for: target).playbackState == .playing else { return }
        clearVectorScopeSnapshots(except: target)
        let state = cardState(for: target)
        let nextID = (vectorScopeHistoryCounters[target] ?? 0) + 1
        vectorScopeHistoryCounters[target] = nextID
        state.vectorScopeSnapshot = VectorScopeAnalyzer.merging(
            snapshot,
            with: state.vectorScopeSnapshot,
            generationID: nextID
        )
    }

    func storeLiveLoudnessMeterSnapshotIfPlaying(
        _ snapshot: LiveLoudnessMeterSnapshot,
        for target: AudioPreviewTarget
    ) {
        guard activeTarget == target, cardState(for: target).playbackState == .playing else { return }
        clearLiveLoudnessMeterSnapshots(except: target)
        cardState(for: target).liveLoudnessMeterSnapshot = snapshot
    }

    private func finishPlaybackIfCurrent(target: AudioPreviewTarget, playbackID: UUID) {
        guard activePlaybackID == playbackID else { return }
        if !comparisonPlayerNodes.isEmpty {
            completedComparisonTargets.insert(target)
        }
        guard activeTarget == target else { return }
        finishActivePlayback()
    }

    private func currentPlaybackPosition() -> TimeInterval {
        guard
            let playerNode,
            let nodeTime = playerNode.lastRenderTime,
            let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else {
            return activeTarget.map { cardState(for: $0).playbackPosition } ?? 0
        }
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        return min(max(activePlaybackStartTime + elapsed, 0), activePlaybackDuration)
    }

    private func stopActivePlaybackEngine() {
        activePlaybackID = UUID()
        activeAnalysisID = UUID()
        activeAnalysisTarget = nil
        if hasInstalledAnalysisTap {
            analysisMixer?.removeTap(onBus: 0)
            hasInstalledAnalysisTap = false
        }
        if comparisonPlayerNodes.isEmpty {
            playerNode?.stop()
        } else {
            comparisonPlayerNodes.values.forEach { $0.stop() }
        }
        engine?.stop()
        playerNode = nil
        analysisMixer = nil
        engine = nil
        activeAudioFile = nil
        comparisonPlayerNodes.removeAll()
        comparisonAnalysisMixers.removeAll()
        comparisonAudioFiles.removeAll()
        comparisonPlaybackDurations.removeAll()
        completedComparisonTargets.removeAll()
        activePlaybackStartTime = 0
        activePlaybackDuration = 0
    }

    private func clearVectorScopeSnapshots(except preservedTarget: AudioPreviewTarget? = nil) {
        for target in AudioPreviewTarget.allCases where target != preservedTarget {
            cardState(for: target).vectorScopeSnapshot = .unavailable
            vectorScopeHistoryCounters[target] = nil
        }
    }

    private func clearLiveLoudnessMeterSnapshots(except preservedTarget: AudioPreviewTarget? = nil) {
        for target in AudioPreviewTarget.allCases where target != preservedTarget {
            cardState(for: target).liveLoudnessMeterSnapshot = .unavailable
        }
    }

    private func clearRealtimeVisualSnapshots(except preservedTarget: AudioPreviewTarget? = nil) {
        clearVectorScopeSnapshots(except: preservedTarget)
        clearLiveLoudnessMeterSnapshots(except: preservedTarget)
    }

    private func normalizedProgress(for target: AudioPreviewTarget, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(cardState(for: target).playbackPosition / duration, 0), 1)
    }

    func cardState(for target: AudioPreviewTarget) -> AudioPreviewCardState {
        switch target {
        case .input:
            return inputCardState
        case .corrected:
            return correctedCardState
        case .mastered:
            return masteredCardState
        }
    }

    func playbackDiagnosticState() -> AudioPreviewPlaybackDiagnosticState {
        var nodes = comparisonPlayerNodes
        if nodes.isEmpty, let activeTarget, let playerNode {
            nodes[activeTarget] = playerNode
        }
        return AudioPreviewPlaybackDiagnosticState(
            engineIdentifier: engine.map(ObjectIdentifier.init),
            engineIsRunning: engine?.isRunning == true,
            playerNodeIdentifiers: nodes.mapValues(ObjectIdentifier.init),
            playerNodeIsPlaying: nodes.mapValues(\.isPlaying),
            playerNodeVolumes: nodes.mapValues(\.volume),
            playbackSessionID: activePlaybackID,
            analysisTarget: activeAnalysisTarget,
            analysisID: activeAnalysisID,
            completedTargets: completedComparisonTargets,
            analysisOutputSampleRate: analysisMixer?.outputFormat(forBus: 0).sampleRate,
            analysisOutputChannelCount: analysisMixer?.outputFormat(forBus: 0).channelCount
        )
    }

    private func format(duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private enum RealtimeSpectrumTapInstaller {
    nonisolated static func installTap(
        on mixer: AVAudioMixerNode,
        bufferSize: AVAudioFrameCount,
        analysisFormat: AVAudioFormat,
        analysisQueue: DispatchQueue,
        controller: AudioPreviewController,
        target: AudioPreviewTarget,
        analysisID: UUID
    ) {
        let loudnessAnalyzer = LiveLoudnessAnalyzer(sampleRate: analysisFormat.sampleRate)
        mixer.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak controller] buffer, _ in
            guard let sampleBuffer = RealtimeSpectrumAnalyzer.sampleBuffer(from: buffer) else { return }
            analysisQueue.async { [weak controller] in
                let vectorScopeSnapshot = VectorScopeAnalyzer.snapshot(from: sampleBuffer)
                let loudnessSnapshot = loudnessAnalyzer.snapshot(from: sampleBuffer)
                Task { @MainActor [weak controller] in
                    controller?.storeVectorScopeSnapshot(vectorScopeSnapshot, for: target, analysisID: analysisID)
                    controller?.storeLiveLoudnessMeterSnapshot(loudnessSnapshot, for: target, analysisID: analysisID)
                }
            }
        }
    }
}

struct RealtimeSpectrumSampleBuffer: Sendable {
    let channelSamples: [[Float]]
    let sampleRate: Double
}

final class LiveLoudnessAnalyzer: @unchecked Sendable {
    private let sampleRate: Double
    private let momentaryWindowSize: Int
    private let shortTermWindowSize: Int
    private let integratedBlockSize: Int
    private let integratedHopSize: Int
    private var filters: [LoudnessMeasurementService.KWeightingFilter] = []
    private var momentaryEnergyWindow: [Double] = []
    private var shortTermEnergyWindow: [Double] = []
    private var integratedEnergyWindow: [Double] = []
    private var integratedBlockLoudness: [Double] = []
    private var samplesSinceIntegratedHop = 0
    private var heldTruePeakLinear = Float.zero
    private var truePeakTailSamples: [[Float]] = []

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        momentaryWindowSize = max(1, Int(sampleRate * 0.4))
        shortTermWindowSize = max(1, Int(sampleRate * 3.0))
        integratedBlockSize = max(1, Int(sampleRate * 0.4))
        integratedHopSize = max(1, Int(sampleRate * 0.1))
    }

    func snapshot(from sampleBuffer: RealtimeSpectrumSampleBuffer) -> LiveLoudnessMeterSnapshot {
        let channels = sampleBuffer.channelSamples.filter { !$0.isEmpty }
        guard let frameLength = channels.map(\.count).min(), frameLength > 0 else {
            return .unavailable
        }

        if filters.count != channels.count {
            filters = Array(
                repeating: LoudnessMeasurementService.KWeightingFilter(sampleRate: sampleRate),
                count: channels.count
            )
            momentaryEnergyWindow.removeAll()
            shortTermEnergyWindow.removeAll()
            integratedEnergyWindow.removeAll()
            integratedBlockLoudness.removeAll()
            samplesSinceIntegratedHop = 0
            heldTruePeakLinear = 0
            truePeakTailSamples = Array(repeating: [], count: channels.count)
        }

        for sampleIndex in 0..<frameLength {
            var summedEnergy = 0.0
            for channelIndex in channels.indices {
                let weighted = filters[channelIndex].process(Double(channels[channelIndex][sampleIndex]))
                summedEnergy += weighted * weighted
            }
            appendEnergySample(summedEnergy)
        }
        trimEnergyWindows()

        let truePeakChannels = channels.enumerated().map { channelIndex, samples in
            let tailSamples = channelIndex < truePeakTailSamples.count ? truePeakTailSamples[channelIndex] : []
            return tailSamples + samples
        }
        heldTruePeakLinear = max(heldTruePeakLinear, LoudnessMeasurementService.truePeakLinear(truePeakChannels))
        truePeakTailSamples = channels.map { Array($0.suffix(16)) }
        return LiveLoudnessMeterSnapshot(
            state: .measuring,
            momentaryLUFS: momentaryEnergyWindow.count >= momentaryWindowSize ? loudnessLUFS(from: momentaryEnergyWindow) : nil,
            shortTermLUFS: shortTermEnergyWindow.count >= shortTermWindowSize ? loudnessLUFS(from: shortTermEnergyWindow) : nil,
            integratedLUFS: integratedLoudnessLUFS(),
            truePeakDBTP: heldTruePeakLinear > 0 ? 20 * log10(max(Double(heldTruePeakLinear), 1e-12)) : nil
        )
    }

    private func appendEnergySample(_ energy: Double) {
        momentaryEnergyWindow.append(energy)
        shortTermEnergyWindow.append(energy)
        integratedEnergyWindow.append(energy)

        samplesSinceIntegratedHop += 1
        if samplesSinceIntegratedHop >= integratedHopSize {
            samplesSinceIntegratedHop = 0
            if integratedEnergyWindow.count >= integratedBlockSize {
                let blockLoudness = loudnessLUFS(from: Array(integratedEnergyWindow.suffix(integratedBlockSize)))
                integratedBlockLoudness.append(blockLoudness)
            }
        }
    }

    private func trimEnergyWindows() {
        trim(&momentaryEnergyWindow, maximumCount: momentaryWindowSize)
        trim(&shortTermEnergyWindow, maximumCount: shortTermWindowSize)
        trim(&integratedEnergyWindow, maximumCount: integratedBlockSize)
    }

    private func trim(_ values: inout [Double], maximumCount: Int) {
        guard values.count > maximumCount else { return }
        values.removeFirst(values.count - maximumCount)
    }

    private func loudnessLUFS(from energies: [Double]) -> Double {
        guard !energies.isEmpty else { return -70 }
        let meanEnergy = energies.reduce(0, +) / Double(energies.count)
        return -0.691 + 10 * log10(max(meanEnergy, 1e-12))
    }

    private func integratedLoudnessLUFS() -> Double? {
        let absoluteGated = integratedBlockLoudness.filter { $0 >= -70 }
        guard !absoluteGated.isEmpty else { return nil }
        let preliminary = energyAverage(absoluteGated)
        let relativeGate = preliminary - 10
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }
        return energyAverage(relativeGated.isEmpty ? absoluteGated : relativeGated)
    }

    private func energyAverage(_ loudnessValues: [Double]) -> Double {
        let meanEnergy = loudnessValues.map { pow(10, $0 / 10) }.reduce(0, +) / Double(max(loudnessValues.count, 1))
        return 10 * log10(max(meanEnergy, 1e-9))
    }
}

enum RealtimeSpectrumAnalyzer {
    static let analysisSampleCount = 2_048
    static let timelineInterval: TimeInterval = 0.1
    private static let minimumAudibleSample: Float = 0.00001
    private static let displayedFrequencies = [
        80.0, 100.0, 125.0, 160.0, 200.0, 250.0, 315.0, 400.0,
        500.0, 630.0, 800.0, 1_000.0, 1_250.0, 1_600.0, 2_000.0,
        2_500.0, 3_150.0, 4_000.0, 5_000.0, 6_300.0, 8_000.0,
        10_000.0, 12_500.0, 16_000.0, 20_000.0
    ]

    static func tapBufferSize(for sampleRate: Double) -> AVAudioFrameCount {
        AVAudioFrameCount(max(analysisSampleCount, Int(sampleRate * 0.1)))
    }

    static func points(from buffer: AVAudioPCMBuffer) -> [RealtimeSpectrumPoint] {
        guard let sampleBuffer = sampleBuffer(from: buffer) else { return [] }
        return points(from: sampleBuffer)
    }

    static func timeline(
        from mono: [Float],
        sampleRate: Double,
        frameInterval: TimeInterval = timelineInterval
    ) -> [[RealtimeSpectrumPoint]] {
        guard !mono.isEmpty, sampleRate > 0, frameInterval > 0, let dft = makeTransform() else {
            return []
        }

        let segmentLength = max(analysisSampleCount, Int(sampleRate * 0.1))
        let maximumStart = max(mono.count - segmentLength, 0)
        let duration = Double(mono.count) / sampleRate
        let frameCount = max(1, Int(ceil(duration / frameInterval)) + 1)
        return (0..<frameCount).map { frameIndex in
            let time = min(Double(frameIndex) * frameInterval, duration)
            let centerIndex = min(Int((time * sampleRate).rounded()), mono.count - 1)
            let startIndex = min(max(centerIndex - segmentLength / 2, 0), maximumStart)
            var segment = Array(repeating: Float.zero, count: segmentLength)
            let copiedCount = min(segmentLength, mono.count - startIndex)
            if copiedCount > 0 {
                segment.replaceSubrange(0..<copiedCount, with: mono[startIndex..<(startIndex + copiedCount)])
            }
            let window = loudestWindow(from: [segment])
            return points(from: window, sampleRate: sampleRate, dft: dft)
        }
    }

    fileprivate static func sampleBuffer(from buffer: AVAudioPCMBuffer) -> RealtimeSpectrumSampleBuffer? {
        guard
            let channelData = buffer.floatChannelData,
            buffer.frameLength >= AVAudioFrameCount(analysisSampleCount)
        else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var channelSamples: [[Float]] = []
        channelSamples.reserveCapacity(channelCount)
        for channelIndex in 0..<channelCount {
            let samples = UnsafeBufferPointer(start: channelData[channelIndex], count: frameLength)
            channelSamples.append(Array(samples))
        }

        return RealtimeSpectrumSampleBuffer(
            channelSamples: channelSamples,
            sampleRate: buffer.format.sampleRate
        )
    }

    fileprivate static func points(from sampleBuffer: RealtimeSpectrumSampleBuffer) -> [RealtimeSpectrumPoint] {
        let mono = loudestWindow(from: sampleBuffer.channelSamples)
        guard !mono.isEmpty, let dft = makeTransform() else { return [] }
        return points(from: mono, sampleRate: sampleBuffer.sampleRate, dft: dft)
    }

    private static func makeTransform() -> vDSP.DiscreteFourierTransform<Float>? {
        try? vDSP.DiscreteFourierTransform<Float>(
            count: analysisSampleCount,
            direction: .forward,
            transformType: .complexReal,
            ofType: Float.self
        )
    }

    private static func points(
        from mono: [Float],
        sampleRate: Double,
        dft: vDSP.DiscreteFourierTransform<Float>
    ) -> [RealtimeSpectrumPoint] {
        guard mono.count == analysisSampleCount else { return [] }

        let inputImaginary = [Float](repeating: .zero, count: analysisSampleCount)
        var outputReal = Array(repeating: Float.zero, count: analysisSampleCount)
        var outputImaginary = Array(repeating: Float.zero, count: analysisSampleCount)
        dft.transform(
            inputReal: mono,
            inputImaginary: inputImaginary,
            outputReal: &outputReal,
            outputImaginary: &outputImaginary
        )

        let frequencyStep = sampleRate / Double(analysisSampleCount)
        let halfCount = analysisSampleCount / 2
        return displayedFrequencies.compactMap { frequency in
            guard frequency < sampleRate / 2 else { return nil }
            let bin = min(max(Int((frequency / frequencyStep).rounded()), 1), halfCount - 1)
            let power = Double(outputReal[bin] * outputReal[bin] + outputImaginary[bin] * outputImaginary[bin])
            let amplitude = sqrt(power) * 2 / Double(analysisSampleCount)
            let levelDB = 20 * log10(max(amplitude, 1e-9))
            return RealtimeSpectrumPoint(
                id: String(format: "%.0f", frequency),
                frequencyHz: frequency,
                levelDB: max(-100, min(0, levelDB))
            )
        }
    }

    private static func loudestWindow(from channelSamples: [[Float]]) -> [Float] {
        guard let frameLength = channelSamples.first?.count, frameLength >= analysisSampleCount else { return [] }

        var loudestIndex = 0
        var loudestSample = Float.zero
        for samples in channelSamples {
            for (index, sample) in samples.enumerated() {
                let value = abs(sample)
                if value > loudestSample {
                    loudestSample = value
                    loudestIndex = index
                }
            }
        }
        guard loudestSample > minimumAudibleSample else { return [] }

        let startIndex = min(max(loudestIndex - analysisSampleCount / 2, 0), frameLength - analysisSampleCount)
        var mono = Array(repeating: Float.zero, count: analysisSampleCount)
        for samples in channelSamples {
            for index in 0..<analysisSampleCount {
                mono[index] += samples[startIndex + index] / Float(channelSamples.count)
            }
        }
        return mono
    }
}

enum VectorScopeAnalyzer {
    static let maximumPointCount = 256
    static let historyDurationSeconds = 3.0
    private static let minimumAudibleSample: Float = 0.00001
    private static let maximumHistoryAge = 1.0
    private static let defaultUpdatesPerSecond = 10.0
    private static let maximumStoredPointCount = maximumPointCount * Int(historyDurationSeconds * defaultUpdatesPerSecond)
    private static let maximumStoredLineCount = Int(historyDurationSeconds * defaultUpdatesPerSecond)

    static func snapshot(from buffer: AVAudioPCMBuffer) -> VectorScopeSnapshot {
        guard let sampleBuffer = RealtimeSpectrumAnalyzer.sampleBuffer(from: buffer) else {
            return .unavailable
        }
        return snapshot(from: sampleBuffer)
    }

    static func inputState(forChannelCount channelCount: Int) -> VectorScopeInputState {
        switch channelCount {
        case 1:
            return .mono
        case 2:
            return .stereo
        case 3...:
            return .multichannel(channelCount)
        default:
            return .unavailable
        }
    }

    fileprivate static func snapshot(from sampleBuffer: RealtimeSpectrumSampleBuffer) -> VectorScopeSnapshot {
        let channelCount = sampleBuffer.channelSamples.count
        let inputState = inputState(forChannelCount: channelCount)
        guard inputState == .stereo else {
            return VectorScopeSnapshot(inputState: inputState, points: [])
        }

        let left = sampleBuffer.channelSamples[0]
        let right = sampleBuffer.channelSamples[1]
        let frameLength = min(left.count, right.count)
        guard frameLength > 0 else {
            return VectorScopeSnapshot(inputState: .stereo, points: [])
        }

        var peak = Float.zero
        for index in 0..<frameLength {
            peak = max(peak, abs(left[index]), abs(right[index]))
        }
        guard peak > minimumAudibleSample else {
            return VectorScopeSnapshot(inputState: .stereo, points: [])
        }

        let pointCount = min(maximumPointCount, frameLength)
        var leftEnergy = 0.0
        var rightEnergy = 0.0
        var sharedEnergy = 0.0
        var midEnergy = 0.0
        var sideEnergy = 0.0
        var peakPolarPoint: (x: Double, y: Double)?
        var peakPolarMagnitude = 0.0
        var sideSum = 0.0
        var containsClipping = false

        for index in 0..<frameLength {
            let leftSample = Double(left[index])
            let rightSample = Double(right[index])
            let mid = (leftSample + rightSample) / 2
            let side = (rightSample - leftSample) / 2
            leftEnergy += leftSample * leftSample
            rightEnergy += rightSample * rightSample
            sharedEnergy += leftSample * rightSample
            midEnergy += mid * mid
            sideEnergy += side * side
            let rawPeakX = side * sqrt(2)
            let rawPeakY = abs(mid) * sqrt(2)
            let peakMagnitude = sqrt(rawPeakX * rawPeakX + rawPeakY * rawPeakY)
            if peakMagnitude > peakPolarMagnitude {
                peakPolarMagnitude = peakMagnitude
                peakPolarPoint = normalizePolarPoint(x: rawPeakX, y: rawPeakY)
            }
            sideSum += side
            containsClipping = containsClipping || isClipped(leftSample, rightSample)
        }

        let points = (0..<pointCount).map { pointIndex in
            let sampleIndex: Int
            if pointCount == 1 {
                sampleIndex = 0
            } else {
                sampleIndex = pointIndex * (frameLength - 1) / (pointCount - 1)
            }
            let leftSample = Double(left[sampleIndex])
            let rightSample = Double(right[sampleIndex])
            let point = lissajousPoint(left: leftSample, right: rightSample)
            return VectorScopePoint(
                id: pointIndex,
                x: point.x,
                y: point.y,
                isClipped: isClipped(leftSample, rightSample)
            )
        }
        let polarSamplePoints = (0..<pointCount).map { pointIndex in
            let sampleIndex: Int
            if pointCount == 1 {
                sampleIndex = 0
            } else {
                sampleIndex = pointIndex * (frameLength - 1) / (pointCount - 1)
            }
            let leftSample = Double(left[sampleIndex])
            let rightSample = Double(right[sampleIndex])
            let point = polarSamplePoint(left: leftSample, right: rightSample)
            return VectorScopePoint(
                id: pointIndex,
                x: point.x,
                y: point.y,
                isClipped: isClipped(leftSample, rightSample)
            )
        }

        let denominator = sqrt(leftEnergy * rightEnergy)
        let measuredCorrelation = denominator > 1e-12 ? max(-1, min(1, sharedEnergy / denominator)) : nil
        let totalEnergy = leftEnergy + rightEnergy
        let balance = totalEnergy > 1e-12 ? max(-1, min(1, (rightEnergy - leftEnergy) / totalEnergy)) : nil
        let polarLevelLinesByDetectionMode = makePolarLevelLines(
            frameLength: frameLength,
            midEnergy: midEnergy,
            sideEnergy: sideEnergy,
            peakPolarPoint: peakPolarPoint,
            sideSum: sideSum,
            leftEnergy: leftEnergy,
            rightEnergy: rightEnergy,
            balance: balance,
            isClipped: containsClipping
        )

        return VectorScopeSnapshot(
            inputState: .stereo,
            points: points,
            polarSamplePoints: polarSamplePoints,
            polarLevelLinesByDetectionMode: polarLevelLinesByDetectionMode,
            correlation: measuredCorrelation,
            balance: balance,
            updateDurationSeconds: Double(frameLength) / sampleBuffer.sampleRate
        )
    }

    static func merging(
        _ current: VectorScopeSnapshot,
        with previous: VectorScopeSnapshot,
        generationID: Int
    ) -> VectorScopeSnapshot {
        guard current.inputState == .stereo, previous.inputState == .stereo else {
            return current
        }

        let currentPoints = renumber(current.points, generationID: generationID)
        let currentPolarPoints = renumber(current.polarSamplePoints, generationID: generationID)
        let currentLinesByDetectionMode = renumber(current.polarLevelLinesByDetectionMode, generationID: generationID)
        let ageStep = historyAgeStep(for: current)
        let agedPreviousLinesByDetectionMode = aged(previous.polarLevelLinesByDetectionMode, by: ageStep)

        return VectorScopeSnapshot(
            inputState: current.inputState,
            points: capped(currentPoints + aged(previous.points, by: ageStep), maximumCount: maximumStoredPointCount),
            polarSamplePoints: capped(currentPolarPoints + aged(previous.polarSamplePoints, by: ageStep), maximumCount: maximumStoredPointCount),
            polarLevelLinesByDetectionMode: VectorScopeLevelDetectionMode.allCases.reduce(into: [:]) { result, detectionMode in
                result[detectionMode] = capped(
                    (currentLinesByDetectionMode[detectionMode] ?? []) + (agedPreviousLinesByDetectionMode[detectionMode] ?? []),
                    maximumCount: maximumStoredLineCount
                )
            },
            correlation: current.correlation,
            balance: current.balance,
            updateDurationSeconds: current.updateDurationSeconds
        )
    }

    private static func historyAgeStep(for snapshot: VectorScopeSnapshot) -> Double {
        let updateDuration = snapshot.updateDurationSeconds > 0
            ? snapshot.updateDurationSeconds
            : 1 / defaultUpdatesPerSecond
        return min(maximumHistoryAge, updateDuration / historyDurationSeconds)
    }

    private static func isClipped(_ leftSample: Double, _ rightSample: Double) -> Bool {
        abs(leftSample) >= 1 || abs(rightSample) >= 1
    }

    private static func makePolarLevelLines(
        frameLength: Int,
        midEnergy: Double,
        sideEnergy: Double,
        peakPolarPoint: (x: Double, y: Double)?,
        sideSum: Double,
        leftEnergy: Double,
        rightEnergy: Double,
        balance: Double?,
        isClipped: Bool
    ) -> [VectorScopeLevelDetectionMode: [VectorScopeLine]] {
        let totalEnergy = leftEnergy + rightEnergy
        guard frameLength > 0, totalEnergy > 1e-12 else { return [:] }

        let midRMS = sqrt(midEnergy / Double(frameLength))
        let sideRMS = sqrt(sideEnergy / Double(frameLength))
        let balanceValue = balance ?? 0
        let sideSign: Double
        if abs(balanceValue) > 0.001 {
            sideSign = balanceValue > 0 ? 1 : -1
        } else if abs(sideSum) > 0.001 {
            sideSign = sideSum > 0 ? 1 : -1
        } else {
            sideSign = sideEnergy > midEnergy ? 1 : 0
        }

        return [
            .rms: [
                VectorScopeLine(
                    id: 0,
                    x: clampUnit(sideRMS * sqrt(2) * sideSign),
                    y: clampUnit(midRMS * sqrt(2)),
                    isClipped: isClipped
                )
            ],
            .peak: [
                VectorScopeLine(
                    id: 0,
                    x: peakPolarPoint?.x ?? 0,
                    y: peakPolarPoint?.y ?? 0,
                    isClipped: isClipped
                )
            ]
        ]
    }

    private static func lissajousPoint(left: Double, right: Double) -> (x: Double, y: Double) {
        (
            x: clampUnit((right - left) / 2),
            y: clampUnit((left + right) / 2)
        )
    }

    private static func polarSamplePoint(left: Double, right: Double) -> (x: Double, y: Double) {
        let mid = (left + right) / 2
        let side = (right - left) / 2
        return normalizePolarPoint(x: side * sqrt(2), y: abs(mid) * sqrt(2))
    }

    private static func normalizePolarPoint(x: Double, y: Double) -> (x: Double, y: Double) {
        let positiveY = max(0, y)
        let length = sqrt(x * x + positiveY * positiveY)
        guard length > 1 else {
            return (clampUnit(x), min(positiveY, 1))
        }
        return (clampUnit(x / length), min(positiveY / length, 1))
    }

    private static func clampUnit(_ value: Double) -> Double {
        max(-1, min(1, value))
    }

    private static func aged(_ points: [VectorScopePoint], by ageStep: Double) -> [VectorScopePoint] {
        points.compactMap { point in
            let nextAge = point.age + ageStep
            guard nextAge <= maximumHistoryAge else { return nil }
            return VectorScopePoint(id: point.id, x: point.x, y: point.y, isClipped: point.isClipped, age: nextAge)
        }
    }

    private static func aged(_ lines: [VectorScopeLine], by ageStep: Double) -> [VectorScopeLine] {
        lines.compactMap { line in
            let nextAge = line.age + ageStep
            guard nextAge <= maximumHistoryAge else { return nil }
            return VectorScopeLine(id: line.id, x: line.x, y: line.y, isClipped: line.isClipped, age: nextAge)
        }
    }

    private static func aged(
        _ linesByDetectionMode: [VectorScopeLevelDetectionMode: [VectorScopeLine]],
        by ageStep: Double
    ) -> [VectorScopeLevelDetectionMode: [VectorScopeLine]] {
        linesByDetectionMode.mapValues { aged($0, by: ageStep) }
    }

    private static func renumber(_ points: [VectorScopePoint], generationID: Int) -> [VectorScopePoint] {
        points.enumerated().map { offset, point in
            VectorScopePoint(
                id: generationID * 10_000 + offset,
                x: point.x,
                y: point.y,
                isClipped: point.isClipped,
                age: 0
            )
        }
    }

    private static func renumber(_ lines: [VectorScopeLine], generationID: Int) -> [VectorScopeLine] {
        lines.enumerated().map { offset, line in
            VectorScopeLine(
                id: generationID * 1_000 + offset,
                x: line.x,
                y: line.y,
                isClipped: line.isClipped,
                age: 0
            )
        }
    }

    private static func renumber(
        _ linesByDetectionMode: [VectorScopeLevelDetectionMode: [VectorScopeLine]],
        generationID: Int
    ) -> [VectorScopeLevelDetectionMode: [VectorScopeLine]] {
        linesByDetectionMode.mapValues { renumber($0, generationID: generationID) }
    }

    private static func capped<T>(_ values: [T], maximumCount: Int) -> [T] {
        guard values.count > maximumCount else { return values }
        return Array(values.prefix(maximumCount))
    }
}
