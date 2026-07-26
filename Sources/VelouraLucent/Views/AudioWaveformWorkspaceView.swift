import AppKit
import SwiftUI

struct AudioWaveformWorkspaceView: View {
    let preview: AudioPreviewController
    let inputFileURL: URL?
    let correctedFileURL: URL?
    let masteredFileURL: URL?
    let onWillStartPlayback: @MainActor () -> Void
    @State private var hoveredWaveformProgress: Double?
    @State private var hoveredWaveformTarget: AudioPreviewTarget?

    private let waveformLabelColumnWidth: CGFloat = 112
    private let waveformTrailingColumnWidth: CGFloat = 140

    init(
        preview: AudioPreviewController,
        inputFileURL: URL?,
        correctedFileURL: URL?,
        masteredFileURL: URL?,
        onWillStartPlayback: @escaping @MainActor () -> Void = {}
    ) {
        self.preview = preview
        self.inputFileURL = inputFileURL
        self.correctedFileURL = correctedFileURL
        self.masteredFileURL = masteredFileURL
        self.onWillStartPlayback = onWillStartPlayback
    }

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
                    Divider()
                    waveformTimeRuler
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
                    onWillStartPlayback()
                    preview.playComparisonSide(.a)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .disabled(comparisonFileURL(for: .a) == nil)

