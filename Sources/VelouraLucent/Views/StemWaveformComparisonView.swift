import AppKit
import SwiftUI

/// 選択中Stemの検証済みraw／補正後だけを手動試聴する独立欄です。
///
/// 2mix試聴とは状態を共有せず、DSP採否やマスタリング入力にも接続しません。
@MainActor
struct StemWaveformComparisonView: View {
    @Bindable var model: StemModeWorkspaceModel
    @State private var hoveredWaveformProgress: Double?
    @State private var hoveredWaveformTarget: AudioPreviewTarget?
    @State private var waveformViewport = WaveformViewport()
    @State private var waveformPanStartProgress: Double?
    @State private var isWaveformPanning = false
    @State private var rawWaveformHeight = WaveformTrackResizeHandle.defaultHeight
    @State private var correctedWaveformHeight = WaveformTrackResizeHandle.defaultHeight

    private let waveformLabelColumnWidth: CGFloat = 170
    private let waveformTrailingColumnWidth: CGFloat = 140

    private var preview: AudioPreviewController {
        model.stemPreviewController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            rolePicker
            playbackControls

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 0) {
                    waveformRow(
                        target: .input,
                        title: "分離直後（raw）",
                        sideTitle: "A",
                        fileURL: model.selectedRawStemPreviewURL,
                        tint: .blue,
                        height: $rawWaveformHeight
                    )
                    Divider()
                    waveformRow(
                        target: .corrected,
                        title: "補正後Stem",
                        sideTitle: "B",
                        fileURL: model.selectedCorrectedStemPreviewURL,
                        tint: .green,
                        height: $correctedWaveformHeight
                    )
                    Divider()
                    waveformTimeRuler
                }
                .padding(8)
                .velouraAdaptiveGlass(in: .rect(cornerRadius: 16))
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear(perform: model.refreshSelectedStemPreviewSources)
        .onChange(of: model.selectedRawStemPreviewURL) {
            model.refreshSelectedStemPreviewSources()
        }
        .onChange(of: model.selectedCorrectedStemPreviewURL) {
            model.refreshSelectedStemPreviewSources()
        }
        .onChange(of: model.selectedInputURL) {
            resetWaveformViewport()
        }
        .onChange(of: model.selectedCorrectionRole) {
            resetWaveformViewport()
        }
        .onChange(of: playingWaveformProgress) {
            guard
                !isWaveformPanning,
                let playingWaveformProgress
            else {
                return
            }
            waveformViewport.followPlayback(playingWaveformProgress)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("4 Stem 波形")
                .font(.headline)
            Text(stemPlaybackLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("表示するStem")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            LiquidGlassSegmentedPicker(
                title: "表示するStem",
                options: StemRole.allCases,
                selection: binding(
                    get: { model.selectedCorrectionRole },
                    set: { model.selectCorrectionRole($0) }
                ),
                label: \.stemModeDisplayTitle
            )
        }
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
                Button("rawを再生") {
                    beginStemPlayback {
                        preview.playComparisonSide(.a)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .disabled(model.selectedRawStemPreviewURL == nil)

                Button(playPauseTitle, systemImage: playPauseSystemImage) {
                    beginStemPlayback {
                        preview.toggleComparisonPlayback()
                    }
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

                Button("補正後を再生") {
                    beginStemPlayback {
                        preview.playComparisonSide(.b)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .disabled(model.selectedCorrectedStemPreviewURL == nil)

                Button("raw／補正後切替") {
                    beginStemPlayback {
                        preview.toggleComparisonSide()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .disabled(
                    model.selectedRawStemPreviewURL == nil
                        || model.selectedCorrectedStemPreviewURL == nil
                )

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
            .accessibilityLabel("Stem試聴音量")
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
        .help("rawと補正後の音量差を試聴時だけ揃えます")
    }

    private var activeComparisonLabel: some View {
        let isRaw = preview.activeComparisonSide == .a
        let tint: Color = isRaw ? .blue : .green

        return HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(isRaw ? "現在 raw" : "現在 補正後")
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("現在のStem試聴対象")
        .accessibilityValue(isRaw ? "分離直後" : "補正後")
    }

    private func waveformRow(
        target: AudioPreviewTarget,
        title: String,
        sideTitle: String,
        fileURL: URL?,
        tint: Color,
        height: Binding<CGFloat>
    ) -> some View {
        let state = preview.cardState(for: target)

        return HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(sideTitle)
                    .font(.callout.bold())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(tint.opacity(0.16)), in: .capsule)
            }
            .frame(width: waveformLabelColumnWidth, alignment: .leading)

            SeekableWaveformView(
                samples: state.snapshot?.waveform ?? [],
                progress: state.playbackProgress,
                hoverProgress: hoveredWaveformProgress,
                duration: state.snapshot?.duration ?? 0,
                viewport: waveformViewport,
                tint: tint,
                isActive: preview.activeTarget == target,
                isAvailable: state.snapshot != nil,
                showsHoverTime: hoveredWaveformTarget == target,
                onSeek: { progress in
                    preview.seek(to: progress, target: target)
                },
                onPanChanged: { translationFraction in
                    panWaveform(by: translationFraction)
                },
                onPanEnded: { translationFraction in
                    finishWaveformPan(by: translationFraction)
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
            .frame(height: height.wrappedValue)

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
        .overlay(alignment: .bottom) {
            WaveformTrackResizeHandle(
                title: title,
                height: height
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.selectedCorrectionRole.stemModeDisplayTitle)の\(title)波形")
    }

    private var waveformTimeRuler: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: waveformLabelColumnWidth)

            GeometryReader { proxy in
                let maximumZoomScale = WaveformViewport.maximumZoomScale(
                    sampleCount: waveformSampleCount,
                    displayWidth: Double(proxy.size.width)
                )

                VStack(alignment: .trailing, spacing: 6) {
                    WaveformTimeRulerView(
                        duration: waveformDuration,
                        viewport: waveformViewport
                    )

                    WaveformZoomControls(
                        viewport: $waveformViewport,
                        centerProgress: waveformZoomCenterProgress,
                        maximumZoomScale: maximumZoomScale
                    )
                }
            }
            .frame(minWidth: 240, maxWidth: .infinity)
            .frame(height: 78)

            Color.clear
                .frame(width: waveformTrailingColumnWidth)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var waveformDuration: TimeInterval {
        [AudioPreviewTarget.input, .corrected]
            .compactMap { preview.cardState(for: $0).snapshot?.duration }
            .max() ?? 0
    }

    private var waveformSampleCount: Int {
        [AudioPreviewTarget.input, .corrected]
            .compactMap { preview.cardState(for: $0).snapshot?.waveform.count }
            .max() ?? 0
    }

    private var waveformZoomCenterProgress: Double {
        if let activeTarget = preview.activeTarget {
            return preview.cardState(for: activeTarget).playbackProgress
        }
        return preview.cardState(
            for: preview.comparisonTarget(for: preview.activeComparisonSide)
        ).playbackProgress
    }

    private var playingWaveformProgress: Double? {
        guard
            let activeTarget = preview.activeTarget,
            preview.playbackState(for: activeTarget) == .playing
        else {
            return nil
        }
        return preview.cardState(for: activeTarget).playbackProgress
    }

    private func panWaveform(by horizontalTranslationFraction: Double) {
        guard waveformViewport.canZoomOut else { return }

        if waveformPanStartProgress == nil {
            waveformPanStartProgress = waveformViewport.startProgress
            isWaveformPanning = true
        }
        guard let waveformPanStartProgress else { return }
        waveformViewport.pan(
            from: waveformPanStartProgress,
            horizontalTranslationFraction: horizontalTranslationFraction
        )
    }

    private func finishWaveformPan(by horizontalTranslationFraction: Double) {
        guard let waveformPanStartProgress else { return }
        waveformViewport.pan(
            from: waveformPanStartProgress,
            horizontalTranslationFraction: horizontalTranslationFraction
        )
        self.waveformPanStartProgress = nil
        isWaveformPanning = false

        if let playingWaveformProgress {
            waveformViewport.followPlayback(playingWaveformProgress)
        }
    }

    private func resetWaveformViewport() {
        waveformViewport.reset()
        hoveredWaveformProgress = nil
        hoveredWaveformTarget = nil
        waveformPanStartProgress = nil
        isWaveformPanning = false
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
        switch preview.activeComparisonSide {
        case .a:
            model.selectedRawStemPreviewURL
        case .b:
            model.selectedCorrectedStemPreviewURL
        }
    }

    private var stemPlaybackLabel: String {
        guard let activeTarget = preview.activeTarget else { return "未再生" }
        let targetTitle = activeTarget == .input ? "raw" : "補正後Stem"
        switch preview.playbackState(for: activeTarget) {
        case .playing:
            return "\(targetTitle)を再生中"
        case .paused:
            return "\(targetTitle)を一時停止中"
        case .stopped:
            return "停止中"
        }
    }

    private func beginStemPlayback(_ action: () -> Void) {
        model.stopTwoMixPreviewPlayback()
        action()
    }

    private func openWithQuickTimePlayer(_ fileURL: URL) {
        guard let quickTimeURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.QuickTimePlayerX"
        ) else {
            NSWorkspace.shared.open(fileURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: quickTimeURL,
            configuration: configuration
        )
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
