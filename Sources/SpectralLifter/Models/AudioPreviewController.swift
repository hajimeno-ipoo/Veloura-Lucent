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

    private var player: AVAudioPlayer?

    func togglePlayback(for url: URL?, target: AudioPreviewTarget) {
        guard let url else { return }

        if activeTarget == target, player?.isPlaying == true {
            stopPlayback()
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            activeTarget = target
            playbackLabel = "\(target.rawValue)を再生中"
        } catch {
            stopPlayback()
            playbackLabel = "再生できませんでした"
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        activeTarget = nil
        playbackLabel = "停止中"
    }

    func durationText(for url: URL?) -> String {
        guard let url else { return "--:--" }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return "--:--" }
        let totalSeconds = Int(player.duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopPlayback()
        }
    }
}
