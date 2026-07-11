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
    private var activePlaybackStartTime: TimeInterval = 0
    private var activePlaybackDuration: TimeInterval = 0
    private var activePlaybackID = UUID()
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

        do {
            preparePreview(for: url, target: target)
            syncComparisonPositionIfNeeded(for: target)
            transitionAwayFromCurrentTarget(keepingPosition: true)
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            let targetState = cardState(for: target)
            let resumeTime = min(targetState.playbackPosition, max(duration - 0.05, 0))
            try prepareEnginePlayback(audioFile: audioFile, target: target, startTime: resumeTime, duration: duration)
            targetState.playbackState = .playing
            if let comparisonSide = comparisonSide(for: target) {
                activeComparisonSide = comparisonSide
                playbackLabel = "\(comparisonPair.title(for: comparisonSide)) \(target.rawValue)を再生中"
            } else {
                playbackLabel = "\(target.rawValue)を再生中"
            }
            targetState.playbackPosition = resumeTime
            targetState.playbackProgress = duration > 0 ? max(0, min(1, resumeTime / duration)) : 0
            updateComparisonSpectra(at: resumeTime)
            startMetering(target: target)
            playerNode?.play()
        } catch {
            stopPlayback(target: target)
            playbackLabel = "再生できませんでした"
        }
    }

    func playComparisonSide(_ side: AudioComparisonSide) {
        activeComparisonSide = side
        let target = comparisonTarget(for: side)
        startPlayback(for: cardState(for: target).sourceURL, target: target)
    }

    func toggleComparisonSide() {
        let next: AudioComparisonSide = activeComparisonSide == .a ? .b : .a
        playComparisonSide(next)
    }

    func setComparisonPair(_ pair: AudioComparisonPair) {
        guard pair != comparisonPair else { return }

        let previousActiveTarget = activeTarget
        let previousActiveSide = activeComparisonSide
        let preservedPosition = comparisonPositionForPairChange()
        if let previousActiveTarget, !pair.targets.contains(previousActiveTarget) {
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
        refreshPlaybackVolumeIfNeeded()
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
        targetState.playbackPosition = currentTime
        targetState.playbackProgress = activePlaybackDuration > 0 ? max(0, min(1, currentTime / activePlaybackDuration)) : 0
        updateComparisonSpectra(at: currentTime)
        meterTimer?.invalidate()
        meterTimer = nil
        playerNode.pause()
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
            waveform: Array(repeating: 0, count: AudioFileService.previewBucketCount),
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
        let bucketIndex = min(
            max(Int(round(cardState(for: target).playbackProgress * Double(max(snapshot.waveform.count - 1, 0)))), 0),
            max(snapshot.waveform.count - 1, 0)
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
            bucketIndex = min(
                max(Int(round(progress * Double(max(snapshot.waveform.count - 1, 0)))), 0),
                max(snapshot.waveform.count - 1, 0)
            )
        } else {
            bucketIndex = 0
        }

        return AudioBandCatalog.previewBands.map { band in
            let level = Double(snapshot.bandLevels[band.id]?[bucketIndex] ?? 0)
            return LiveBandSample(id: band.id, label: band.label, level: level)
        }
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
        playerNode?.volume = effectivePlaybackVolume(for: activeTarget)
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
            let activeState = cardState(for: activeTarget)
            activeState.playbackPosition = currentTime
            activeState.playbackProgress = activePlaybackDuration > 0 ? currentTime / activePlaybackDuration : 0
            cardState(for: target).playbackPosition = currentTime
            return
        }

        let pairedTarget = comparisonPair.firstTarget == target ? comparisonPair.secondTarget : comparisonPair.firstTarget
        let pairedPosition = cardState(for: pairedTarget).playbackPosition
        if pairedPosition > 0 {
            cardState(for: target).playbackPosition = pairedPosition
        }
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

    private func prepareEnginePlayback(
        audioFile: AVAudioFile,
        target: AudioPreviewTarget,
        startTime: TimeInterval,
        duration: TimeInterval
    ) throws {
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

        clearRealtimeVisualSnapshots()
        vectorScopeHistoryCounters[target] = nil
        cardState(for: target).vectorScopeSnapshot = VectorScopeSnapshot(
            inputState: VectorScopeAnalyzer.inputState(forChannelCount: Int(format.channelCount)),
            points: []
        )
        cardState(for: target).liveLoudnessMeterSnapshot = .unavailable

        engine.attach(playerNode)
        engine.attach(analysisMixer)
        engine.connect(playerNode, to: analysisMixer, format: format)
        engine.connect(analysisMixer, to: engine.mainMixerNode, format: format)

        let tapBufferSize = RealtimeSpectrumAnalyzer.tapBufferSize(for: sampleRate)
        RealtimeSpectrumTapInstaller.installTap(
            on: analysisMixer,
            bufferSize: tapBufferSize,
            format: format,
            analysisQueue: realtimeAnalysisQueue,
            controller: self,
            target: target,
            playbackID: playbackID
        )
        hasInstalledAnalysisTap = true

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
        let targetState = cardState(for: target)
        targetState.playbackState = .playing
        targetState.playbackPosition = safeStartTime
        targetState.playbackProgress = duration > 0 ? max(0, min(1, safeStartTime / duration)) : 0

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
    }

    fileprivate func storeVectorScopeSnapshot(
        _ snapshot: VectorScopeSnapshot,
        for target: AudioPreviewTarget,
        playbackID: UUID
    ) {
        guard activeTarget == target, activePlaybackID == playbackID else { return }
        storeVectorScopeSnapshotIfPlaying(snapshot, for: target)
    }

    fileprivate func storeLiveLoudnessMeterSnapshot(
        _ snapshot: LiveLoudnessMeterSnapshot,
        for target: AudioPreviewTarget,
        playbackID: UUID
    ) {
        guard activeTarget == target, activePlaybackID == playbackID else { return }
        storeLiveLoudnessMeterSnapshotIfPlaying(snapshot, for: target)
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
        guard activeTarget == target, activePlaybackID == playbackID else { return }
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
        if hasInstalledAnalysisTap {
            analysisMixer?.removeTap(onBus: 0)
            hasInstalledAnalysisTap = false
        }
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        analysisMixer = nil
        engine = nil
        activeAudioFile = nil
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
        format: AVAudioFormat,
        analysisQueue: DispatchQueue,
        controller: AudioPreviewController,
        target: AudioPreviewTarget,
        playbackID: UUID
    ) {
        let loudnessAnalyzer = LiveLoudnessAnalyzer(sampleRate: format.sampleRate)
        mixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak controller] buffer, _ in
            guard let sampleBuffer = RealtimeSpectrumAnalyzer.sampleBuffer(from: buffer) else { return }
            analysisQueue.async { [weak controller] in
                let vectorScopeSnapshot = VectorScopeAnalyzer.snapshot(from: sampleBuffer)
                let loudnessSnapshot = loudnessAnalyzer.snapshot(from: sampleBuffer)
                Task { @MainActor [weak controller] in
                    controller?.storeVectorScopeSnapshot(vectorScopeSnapshot, for: target, playbackID: playbackID)
                    controller?.storeLiveLoudnessMeterSnapshot(loudnessSnapshot, for: target, playbackID: playbackID)
                }
            }
        }
    }
}

