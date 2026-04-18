import AVFoundation
import Foundation

enum AudioPreviewTarget: String {
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
final class AudioPreviewController: NSObject, AVAudioPlayerDelegate {
    var activeTarget: AudioPreviewTarget?
    var playbackLabel = "未再生"
    var previewSnapshots: [AudioPreviewTarget: AudioPreviewSnapshot] = [:]
    var liveBandLevels: [AudioPreviewTarget: [LiveBandSample]] = [:]

    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var previewSourceURLs: [AudioPreviewTarget: URL] = [:]
    private var previewTasks: [AudioPreviewTarget: Task<Void, Never>] = [:]
    private var playbackPositions: [AudioPreviewTarget: TimeInterval] = [:]
    private var playbackProgresses: [AudioPreviewTarget: Double] = [:]
    private var playbackStates: [AudioPreviewTarget: AudioPlaybackState] = [:]
    private let meterInterval: TimeInterval = 0.05
    private let smoothingFactor = 0.20

    func startPlayback(for url: URL?, target: AudioPreviewTarget) {
        guard let url else { return }

        if activeTarget == target, let player, player.isPlaying {
            return
        }

        do {
            preparePreview(for: url, target: target)
            transitionAwayFromCurrentTarget(keepingPosition: true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.isMeteringEnabled = true
            player?.prepareToPlay()
            let resumeTime = playbackPositions[target] ?? 0
            if let player {
                player.currentTime = min(resumeTime, max(player.duration - 0.05, 0))
            }
            player?.play()
            activeTarget = target
            playbackStates[target] = .playing
            playbackLabel = "\(target.rawValue)を再生中"
            let progress = player?.duration == 0 ? 0 : max(0, min(1, (player?.currentTime ?? 0) / (player?.duration ?? 1)))
            playbackProgresses[target] = progress
            startMetering(target: target)
        } catch {
            stopPlayback(target: target)
            playbackLabel = "再生できませんでした"
        }
    }

    func pausePlayback(target: AudioPreviewTarget) {
        guard activeTarget == target, let player else { return }
        playbackPositions[target] = player.currentTime
        playbackProgresses[target] = player.duration > 0 ? max(0, min(1, player.currentTime / player.duration)) : 0
        meterTimer?.invalidate()
        meterTimer = nil
        player.pause()
        playbackStates[target] = .paused
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

        playbackPositions[resolvedTarget] = 0
        playbackProgresses[resolvedTarget] = 0
        playbackStates[resolvedTarget] = .stopped
        if let snapshot = previewSnapshots[resolvedTarget] {
            liveBandLevels[resolvedTarget] = makeInitialLiveBandLevels(from: snapshot, target: resolvedTarget)
        }
        playbackLabel = "停止中"
    }

    func preparePreview(for url: URL?, target: AudioPreviewTarget) {
        previewTasks[target]?.cancel()

        guard let url else {
            previewTasks[target] = nil
            previewSourceURLs[target] = nil
            previewSnapshots[target] = nil
            liveBandLevels[target] = nil
            playbackPositions[target] = 0
            playbackProgresses[target] = 0
            playbackStates[target] = .stopped
            if activeTarget == target {
                activeTarget = nil
            }
            return
        }

        if previewSourceURLs[target] == url, previewSnapshots[target] != nil {
            return
        }

        previewSourceURLs[target] = url
        previewSnapshots[target] = nil
        liveBandLevels[target] = nil

        previewTasks[target] = Task {
            let snapshot = try? await Task.detached(priority: .utility) {
                try AudioFileService.makePreviewSnapshot(for: url)
            }.value

            guard !Task.isCancelled else { return }
            guard previewSourceURLs[target] == url else { return }
            if let snapshot {
                setPreviewSnapshot(snapshot, for: target, sourceURL: url)
            }
            previewTasks[target] = nil
        }
    }

    func setPreviewSnapshot(_ snapshot: AudioPreviewSnapshot, for target: AudioPreviewTarget, sourceURL: URL) {
        previewSourceURLs[target] = sourceURL
        previewSnapshots[target] = snapshot
        playbackProgresses[target] = normalizedProgress(for: target, duration: snapshot.duration)
        if playbackStates[target] == nil {
            playbackStates[target] = .stopped
        }
        liveBandLevels[target] = makeInitialLiveBandLevels(from: snapshot, target: target)
    }

    func durationText(for target: AudioPreviewTarget) -> String {
        if let snapshot = previewSnapshots[target], snapshot.duration > 0 {
            return format(duration: snapshot.duration)
        }
        return "--:--"
    }

    func playbackTimeText(for target: AudioPreviewTarget) -> String {
        guard let snapshot = previewSnapshots[target], snapshot.duration > 0 else {
            return "--:-- / --:--"
        }

        let elapsed: TimeInterval
        if activeTarget == target {
            elapsed = player?.currentTime ?? playbackPositions[target] ?? 0
        } else {
            elapsed = playbackPositions[target] ?? 0
        }

        return "\(format(duration: elapsed)) / \(format(duration: snapshot.duration))"
    }

    func snapshot(for target: AudioPreviewTarget) -> AudioPreviewSnapshot {
        previewSnapshots[target] ?? AudioPreviewSnapshot(
            waveform: Array(repeating: 0, count: 96),
            duration: 0,
            bandLevels: Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map { ($0.id, Array(repeating: 0, count: 96)) }),
            bandLevelDBs: Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map { ($0.id, Array(repeating: Float(-120), count: 96)) })
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
            playbackProgresses[target] = progress
            playbackPositions[target] = player.currentTime
        }

