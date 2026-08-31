import SwiftUI

struct ComparisonVideoPlayerView: View {
    @Bindable var model: ComparisonVideoWindowModel

    var body: some View {
        ZStack {
            Color.clear

            if model.previewPlayer != nil {
                VStack(spacing: 12) {
                    ComparisonVideoCanvasView(model: model)
                        .aspectRatio(
                            model.orientation.pixelSize.width / model.orientation.pixelSize.height,
                            contentMode: .fit
                        )
                        .padding(8)
                        .velouraAdaptiveGlass(in: .rect(cornerRadius: 18))

                    ComparisonVideoPlaybackControls(model: model)
                }
                .padding(24)
            } else if model.isPreparingPreview {
                ProgressView("プレイヤーを準備しています")
                    .controlSize(.small)
                    .padding(24)
                    .velouraAdaptiveGlass(in: .rect(cornerRadius: 18))
            } else {
                Text("比較する2つの音源を選択してください")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .velouraAdaptiveGlass(in: .rect(cornerRadius: 18))
            }
        }
    }
}

private struct ComparisonVideoCanvasView: View {
    let model: ComparisonVideoWindowModel

    var body: some View {
        if let state = model.frameState {
            ComparisonVideoFrameView(
                state: state,
                orientation: model.orientation,
                onPositionChange: { element, position in
                    model.setDisplayPosition(position, for: element)
                }
            )
        } else {
            Color.black
        }
    }
}

private struct ComparisonVideoPlaybackControls: View {
    let model: ComparisonVideoWindowModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePreviewPlayback()
            } label: {
                Image(systemName: model.isPreviewPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPreviewPlaying ? "一時停止" : "再生")

            Text(timeText(model.outputTime))
                .monospacedDigit()

            Slider(
                value: Binding(
                    get: { min(max(model.outputTime, 0), maximumDuration) },
                    set: { newValue in
                        model.seekPreview(to: newValue)
                    }
                ),
                in: 0...maximumDuration
            )
            .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
            .accessibilityLabel("再生位置")
            .accessibilityValue("\(timeText(model.outputTime)) / \(timeText(duration))")

            Text(timeText(duration))
                .monospacedDigit()

            Image(systemName: model.previewVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { model.previewVolume },
                    set: { newValue in
                        model.setPreviewVolume(newValue)
                    }
                ),
                in: 0...1
            )
            .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
            .frame(width: 96)
            .accessibilityLabel("音量")
            .accessibilityValue("\(Int((model.previewVolume * 100).rounded()))パーセント")
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 640)
        .velouraAdaptiveGlass(in: .capsule, interactive: true)
    }

    private var duration: TimeInterval {
        model.plan?.outputDuration ?? 0
    }

    private var maximumDuration: TimeInterval {
        max(duration.isFinite ? duration : 0, 0.001)
    }

    private func timeText(_ time: TimeInterval) -> String {
        let seconds = max(Int(time.isFinite ? time.rounded(.down) : 0), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
