import AVFoundation
import Foundation

enum AudioPreviewTarget: String {
    case input = "入力"
    case output = "出力"
}

@MainActor
@Observable
final class AudioPreviewController: NSObject, AVAudioPlayerDelegate {
    var activeTarget: AudioPreviewTarget?
    var playbackLabel = "未再生"
    var playbackProgress: Double = 0
    var previewSnapshots: [AudioPreviewTarget: AudioPreviewSnapshot] = [:]
    var liveBandLevels: [AudioPreviewTarget: [LiveBandSample]] = [:]

    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var previewSourceURLs: [AudioPreviewTarget: URL] = [:]
    private var previewTasks: [AudioPreviewTarget: Task<Void, Never>] = [:]
    private let meterInterval: TimeInterval = 0.05
    private let smoothingFactor = 0.20

    func togglePlayback(for url: URL?, target: AudioPreviewTarget) {
        guard let url else { return }

        if activeTarget == target, player?.isPlaying == true {
            stopPlayback()
            return
        }

        do {
            preparePreview(for: url, target: target)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.isMeteringEnabled = true
            player?.prepareToPlay()
            player?.play()
            activeTarget = target
            playbackLabel = "\(target.rawValue)を再生中"
            playbackProgress = 0
            startMetering(target: target)
        } catch {
            stopPlayback()
            playbackLabel = "再生できませんでした"
        }
    }

    func stopPlayback() {
        meterTimer?.invalidate()
        meterTimer = nil
        player?.stop()
        player = nil
        playbackProgress = 0
        activeTarget = nil
        playbackLabel = "停止中"
    }

    func preparePreview(for url: URL?, target: AudioPreviewTarget) {
        previewTasks[target]?.cancel()

        guard let url else {
            previewTasks[target] = nil
            previewSourceURLs[target] = nil
            previewSnapshots[target] = nil
            liveBandLevels[target] = nil
            if activeTarget == target {
                playbackProgress = 0
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
                previewSnapshots[target] = snapshot
            }
            previewTasks[target] = nil
        }
    }

    func durationText(for target: AudioPreviewTarget) -> String {
        if let snapshot = previewSnapshots[target], snapshot.duration > 0 {
            return format(duration: snapshot.duration)
        }
        return "--:--"
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
            playbackProgress = max(0, min(1, player.currentTime / player.duration))
        }

        let snapshot = snapshot(for: target)
        let bucketIndex = min(
            max(Int(round(playbackProgress * Double(max(snapshot.waveform.count - 1, 0)))), 0),
            max(snapshot.waveform.count - 1, 0)
        )
        let previousLevels = Dictionary(uniqueKeysWithValues: (liveBandLevels[target] ?? []).map { ($0.id, $0.level) })
        liveBandLevels[target] = AudioBandCatalog.previewBands.map { band in
            let targetLevel = Double(snapshot.bandLevels[band.id]?[bucketIndex] ?? 0)
            let previousLevel = previousLevels[band.id] ?? targetLevel
            let smoothedLevel = previousLevel + (targetLevel - previousLevel) * smoothingFactor
            return LiveBandSample(id: band.id, label: band.label, level: smoothedLevel)
        }
    }

    private func format(duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
