import AVFoundation
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
    var playbackProgress: Double = 0
    var playbackPosition: TimeInterval = 0
    var playbackState: AudioPlaybackState = .stopped

    init(target: AudioPreviewTarget) {
        self.target = target
    }
}

@MainActor
@Observable
final class AudioPreviewController: NSObject, AVAudioPlayerDelegate {
    var activeTarget: AudioPreviewTarget?
    var playbackLabel = "未再生"
    var playbackVolume: Float = 1.0
    var comparisonPair: AudioComparisonPair = .correctedVsMastered
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

    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var previewTasks: [AudioPreviewTarget: Task<Void, Never>] = [:]
    private var integratedLoudnessByTarget: [AudioPreviewTarget: Float] = [:]
    private let meterInterval: TimeInterval = 0.05
    private let smoothingFactor = 0.25

    func startPlayback(for url: URL?, target: AudioPreviewTarget) {
        guard let url else { return }

        if activeTarget == target, let player, player.isPlaying {
            return
        }

        do {
            preparePreview(for: url, target: target)
            syncComparisonPositionIfNeeded(for: target)
            transitionAwayFromCurrentTarget(keepingPosition: true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.isMeteringEnabled = true
            player?.prepareToPlay()
            player?.volume = effectivePlaybackVolume(for: target)
            let targetState = cardState(for: target)
            let resumeTime = targetState.playbackPosition
            if let player {
                player.currentTime = min(resumeTime, max(player.duration - 0.05, 0))
            }
            player?.play()
            activeTarget = target
            targetState.playbackState = .playing
            if let comparisonSide = comparisonSide(for: target) {
                activeComparisonSide = comparisonSide
                playbackLabel = "\(comparisonPair.title(for: comparisonSide)) \(target.rawValue)を再生中"
            } else {
                playbackLabel = "\(target.rawValue)を再生中"
            }
            let progress = player?.duration == 0 ? 0 : max(0, min(1, (player?.currentTime ?? 0) / (player?.duration ?? 1)))
            targetState.playbackProgress = progress
            startMetering(target: target)
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
        guard activeTarget == target, let player else { return }
        let targetState = cardState(for: target)
        targetState.playbackPosition = player.currentTime
        targetState.playbackProgress = player.duration > 0 ? max(0, min(1, player.currentTime / player.duration)) : 0
        meterTimer?.invalidate()
        meterTimer = nil
        player.pause()
        targetState.playbackState = .paused
        playbackLabel = "\(target.rawValue)を一時停止中"
    }

    func stopPlayback(target: AudioPreviewTarget? = nil) {
        let resolvedTarget = target ?? activeTarget
        guard let resolvedTarget else {
            playbackLabel = "停止中"
            return
        }

        if activeTarget == resolvedTarget {
            meterTimer?.invalidate()
            meterTimer = nil
            player?.stop()
            player = nil
            activeTarget = nil
        }

        let resolvedState = cardState(for: resolvedTarget)
        resolvedState.playbackPosition = 0
        resolvedState.playbackProgress = 0
        resolvedState.playbackState = .stopped
        if let snapshot = resolvedState.snapshot {
            resolvedState.liveBandLevels = makeInitialLiveBandLevels(from: snapshot, target: resolvedTarget)
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
        integratedLoudnessByTarget[target] = nil
        targetState.playbackPosition = 0
        targetState.playbackProgress = 0
        targetState.playbackState = .stopped
        if activeTarget == target {
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
        integratedLoudnessByTarget[target] = nil
        targetState.playbackPosition = 0
        targetState.playbackProgress = 0
        targetState.playbackState = .stopped
        if activeTarget == target {
            activeTarget = nil
        }
    }

    func setPreviewSnapshot(_ snapshot: AudioPreviewSnapshot, for target: AudioPreviewTarget, sourceURL: URL, integratedLoudnessLUFS: Double? = nil) {
        let targetState = cardState(for: target)
        targetState.sourceURL = sourceURL
        targetState.snapshot = snapshot
        targetState.playbackProgress = normalizedProgress(for: target, duration: snapshot.duration)
        targetState.liveBandLevels = makeInitialLiveBandLevels(from: snapshot, target: target)
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
            elapsed = player?.currentTime ?? targetState.playbackPosition
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

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopPlayback()
        }
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
        guard let player else { return }
        player.updateMeters()

        if player.duration > 0 {
            let progress = max(0, min(1, player.currentTime / player.duration))
            let targetState = cardState(for: target)
            targetState.playbackProgress = progress
            targetState.playbackPosition = player.currentTime
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
        guard let activeTarget, let player else { return }
        let targetState = cardState(for: activeTarget)
        targetState.playbackPosition = player.currentTime
        targetState.playbackProgress = player.duration > 0 ? max(0, min(1, player.currentTime / player.duration)) : 0
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

    func playbackProgress(for target: AudioPreviewTarget) -> Double {
        if activeTarget == target, let player, player.duration > 0 {
            return max(0, min(1, player.currentTime / player.duration))
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
        player?.stop()
        player = nil
        self.activeTarget = nil
    }

    private func refreshPlaybackVolumeIfNeeded() {
        guard let activeTarget else { return }
        player?.volume = effectivePlaybackVolume(for: activeTarget)
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
            let currentTime = player?.currentTime ?? cardState(for: activeTarget).playbackPosition
            let activeState = cardState(for: activeTarget)
            activeState.playbackPosition = currentTime
            activeState.playbackProgress = player?.duration ?? 0 > 0 ? currentTime / max(player?.duration ?? 1, 1) : 0
            cardState(for: target).playbackPosition = currentTime
            return
        }

        let pairedTarget = comparisonPair.firstTarget == target ? comparisonPair.secondTarget : comparisonPair.firstTarget
        let pairedPosition = cardState(for: pairedTarget).playbackPosition
        if pairedPosition > 0 {
            cardState(for: target).playbackPosition = pairedPosition
        }
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
