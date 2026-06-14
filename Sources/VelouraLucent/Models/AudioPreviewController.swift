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
    private let realtimeSpectrumAnalysisQueue = DispatchQueue(
        label: "com.codex.VelouraLucent.realtimeSpectrumAnalysis",
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
        comparisonPair = pair
        activeComparisonSide = .a
        if let activeTarget, !pair.targets.contains(activeTarget) {
            stopPlayback()
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
        guard activeTarget == target, let playerNode else { return }
        let targetState = cardState(for: target)
        let currentTime = currentPlaybackPosition()
        targetState.playbackPosition = currentTime
        targetState.playbackProgress = activePlaybackDuration > 0 ? max(0, min(1, currentTime / activePlaybackDuration)) : 0
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
        guard let activeTarget else { return }
        stopPlayback(target: activeTarget)
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
            synchronizePlaybackPositions(to: currentPlaybackPosition(), updatesLiveBandLevels: false)
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

        engine.attach(playerNode)
        engine.attach(analysisMixer)
        engine.connect(playerNode, to: analysisMixer, format: format)
        engine.connect(analysisMixer, to: engine.mainMixerNode, format: format)

        let tapBufferSize = RealtimeSpectrumAnalyzer.tapBufferSize(for: sampleRate)
        RealtimeSpectrumTapInstaller.installTap(
            on: analysisMixer,
            bufferSize: tapBufferSize,
            format: format,
            analysisQueue: realtimeSpectrumAnalysisQueue,
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

    fileprivate func storeRealtimeSpectrum(
        _ points: [RealtimeSpectrumPoint],
        for target: AudioPreviewTarget,
        playbackID: UUID
    ) {
        guard activeTarget == target, activePlaybackID == playbackID else { return }
        cardState(for: target).realtimeSpectrum = points
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
        mixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak controller] buffer, _ in
            guard let sampleBuffer = RealtimeSpectrumAnalyzer.sampleBuffer(from: buffer) else { return }
            analysisQueue.async { [weak controller] in
                let points = RealtimeSpectrumAnalyzer.points(from: sampleBuffer)
                guard !points.isEmpty else { return }
                Task { @MainActor [weak controller] in
                    controller?.storeRealtimeSpectrum(points, for: target, playbackID: playbackID)
                }
            }
        }
    }
}

fileprivate struct RealtimeSpectrumSampleBuffer: Sendable {
    let channelSamples: [[Float]]
    let sampleRate: Double
}

enum RealtimeSpectrumAnalyzer {
    static let analysisSampleCount = 2_048
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
        guard !mono.isEmpty else { return [] }

        let dft: vDSP.DiscreteFourierTransform<Float>
        do {
            dft = try vDSP.DiscreteFourierTransform<Float>(
                count: analysisSampleCount,
                direction: .forward,
                transformType: .complexReal,
                ofType: Float.self
            )
        } catch {
            return []
        }

        let inputImaginary = [Float](repeating: .zero, count: analysisSampleCount)
        var outputReal = Array(repeating: Float.zero, count: analysisSampleCount)
        var outputImaginary = Array(repeating: Float.zero, count: analysisSampleCount)
        dft.transform(
            inputReal: mono,
            inputImaginary: inputImaginary,
            outputReal: &outputReal,
            outputImaginary: &outputImaginary
        )

        let sampleRate = sampleBuffer.sampleRate
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
