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
        previewSnapshots[target] ?? AudioPreviewSnapshot(waveform: Array(repeating: 0, count: 96), duration: 0)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopPlayback()
        }
    }
    private func startMetering(target: AudioPreviewTarget) {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
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

        let averagePower = player.averagePower(forChannel: 0)
        let normalized = Double(max(0, min(1, (averagePower + 60) / 60)))
        liveBandLevels[target] = [
            LiveBandSample(id: "low", label: "低域", level: normalized * 0.55),
            LiveBandSample(id: "mid", label: "中域", level: normalized * 0.72),
            LiveBandSample(id: "high", label: "高域", level: normalized * 0.88),
            LiveBandSample(id: "air", label: "超高域", level: normalized)
        ]
    }

    private func format(duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
