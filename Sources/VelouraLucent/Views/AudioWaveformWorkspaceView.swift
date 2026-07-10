import AppKit
import SwiftUI

struct AudioWaveformWorkspaceView: View {
    let preview: AudioPreviewController
    let inputFileURL: URL?
    let correctedFileURL: URL?
    let masteredFileURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            comparisonPicker
            playbackControls

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 0) {
                    waveformRow(target: .input, tint: .blue)
                    Divider()
                    waveformRow(target: .corrected, tint: .green)
                    Divider()
                    waveformRow(target: .mastered, tint: .orange)
                }
                .padding(8)
                .glassCard(cornerRadius: 16)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("波形と試聴比較")
                .font(.headline)
            Text(preview.playbackLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    private var comparisonPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                comparisonLabel
                comparisonSummary
                Spacer(minLength: 0)
            }
            comparisonPairPicker
        }
    }

    private var comparisonLabel: some View {
        Text("比較対象")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var comparisonPairPicker: some View {
        LiquidGlassSegmentedPicker(
            title: "比較対象",
            options: AudioComparisonPair.allCases,
            selection: binding(
                get: { preview.comparisonPair },
                set: { preview.setComparisonPair($0) }
            ),
            label: \.title
        )
    }

    private var comparisonSummary: some View {
        Text(preview.comparisonPair.summary)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var playbackControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                transportControls
                Divider().frame(height: 24)
                volumeControl
                loudnessComparisonToggle
            }

            VStack(alignment: .leading, spacing: 10) {
                transportControls
                HStack(spacing: 14) {
                    volumeControl
                    loudnessComparisonToggle
                }
            }
        }
    }

    private var transportControls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                Button("Aを再生") {
                    preview.playComparisonSide(.a)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .disabled(comparisonFileURL(for: .a) == nil)

                Button(playPauseTitle, systemImage: playPauseSystemImage) {
                    togglePlayback()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .controlSize(.large)
                .padding(10)
                .help(playPauseTitle)
                .accessibilityLabel(playPauseTitle)
                .disabled(activeComparisonFileURL == nil)

                Button("停止", systemImage: "stop.fill") {
                    preview.stopPlayback()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .padding(10)
                .help("停止")
                .disabled(preview.activeTarget == nil)

                Button("Bを再生") {
                    preview.playComparisonSide(.b)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .disabled(comparisonFileURL(for: .b) == nil)

                Button("A/B切替") {
                    preview.toggleComparisonSide()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(comparisonFileURL(for: .a) == nil || comparisonFileURL(for: .b) == nil)

                activeComparisonLabel
            }
            .padding(6)
            .velouraAdaptiveGlass(in: .capsule, interactive: true)
        }
        .fixedSize()
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(
                value: binding(
                    get: { Double(preview.playbackVolume) },
                    set: { preview.setPlaybackVolume(Float($0)) }
                ),
                in: 0 ... 1,
                step: 0.01
            )
            .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
            .frame(minWidth: 110, idealWidth: 150, maxWidth: 180)
            .accessibilityLabel("試聴音量")
            Text("\(Int((preview.playbackVolume * 100).rounded()))%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var loudnessComparisonToggle: some View {
        Toggle(
            "ラウドネス合わせ",
            isOn: binding(
                get: { preview.isLoudnessMatchedComparisonEnabled },
                set: { preview.setLoudnessMatchedComparisonEnabled($0) }
            )
        )
        .toggleStyle(.switch)
        .tint(LiquidGlassSegmentedPickerStyle.switchTint)
        .controlSize(.small)
        .fixedSize()
        .help("音量差を揃えて音質の違いを比較します")
    }

    private var activeComparisonLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(activeComparisonTint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("現在 \(preview.comparisonPair.title(for: preview.activeComparisonSide))")
                .font(.callout.weight(.bold))
                .foregroundStyle(activeComparisonTint)
        }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("現在再生中")
            .accessibilityValue(preview.comparisonPair.title(for: preview.activeComparisonSide))
    }

    private var activeComparisonTint: Color {
        switch preview.comparisonTarget(for: preview.activeComparisonSide) {
        case .input:
            return .blue
        case .corrected:
            return .green
        case .mastered:
            return .orange
        }
    }

    private func waveformRow(target: AudioPreviewTarget, tint: Color) -> some View {
        let state = preview.cardState(for: target)
        let snapshot = state.snapshot
        let comparisonSide = preview.comparisonSide(for: target)
        let fileURL = fileURL(for: target)

        return HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(target.rawValue)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let comparisonSide {
                    Text(preview.comparisonPair.title(for: comparisonSide))
                        .font(.callout.bold())
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .glassEffect(.regular.tint(tint.opacity(0.16)), in: .capsule)
                }
            }
            .frame(width: 112, alignment: .leading)

            SeekableWaveformView(
                samples: snapshot?.waveform ?? [],
                progress: state.playbackProgress,
                tint: tint,
                isActive: preview.activeTarget == target,
                isAvailable: snapshot != nil,
                onSeek: { progress in
                    preview.seek(to: progress, target: target)
                }
            )
            .frame(minWidth: 240, maxWidth: .infinity)

            Text(preview.playbackTimeText(for: target))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)

            HStack(spacing: 6) {
                Button("外部プレイヤーで開く", systemImage: "music.quarternote.3") {
                    guard let fileURL else { return }
                    openWithQuickTimePlayer(fileURL)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(fileURL == nil)
                .help(fileURL == nil ? "音声ファイルがありません" : "外部プレイヤーで開く")

                Button("Finderに表示", systemImage: "folder") {
                    guard let fileURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(fileURL == nil)
                .help(fileURL == nil ? "音声ファイルがありません" : "Finderに表示")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(target.rawValue)の波形")
    }

    private var playPauseTitle: String {
        guard let activeTarget = preview.activeTarget else { return "再生" }
        return preview.playbackState(for: activeTarget) == .playing ? "一時停止" : "再開"
    }

    private var playPauseSystemImage: String {
        guard let activeTarget = preview.activeTarget else { return "play.fill" }
        return preview.playbackState(for: activeTarget) == .playing ? "pause.fill" : "play.fill"
    }

    private var activeComparisonFileURL: URL? {
        comparisonFileURL(for: preview.activeComparisonSide)
    }

    private func togglePlayback() {
        if let activeTarget = preview.activeTarget, preview.playbackState(for: activeTarget) == .playing {
            preview.pausePlayback(target: activeTarget)
        } else {
            preview.playComparisonSide(preview.activeComparisonSide)
        }
    }

    private func comparisonFileURL(for side: AudioComparisonSide) -> URL? {
        fileURL(for: preview.comparisonTarget(for: side))
    }

    private func fileURL(for target: AudioPreviewTarget) -> URL? {
        switch target {
        case .input:
            return inputFileURL
        case .corrected:
            return correctedFileURL
        case .mastered:
            return masteredFileURL
        }
    }

    private func openWithQuickTimePlayer(_ fileURL: URL) {
        guard let quickTimeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.QuickTimePlayerX") else {
            NSWorkspace.shared.open(fileURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([fileURL], withApplicationAt: quickTimeURL, configuration: configuration)
    }

    private func binding<Value>(
        get: @escaping @MainActor () -> Value,
        set: @escaping @MainActor (Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { @MainActor in get() },
            set: { @MainActor newValue in set(newValue) }
        )
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        self
            .velouraAdaptiveGlass(in: .rect(cornerRadius: cornerRadius))
    }
}

private struct SeekableWaveformView: View {
    let samples: [Float]
    let progress: Double
    let tint: Color
    let isActive: Bool
    let isAvailable: Bool
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                if isAvailable, !samples.isEmpty {
                    waveform(color: tint.opacity(0.28))
                    waveform(color: tint.opacity(isActive ? 0.9 : 0.65))
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: proxy.size.width * clampedProgress)
                        }

                    Rectangle()
                        .fill(tint)
                        .frame(width: 2)
                        .offset(x: min(proxy.size.width * clampedProgress, max(proxy.size.width - 2, 0)))
                } else {
                    Text("音声なし")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isAvailable, proxy.size.width > 0 else { return }
                        onSeek(min(max(value.location.x / proxy.size.width, 0), 1))
                    }
            )
        }
        .frame(height: 58)
        .accessibilityLabel("再生位置")
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let increment = 0.02
            switch direction {
            case .increment:
                onSeek(min(progress + increment, 1))
            case .decrement:
                onSeek(max(progress - increment, 0))
            @unknown default:
                break
            }
        }
    }

    private func waveform(color: Color) -> some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            context.fill(envelopePath(in: size), with: .color(color))
        }
    }

    private func envelopePath(in size: CGSize) -> Path {
        let upperPoints = waveformPoints(in: size, isUpperSide: true)
        let lowerPoints = waveformPoints(in: size, isUpperSide: false).reversed()
        var path = Path()

        addSmoothCurve(points: upperPoints, to: &path, startsNewSubpath: true)
        addSmoothCurve(points: Array(lowerPoints), to: &path, startsNewSubpath: false)
        path.closeSubpath()

        return path
    }

    private func waveformPoints(in size: CGSize, isUpperSide: Bool) -> [CGPoint] {
        let step = size.width / CGFloat(max(samples.count - 1, 1))
        let centerY = size.height / 2
        let direction: CGFloat = isUpperSide ? -1 : 1

        return samples.enumerated().map { index, sample in
            let x = CGFloat(index) * step
            let normalizedAmplitude = min(max(CGFloat(abs(sample)), 0), 1)
            let amplitude = normalizedAmplitude * size.height * 0.42
            return CGPoint(x: x, y: centerY + direction * amplitude)
        }
    }

    private func addSmoothCurve(points: [CGPoint], to path: inout Path, startsNewSubpath: Bool) {
        guard let firstPoint = points.first else { return }

        if startsNewSubpath {
            path.move(to: firstPoint)
        } else {
            path.addLine(to: firstPoint)
        }

        guard points.count > 1 else { return }

        for index in 1..<points.count {
            let previousPoint = points[index - 1]
            let currentPoint = points[index]
            let midpoint = CGPoint(
                x: (previousPoint.x + currentPoint.x) / 2,
                y: (previousPoint.y + currentPoint.y) / 2
            )

            path.addQuadCurve(to: midpoint, control: previousPoint)

            if index == points.count - 1 {
                path.addQuadCurve(to: currentPoint, control: currentPoint)
            }
        }
    }
}