fileprivate struct RealtimeSpectrumSampleBuffer: Sendable {
    let channelSamples: [[Float]]
    let sampleRate: Double
}

fileprivate final class LiveLoudnessAnalyzer: @unchecked Sendable {
    private let momentaryWindowSize: Int
    private let shortTermWindowSize: Int
    private let integratedBlockSize: Int
    private let integratedHopSize: Int
    private var filters: [LiveKWeightingFilter] = []
    private var momentaryEnergyWindow: [Double] = []
    private var shortTermEnergyWindow: [Double] = []
    private var integratedEnergyWindow: [Double] = []
    private var integratedBlockLoudness: [Double] = []
    private var samplesSinceIntegratedHop = 0
    private var heldTruePeakLinear = Float.zero
    private var truePeakTailSamples: [[Float]] = []

    init(sampleRate: Double) {
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
            filters = Array(repeating: LiveKWeightingFilter(), count: channels.count)
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

fileprivate struct LiveKWeightingFilter {
    private var preFilter = LiveBiquadFilter(coefficients: .officialPreFilter)
    private var rlbFilter = LiveBiquadFilter(coefficients: .officialRLBFilter)

    mutating func process(_ input: Double) -> Double {
        rlbFilter.process(preFilter.process(input))
    }
}

fileprivate struct LiveBiquadFilter {
    let coefficients: LiveBiquadCoefficients
    var x1 = 0.0
    var x2 = 0.0
    var y1 = 0.0
    var y2 = 0.0

    mutating func process(_ input: Double) -> Double {
        let output = coefficients.b0 * input
            + coefficients.b1 * x1
            + coefficients.b2 * x2
            - coefficients.a1 * y1
            - coefficients.a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}

fileprivate struct LiveBiquadCoefficients {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double

    static let officialPreFilter = LiveBiquadCoefficients(
        b0: 1.53512485958697,
        b1: -2.69169618940638,
        b2: 1.19839281085285,
        a1: -1.69065929318241,
        a2: 0.73248077421585
    )

    static let officialRLBFilter = LiveBiquadCoefficients(
        b0: 1,
        b1: -2,
        b2: 1,
        a1: -1.99004745483398,
        a2: 0.99007225036621
    )
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