        let snapshot = snapshot(for: target)
        let bucketIndex = min(
            max(Int(round((playbackProgresses[target] ?? 0) * Double(max(snapshot.waveform.count - 1, 0)))), 0),
            max(snapshot.waveform.count - 1, 0)
        )

        if let sharedLevels = sharedComparisonLevels(for: target, bucketIndex: bucketIndex) {
            let previousLevels = Dictionary(uniqueKeysWithValues: (liveBandLevels[target] ?? []).map { ($0.id, $0.level) })
            liveBandLevels[target] = sharedLevels.map { sample in
                let previousLevel = previousLevels[sample.id] ?? sample.level
                let smoothedLevel = previousLevel + (sample.level - previousLevel) * smoothingFactor
                return LiveBandSample(id: sample.id, label: sample.label, level: smoothedLevel)
            }
            return
        }

        let previousLevels = Dictionary(uniqueKeysWithValues: (liveBandLevels[target] ?? []).map { ($0.id, $0.level) })
        liveBandLevels[target] = AudioBandCatalog.previewBands.map { band in
            let targetLevel = Double(snapshot.bandLevels[band.id]?[bucketIndex] ?? 0)
            let previousLevel = previousLevels[band.id] ?? targetLevel
            let smoothedLevel = previousLevel + (targetLevel - previousLevel) * smoothingFactor
            return LiveBandSample(id: band.id, label: band.label, level: smoothedLevel)
        }
    }

    private func sharedComparisonLevels(for target: AudioPreviewTarget, bucketIndex: Int) -> [LiveBandSample]? {
        let comparisonTarget: AudioPreviewTarget
        switch target {
        case .input:
            comparisonTarget = .corrected
        case .corrected:
            comparisonTarget = .input
        case .mastered:
            comparisonTarget = .corrected
        }
        let targetSnapshot = previewSnapshots[target]
        let comparisonSnapshot = previewSnapshots[comparisonTarget]
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
        playbackPositions[activeTarget] = player.currentTime
        playbackProgresses[activeTarget] = player.duration > 0 ? max(0, min(1, player.currentTime / player.duration)) : 0
    }

    private func makeInitialLiveBandLevels(from snapshot: AudioPreviewSnapshot, target: AudioPreviewTarget) -> [LiveBandSample] {
        let bucketIndex: Int
        if snapshot.duration > 0 {
            let progress = min(max((playbackPositions[target] ?? 0) / snapshot.duration, 0), 1)
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
        return playbackProgresses[target] ?? 0
    }

    func playbackState(for target: AudioPreviewTarget) -> AudioPlaybackState {
        playbackStates[target] ?? .stopped
    }

    private func transitionAwayFromCurrentTarget(keepingPosition: Bool) {
        guard let activeTarget else { return }
        if keepingPosition {
            storeCurrentPlaybackPosition()
            playbackStates[activeTarget] = .paused
        } else {
            playbackPositions[activeTarget] = 0
            playbackProgresses[activeTarget] = 0
            playbackStates[activeTarget] = .stopped
        }
        meterTimer?.invalidate()
        meterTimer = nil
        player?.stop()
        player = nil
        self.activeTarget = nil
    }

    private func normalizedProgress(for target: AudioPreviewTarget, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(max((playbackPositions[target] ?? 0) / duration, 0), 1)
    }

    private func format(duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