                Button(playPauseTitle, systemImage: playPauseSystemImage) {
                    onWillStartPlayback()
                    preview.toggleComparisonPlayback()
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
                    onWillStartPlayback()
                    preview.playComparisonSide(.b)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .disabled(comparisonFileURL(for: .b) == nil)

                Button("A/B切替") {
                    onWillStartPlayback()
                    preview.toggleComparisonSide()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
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
            .frame(width: waveformLabelColumnWidth, alignment: .leading)

            SeekableWaveformView(
                samples: snapshot?.waveform ?? [],
                progress: state.playbackProgress,
                hoverProgress: hoveredWaveformProgress,
                duration: snapshot?.duration ?? 0,
                tint: tint,
                isActive: preview.activeTarget == target,
                isAvailable: snapshot != nil,
                showsHoverTime: hoveredWaveformTarget == target,
                onSeek: { progress in
                    preview.seek(to: progress, target: target)
                },
                onHover: { progress in
                    if let progress {
                        hoveredWaveformProgress = progress
                        hoveredWaveformTarget = target
                    } else if hoveredWaveformTarget == target {
                        hoveredWaveformProgress = nil
                        hoveredWaveformTarget = nil
                    }
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

    private var waveformTimeRuler: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: waveformLabelColumnWidth)

            WaveformTimeRulerView(duration: waveformDuration)
                .frame(minWidth: 240, maxWidth: .infinity)

            Color.clear
                .frame(width: waveformTrailingColumnWidth)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var waveformDuration: TimeInterval {
        AudioPreviewTarget.allCases
            .compactMap { preview.cardState(for: $0).snapshot?.duration }
            .max() ?? 0
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

struct SeekableWaveformView: View {
    let samples: [WaveformEnvelopeSample]
    let progress: Double
    let hoverProgress: Double?
    let duration: TimeInterval
    let tint: Color
    let isActive: Bool
    let isAvailable: Bool
    let showsHoverTime: Bool
    let onSeek: (Double) -> Void
    let onHover: (Double?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                if isAvailable, !samples.isEmpty {
                    waveform(playedWidth: proxy.size.width * clampedProgress)

                    if let hoverProgress {
                        let hoverX = min(
                            proxy.size.width * min(max(hoverProgress, 0), 1),
                            max(proxy.size.width - 1, 0)
                        )
                        Rectangle()
                            .fill(.secondary.opacity(0.65))
                            .frame(width: 1)
                            .offset(x: hoverX)

                        if showsHoverTime {
                            Text(waveformTimeText(duration * hoverProgress))
                                .font(.callout.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .velouraAdaptiveGlass(in: .capsule)
                                .position(
                                    x: min(max(hoverX, 38), max(proxy.size.width - 38, 38)),
                                    y: 13
                                )
                        }
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
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    guard isAvailable, proxy.size.width > 0 else { return }
                    onHover(min(max(location.x / proxy.size.width, 0), 1))
                case .ended:
                    onHover(nil)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isAvailable, proxy.size.width > 0 else { return }
                        onSeek(min(max(value.location.x / proxy.size.width, 0), 1))
                    }
            )
        }
        .frame(height: 68)
        .accessibilityLabel("再生位置")
        .accessibilityValue(
            "\(waveformTimeText(duration * min(max(progress, 0), 1))) / \(waveformTimeText(duration))"
        )
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

    private func waveform(playedWidth: CGFloat) -> some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let renderedSamples = renderedSamples(for: size.width)
            let peakPath = envelopePath(samples: renderedSamples, in: size)
            let rmsPath = rmsEnvelopePath(samples: renderedSamples, in: size)

            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: size.height / 2))
            centerLine.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                centerLine,
                with: .color(.secondary.opacity(0.18)),
                lineWidth: 1
            )

            context.fill(peakPath, with: .color(tint.opacity(0.20)))
            context.fill(rmsPath, with: .color(tint.opacity(isActive ? 0.48 : 0.36)))

            var playedContext = context
            playedContext.clip(
                to: Path(
                    CGRect(
                        x: 0,
                        y: 0,
                        width: min(max(playedWidth, 0), size.width),
                        height: size.height
                    )
                )
            )
            playedContext.fill(peakPath, with: .color(tint.opacity(0.62)))
            playedContext.fill(rmsPath, with: .color(tint.opacity(isActive ? 0.95 : 0.78)))
        }
    }

    private func envelopePath(
        samples: [WaveformEnvelopeSample],
        in size: CGSize
    ) -> Path {
        let upperPoints = waveformPoints(
            values: samples.map(\.maximum),
            in: size
        )
        let lowerPoints = waveformPoints(
            values: samples.map(\.minimum),
            in: size
        ).reversed()
        var path = Path()

        addLinearCurve(points: upperPoints, to: &path, startsNewSubpath: true)
        addLinearCurve(points: Array(lowerPoints), to: &path, startsNewSubpath: false)
        path.closeSubpath()

        return path
    }

    private func rmsEnvelopePath(
        samples: [WaveformEnvelopeSample],
        in size: CGSize
    ) -> Path {
        let upperRMSValues = samples.map { sample in
            min(sample.rms, max(sample.maximum, 0))
        }
        let lowerRMSValues = samples.map { sample in
            max(-sample.rms, min(sample.minimum, 0))
        }
        let upperPoints = waveformPoints(values: upperRMSValues, in: size)
        let lowerPoints = waveformPoints(
            values: lowerRMSValues,
            in: size
        ).reversed()
        var path = Path()

        addLinearCurve(points: upperPoints, to: &path, startsNewSubpath: true)
        addLinearCurve(points: Array(lowerPoints), to: &path, startsNewSubpath: false)
        path.closeSubpath()

        return path
    }

    private func waveformPoints(
        values: [Float],
        in size: CGSize
    ) -> [CGPoint] {
        let step = size.width / CGFloat(max(values.count - 1, 1))
        let centerY = size.height / 2

        return values.enumerated().map { index, sample in
            let x = CGFloat(index) * step
            let normalizedAmplitude = min(max(CGFloat(sample), -1), 1)
            return CGPoint(
                x: x,
                y: centerY - normalizedAmplitude * size.height * 0.42
            )
        }
    }

    private func renderedSamples(for width: CGFloat) -> [WaveformEnvelopeSample] {
        let targetCount = min(max(Int(width.rounded(.up)), 1), samples.count)
        guard targetCount < samples.count else { return samples }

        let samplesPerGroup = Double(samples.count) / Double(targetCount)
        return (0..<targetCount).map { groupIndex in
            let startIndex = Int(floor(Double(groupIndex) * samplesPerGroup))
            let endIndex = min(
                max(Int(ceil(Double(groupIndex + 1) * samplesPerGroup)), startIndex + 1),
                samples.count
            )
            let group = samples[startIndex..<endIndex]
            var minimum = Float.greatestFiniteMagnitude
            var maximum = -Float.greatestFiniteMagnitude
            var rmsEnergy = 0.0
            for sample in group {
                minimum = min(minimum, sample.minimum)
                maximum = max(maximum, sample.maximum)
                rmsEnergy += Double(sample.rms) * Double(sample.rms)
            }
            return WaveformEnvelopeSample(
                minimum: minimum,
                maximum: maximum,
                rms: Float(sqrt(rmsEnergy / Double(group.count)))
            )
        }
    }

    private func addLinearCurve(points: [CGPoint], to path: inout Path, startsNewSubpath: Bool) {
        guard let firstPoint = points.first else { return }

        if startsNewSubpath {
            path.move(to: firstPoint)
        } else {
            path.addLine(to: firstPoint)
        }

        guard points.count > 1 else { return }
        path.addLines(Array(points.dropFirst()))
    }
}
