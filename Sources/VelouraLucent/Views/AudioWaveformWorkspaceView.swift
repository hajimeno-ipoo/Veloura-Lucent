import AppKit
import SwiftUI

struct AudioWaveformTrackPresentation: Identifiable {
    let target: AudioPreviewTarget
    let title: String
    let tint: Color
    let fileURL: URL?
    let accessibilityLabel: String

    var id: String { target.rawValue }
}

enum AudioWaveformComparisonPresentation {
    case selectable
    case fixed(summary: String)
}

struct AudioWaveformWorkspaceView: View {
    let preview: AudioPreviewController
    let inputFileURL: URL?
    let correctedFileURL: URL?
    let masteredFileURL: URL?
    let playbackInterlocks: [AudioPreviewController]
    let workspaceTitle: String
    let playbackStatusText: String?
    let tracks: [AudioWaveformTrackPresentation]
    let comparisonPresentation: AudioWaveformComparisonPresentation
    let comparisonPairLabel: (AudioComparisonPair) -> String
    let comparisonPairSummary: (AudioComparisonPair) -> String
    let comparisonPairPickerMaxWidth: CGFloat
    let sideAButtonTitle: String
    let sideBButtonTitle: String
    let switchButtonTitle: String
    let activeSideATitle: String
    let activeSideBTitle: String
    let volumeAccessibilityLabel: String
    let loudnessHelp: String
    let waveformLabelColumnWidth: CGFloat
    let topAccessory: AnyView?
    let resetToken: String
    let showsComparisonRepeat: Bool
    @State private var hoveredWaveformProgress: Double?
    @State private var hoveredWaveformTarget: AudioPreviewTarget?
    @State private var waveformViewport = WaveformViewport()
    @State private var waveformPanStartProgress: Double?
    @State private var isWaveformPanning = false
    @State private var inputWaveformHeight = WaveformTrackResizeHandle.defaultHeight
    @State private var correctedWaveformHeight = WaveformTrackResizeHandle.defaultHeight
    @State private var masteredWaveformHeight = WaveformTrackResizeHandle.defaultHeight
    @State private var maximumWaveformZoomScale = 1.0
    @GestureState private var comparisonRepeatDrag: Range<TimeInterval>?
    @FocusState private var isWaveformKeyboardFocused: Bool
    @Environment(\.locale) private var locale

    private let waveformTrailingColumnWidth: CGFloat = 140
    private let waveformKeyboardPanStep = 0.1

    init(
        preview: AudioPreviewController,
        inputFileURL: URL?,
        correctedFileURL: URL?,
        masteredFileURL: URL?,
        correctedTitle: String = AudioPreviewTarget.corrected.rawValue,
        correctedAccessibilityLabel: String = "補正後の波形",
        playbackStatusText: String? = nil,
        comparisonPairLabel: @escaping (AudioComparisonPair) -> String = \.title,
        comparisonPairSummary: @escaping (AudioComparisonPair) -> String = \.summary,
        comparisonPairPickerMaxWidth: CGFloat = 360,
        playbackInterlocks: [AudioPreviewController] = [],
        showsComparisonRepeat: Bool = false
    ) {
        self.preview = preview
        self.inputFileURL = inputFileURL
        self.correctedFileURL = correctedFileURL
        self.masteredFileURL = masteredFileURL
        self.playbackInterlocks = playbackInterlocks
        self.workspaceTitle = "波形と試聴比較"
        self.playbackStatusText = playbackStatusText
        self.tracks = [
            AudioWaveformTrackPresentation(
                target: .input,
                title: AudioPreviewTarget.input.rawValue,
                tint: .blue,
                fileURL: inputFileURL,
                accessibilityLabel: "入力の波形"
            ),
            AudioWaveformTrackPresentation(
                target: .corrected,
                title: correctedTitle,
                tint: .green,
                fileURL: correctedFileURL,
                accessibilityLabel: correctedAccessibilityLabel
            ),
            AudioWaveformTrackPresentation(
                target: .mastered,
                title: AudioPreviewTarget.mastered.rawValue,
                tint: .orange,
                fileURL: masteredFileURL,
                accessibilityLabel: "最終版の波形"
            ),
        ]
        self.comparisonPresentation = .selectable
        self.comparisonPairLabel = comparisonPairLabel
        self.comparisonPairSummary = comparisonPairSummary
        self.comparisonPairPickerMaxWidth = comparisonPairPickerMaxWidth
        self.sideAButtonTitle = "Aを再生"
        self.sideBButtonTitle = "Bを再生"
        self.switchButtonTitle = "A/B切替"
        self.activeSideATitle = "A"
        self.activeSideBTitle = "B"
        self.volumeAccessibilityLabel = "試聴音量"
        self.loudnessHelp = "音量差を揃えて音質の違いを比較します"
        self.waveformLabelColumnWidth = 150
        self.topAccessory = nil
        self.resetToken = inputFileURL?.path ?? ""
        self.showsComparisonRepeat = showsComparisonRepeat
    }

    init(
        preview: AudioPreviewController,
        workspaceTitle: String,
        playbackStatusText: String? = nil,
        tracks: [AudioWaveformTrackPresentation],
        comparisonSummary: String,
        sideAButtonTitle: String,
        sideBButtonTitle: String,
        switchButtonTitle: String,
        activeSideATitle: String,
        activeSideBTitle: String,
        volumeAccessibilityLabel: String,
        loudnessHelp: String,
        waveformLabelColumnWidth: CGFloat = 170,
        resetToken: String,
        topAccessory: AnyView? = nil,
        playbackInterlocks: [AudioPreviewController] = [],
        showsComparisonRepeat: Bool = false
    ) {
        self.preview = preview
        self.inputFileURL = tracks.first(where: { $0.target == .input })?.fileURL
        self.correctedFileURL = tracks.first(where: { $0.target == .corrected })?.fileURL
        self.masteredFileURL = tracks.first(where: { $0.target == .mastered })?.fileURL
        self.playbackInterlocks = playbackInterlocks
        self.workspaceTitle = workspaceTitle
        self.playbackStatusText = playbackStatusText
        self.tracks = tracks
        self.comparisonPresentation = .fixed(summary: comparisonSummary)
        self.comparisonPairLabel = \.title
        self.comparisonPairSummary = \.summary
        self.comparisonPairPickerMaxWidth = 360
        self.sideAButtonTitle = sideAButtonTitle
        self.sideBButtonTitle = sideBButtonTitle
        self.switchButtonTitle = switchButtonTitle
        self.activeSideATitle = activeSideATitle
        self.activeSideBTitle = activeSideBTitle
        self.volumeAccessibilityLabel = volumeAccessibilityLabel
        self.loudnessHelp = loudnessHelp
        self.waveformLabelColumnWidth = waveformLabelColumnWidth
        self.topAccessory = topAccessory
        self.resetToken = resetToken
        self.showsComparisonRepeat = showsComparisonRepeat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let topAccessory {
                topAccessory
            }
            comparisonPicker
            playbackControls

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 0) {
                    waveformTimeRuler
                    ForEach(tracks.indices, id: \.self) { index in
                        waveformRow(
                            track: tracks[index],
                            height: waveformHeight(for: tracks[index].target)
                        )
                        Divider()
                    }
                    waveformZoomControls
                }
                .padding(8)
                .glassCard(cornerRadius: 16)
                .focusable()
                .focused($isWaveformKeyboardFocused)
                .focusedSceneValue(
                    \.velouraWaveformPresentationState,
                    waveformPresentationState
                )
                .focusEffectDisabled()
                .onKeyPress(
                    keys: [.leftArrow, .rightArrow],
                    phases: .all
                ) { keyPress in
                    guard waveformViewport.canZoomOut else { return .ignored }
                    guard keyPress.phase != .up else { return .handled }

                    switch keyPress.key {
                    case .leftArrow:
                        waveformViewport.moveVisibleRange(
                            byVisibleSpanFraction: -waveformKeyboardPanStep
                        )
                    case .rightArrow:
                        waveformViewport.moveVisibleRange(
                            byVisibleSpanFraction: waveformKeyboardPanStep
                        )
                    default:
                        return .ignored
                    }
                    return .handled
                }
            }
        }
        .environment(\.locale, locale)
        .onChange(of: resetToken) {
            waveformViewport.reset()
            hoveredWaveformProgress = nil
            hoveredWaveformTarget = nil
            waveformPanStartProgress = nil
            isWaveformPanning = false
            isWaveformKeyboardFocused = false
        }
        .onChange(of: playingWaveformProgress) {
            guard
                !isWaveformPanning,
                !preview.isPlayingComparisonRepeat,
                let playingWaveformProgress
            else {
                return
            }
            waveformViewport.followPlayback(playingWaveformProgress)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            AppLocalizedText(workspaceTitle)
                .font(.title3.bold())
            Text(localizedPlaybackStatus)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    private var localizedPlaybackStatus: String {
        if let playbackStatusText {
            return AppLanguageSettings.string(playbackStatusText)
        }

        let label = preview.playbackLabel
        for target in AudioPreviewTarget.allCases {
            let title = AppLanguageSettings.string(target.rawValue)
            if label == "\(target.rawValue)を一時停止中" {
                return AppLanguageSettings.format("%@を一時停止中", title)
            }
            if label == "\(target.rawValue)を再生中" {
                return AppLanguageSettings.format("%@を再生中", title)
            }
            for side in ["A", "B"] where label == "\(side) \(target.rawValue)を再生中" {
                return AppLanguageSettings.format("%@ %@を再生中", side, title)
            }
        }
        return AppLanguageSettings.string(label)
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
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var comparisonPairPicker: some View {
        Group {
            switch comparisonPresentation {
            case .selectable:
                LiquidGlassSegmentedPicker(
                    title: "比較対象",
                    options: AudioComparisonPair.allCases,
                    selection: binding(
                        get: { preview.comparisonPair },
                        set: { preview.setComparisonPair($0) }
                    ),
                    label: comparisonPairLabel,
                    maxWidth: comparisonPairPickerMaxWidth
                )
            case .fixed:
                EmptyView()
            }
        }
    }

    private var comparisonSummary: some View {
        AppLocalizedText(comparisonSummaryText)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var playbackControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                transportControlsWithRepeatStatus
                Divider().frame(height: 24)
                volumeControl
                loudnessComparisonToggle
            }

            VStack(alignment: .leading, spacing: 10) {
                transportControlsWithRepeatStatus
                HStack(spacing: 14) {
                    volumeControl
                    loudnessComparisonToggle
                }
            }
        }
    }

    @ViewBuilder
    private var transportControlsWithRepeatStatus: some View {
        if showsComparisonRepeat {
            HStack(spacing: 10) {
                transportControls
                comparisonRepeatStatus
            }
        } else {
            transportControls
        }
    }

    private var comparisonRepeatStatus: some View {
        let maximumTime = comparisonRepeatTimeText(preview.comparisonRepeatMaximumTime)
        let showsRangeHint = showsComparisonRepeatRangeHint
        let statusFont = Font.system(size: 15)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                AppLocalizedText("リピート範囲")
                    .font(statusFont.weight(.semibold))

                ZStack(alignment: .leading) {
                    Text("\(maximumTime) – \(maximumTime)")
                        .font(.callout.monospacedDigit())
                        .hidden()
                        .accessibilityHidden(true)
                    AppLocalizedText("未指定")
                        .hidden()
                        .accessibilityHidden(true)
                    AppLocalizedText("目盛りをドラッグ")
                        .font(statusFont.weight(.semibold))
                        .fixedSize()
                        .opacity(showsRangeHint ? 1 : 0)
                        .accessibilityHidden(!showsRangeHint)

                    if let range = comparisonRepeatDrag ?? preview.comparisonRepeatRange {
                        Text("\(comparisonRepeatTimeText(range.lowerBound)) – \(comparisonRepeatTimeText(range.upperBound))")
                            .font(statusFont.monospacedDigit().width(.condensed))
                            .minimumScaleFactor(0.75)
                    } else if !showsRangeHint {
                        AppLocalizedText("未指定")
                    }
                }
                .lineLimit(1)
            }
            .font(statusFont)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(Color.primary)
            .accessibilityElement(children: .combine)

            WaveformTransportButton(
                title: "リピート範囲をクリア",
                systemImage: "eraser",
                layout: .icon,
                iconFont: .system(size: 22, weight: .semibold),
                isDisabled: preview.comparisonRepeatRange == nil
            ) {
                preview.clearComparisonRepeatRange()
            }
            .fixedSize()
        }
    }

    private func comparisonRepeatTimeText(_ time: TimeInterval) -> String {
        let milliseconds = Int((time * 1_000).rounded())
        return waveformTimeText(Double(milliseconds / 1_000))
            + String(format: ".%03d", milliseconds % 1_000)
    }

    private var transportControls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                WaveformTransportButton(
                    title: sideAButtonTitle,
                    isSelected: preview.activeComparisonSide == .a
                        && comparisonFileURL(for: .a) != nil,
                    isDisabled: comparisonFileURL(for: .a) == nil || !preview.canStartComparisonRepeat,
                    showsSelectedAccessibilityTrait: true
                ) {
                    prepareForPlayback()
                    preview.playComparisonSide(.a)
                }

                WaveformTransportButton(
                    title: playPauseTitle,
                    systemImage: playPauseSystemImage,
                    layout: .icon,
                    isSelected: preview.isComparisonPlaybackRunning,
                    isDisabled: activeComparisonFileURL == nil || !preview.canStartComparisonRepeat
                ) {
                    prepareForPlayback()
                    preview.toggleComparisonPlayback()
                }

                WaveformTransportButton(
                    title: "停止",
                    systemImage: "stop.fill",
                    layout: .icon,
                    isDisabled: preview.activeTarget == nil
                ) {
                    preview.stopPlayback()
                }

                WaveformTransportButton(
                    title: sideBButtonTitle,
                    isSelected: preview.activeComparisonSide == .b
                        && comparisonFileURL(for: .b) != nil,
                    isDisabled: comparisonFileURL(for: .b) == nil || !preview.canStartComparisonRepeat,
                    showsSelectedAccessibilityTrait: true
                ) {
                    prepareForPlayback()
                    preview.playComparisonSide(.b)
                }

                WaveformTransportButton(
                    title: switchButtonTitle,
                    isDisabled: comparisonFileURL(for: .a) == nil
                        || comparisonFileURL(for: .b) == nil
                ) {
                    prepareForPlayback()
                    preview.toggleComparisonSide()
                }

                if showsComparisonRepeat {
                    WaveformTransportButton(
                        title: "区間リピート",
                        isSelected: preview.isComparisonRepeatEnabled,
                        isDisabled: !preview.isComparisonRepeatEnabled
                            && (preview.comparisonRepeatMaximumTime <= 0 || preview.isComparisonPlaybackRunning),
                        showsSelectedAccessibilityTrait: true
                    ) {
                        preview.setComparisonRepeatEnabled(!preview.isComparisonRepeatEnabled)
                    }
                }

                activeComparisonLabel
                    .opacity(preview.isComparisonPlaybackRunning ? 1 : 0)
                    .accessibilityHidden(!preview.isComparisonPlaybackRunning)
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
            .accessibilityLabel(AppLanguageSettings.string(volumeAccessibilityLabel))
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
        .help(AppLanguageSettings.string(loudnessHelp))
    }

    private var activeComparisonLabel: some View {
        let displayTint = activeComparisonTint.opacity(0.65)

        return HStack(spacing: 6) {
            Circle()
                .fill(displayTint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(AppLanguageSettings.format("現在 %@", AppLanguageSettings.string(activeSideTitle)))
                .font(.title3.weight(.bold))
                .foregroundStyle(displayTint)
        }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("現在再生中")
            .accessibilityValue(AppLanguageSettings.string(activeSideTitle))
    }

    private var activeComparisonTint: Color {
        track(for: preview.comparisonTarget(for: preview.activeComparisonSide))?.tint
            ?? .secondary
    }

    private func waveformRow(
        track: AudioWaveformTrackPresentation,
        height: Binding<CGFloat>
    ) -> some View {
        let target = track.target
        let tint = track.tint
        let state = preview.cardState(for: target)
        let snapshot = state.snapshot
        let comparisonSide = preview.comparisonSide(for: target)
        let isSelected = comparisonSide.map {
            $0 == preview.activeComparisonSide
        } ?? false
        let fileURL = track.fileURL

        return waveformColumns {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                AppLocalizedText(track.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let comparisonSide {
                    AppLocalizedText(sideTitle(for: comparisonSide))
                        .font(.body.bold())
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .glassEffect(.regular.tint(tint.opacity(0.16)), in: .capsule)
                }
            }
        } waveform: {
            SeekableWaveformView(
                samples: snapshot?.waveform ?? [],
                progress: state.playbackProgress,
                hoverProgress: hoveredWaveformProgress,
                duration: snapshot?.duration ?? 0,
                viewport: waveformViewport,
                tint: tint,
                isSelected: isSelected,
                isAvailable: snapshot != nil,
                showsHoverTime: hoveredWaveformTarget == target,
                onSeek: { progress in
                    preview.seek(to: progress, target: target)
                },
                onActivateKeyboardPan: {
                    isWaveformKeyboardFocused = true
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
            .frame(height: height.wrappedValue)
        } trailing: {
            HStack(spacing: 12) {
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
                    .help(AppLanguageSettings.string(fileURL == nil ? "音声ファイルがありません" : "外部プレイヤーで開く"))

                    Button("Finderに表示", systemImage: "folder") {
                        guard let fileURL else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(fileURL == nil)
                    .help(AppLanguageSettings.string(fileURL == nil ? "音声ファイルがありません" : "Finderに表示"))
                }
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            WaveformTrackResizeHandle(
                title: track.title,
                height: height
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLanguageSettings.string(track.accessibilityLabel))
    }

    private var waveformTimeRuler: some View {
        waveformColumns {
            Color.clear
        } waveform: {
            if showsComparisonRepeat {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    WaveformTimeRulerView(duration: waveformDuration, viewport: waveformViewport)
                        .background(alignment: .leading) {
                            if let band = comparisonRepeatBand(for: comparisonRepeatDrag ?? preview.comparisonRepeatRange, width: width) {
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.accentColor.opacity(preview.isComparisonRepeatEnabled ? 0.28 : 0.12))
                                        .frame(width: band.visibleWidth)
                                        .offset(x: band.visibleStart)

                                    if canDragComparisonRepeat {
                                        if let startGrip = band.startGrip {
                                            comparisonRepeatGrip(at: startGrip, width: width)
                                        }
                                        if let endGrip = band.endGrip {
                                            comparisonRepeatGrip(at: endGrip, width: width)
                                        }
                                    }
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .updating($comparisonRepeatDrag) { drag, range, _ in
                                    range = comparisonRepeatRange(for: drag, width: width)
                                }
                                .onEnded { drag in
                                    if let range = comparisonRepeatRange(for: drag, width: width) {
                                        preview.setComparisonRepeatRange(range)
                                    }
                                },
                            including: canDragComparisonRepeat ? .gesture : .none
                        )
                }
            } else {
                WaveformTimeRulerView(duration: waveformDuration, viewport: waveformViewport)
            }
        } trailing: {
            Color.clear
        }
        .frame(height: 28)
    }

    private var canDragComparisonRepeat: Bool {
        preview.isComparisonRepeatEnabled && !preview.isComparisonPlaybackRunning
    }

    private var showsComparisonRepeatRangeHint: Bool {
        canDragComparisonRepeat && (comparisonRepeatDrag ?? preview.comparisonRepeatRange) == nil
    }

    private func comparisonRepeatBand(for range: Range<TimeInterval>?, width: CGFloat) -> ComparisonRepeatBand? {
        guard let range, waveformDuration > 0, width > 0 else { return nil }
        let start = waveformViewport.startProgress * waveformDuration
        let secondsPerPoint = waveformViewport.visibleProgressSpan * waveformDuration / width
        return ComparisonRepeatBand(
            start: (range.lowerBound - start) / secondsPerPoint,
            end: (range.upperBound - start) / secondsPerPoint,
            width: width
        )
    }

    private func comparisonRepeatGrip(at x: CGFloat, width: CGFloat) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 3)
            .offset(x: min(max(x - 1.5, 0), max(width - 3, 0)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func comparisonRepeatRange(for drag: DragGesture.Value, width: CGFloat) -> Range<TimeInterval>? {
        guard width > 0, abs(drag.translation.width) >= 4 else { return nil }
        if let band = comparisonRepeatBand(for: preview.comparisonRepeatRange, width: width),
           let adjustment = band.adjustment(at: drag.startLocation.x) {
            let offset = drag.translation.width / width * waveformViewport.visibleProgressSpan * waveformDuration
            return preview.adjustedComparisonRepeatRange(adjustment, by: offset)
        }
        let limit = preview.comparisonRepeatMaximumTime
        let start = min(waveformViewport.globalProgress(forLocalProgress: drag.startLocation.x / width)
                        * waveformDuration, limit)
        let end = min(waveformViewport.globalProgress(forLocalProgress: drag.location.x / width)
                      * waveformDuration, limit)
        return start == end ? nil : min(start, end) ..< max(start, end)
    }

    private struct ComparisonRepeatBand {
        let start: CGFloat
        let end: CGFloat
        let width: CGFloat

        var visibleStart: CGFloat { min(max(start, 0), width) }
        var visibleWidth: CGFloat { min(max(end, 0), width) - visibleStart }

        var startGrip: CGFloat? { (0...width).contains(start) ? gripSpan.lowerBound : nil }
        var endGrip: CGFloat? { (0...width).contains(end) ? gripSpan.upperBound : nil }

        // Give short ranges a central drag target between their two grips.
        // The colored band remains at the actual start and end times.
        private var gripSpan: ClosedRange<CGFloat> {
            let minimumWidth = min(8, width)
            guard (0...width).contains(start), (0...width).contains(end), end - start < minimumWidth else {
                return start...end
            }
            let left = min(max((start + end - minimumWidth) / 2, 0), width - minimumWidth)
            return left...(left + minimumWidth)
        }

        func adjustment(at x: CGFloat) -> AudioPreviewController.ComparisonRepeatAdjustment? {
            let span = gripSpan
            let inset = min(4, (span.upperBound - span.lowerBound) / 4)
            if let startGrip, (startGrip - 5...startGrip + inset).contains(x) { return .start }
            if let endGrip, (endGrip - inset...endGrip + 5).contains(x) { return .end }
            return span.contains(x) ? .move : nil
        }
    }

    private var waveformZoomControls: some View {
        waveformColumns {
            Color.clear
        } waveform: {
            GeometryReader { proxy in
                let maximumZoomScale = WaveformViewport.maximumZoomScale(
                    sampleCount: waveformSampleCount,
                    displayWidth: Double(proxy.size.width)
                )

                WaveformZoomControls(
                    viewport: $waveformViewport,
                    centerProgress: waveformZoomCenterProgress,
                    maximumZoomScale: maximumZoomScale
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .onAppear {
                    maximumWaveformZoomScale = maximumZoomScale
                }
                .onChange(of: maximumZoomScale) { _, newValue in
                    maximumWaveformZoomScale = newValue
                }
            }
            .frame(height: 40)
        } trailing: {
            Color.clear
        }
        .frame(height: 40)
        .padding(.top, 4)
    }

    private func waveformColumns(
        @ViewBuilder leading: () -> some View,
        @ViewBuilder waveform: () -> some View,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            leading()
                .frame(width: waveformLabelColumnWidth, alignment: .leading)
            waveform()
                .frame(minWidth: 240, maxWidth: .infinity)
            trailing()
                .frame(width: waveformTrailingColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }

    private var waveformDuration: TimeInterval {
        tracks.map(\.target)
            .compactMap { preview.cardState(for: $0).snapshot?.duration }
            .max() ?? 0
    }

    private var waveformPresentationState: VelouraWaveformPresentationState {
        VelouraWaveformPresentationState(
            viewport: $waveformViewport,
            maximumZoomScale: maximumWaveformZoomScale,
            centerProgress: waveformZoomCenterProgress
        )
    }

    private func prepareForPlayback() {
        playbackInterlocks.forEach { $0.stopPlayback() }
    }

    private var waveformSampleCount: Int {
        tracks.map(\.target)
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

        if !preview.isPlayingComparisonRepeat, let playingWaveformProgress {
            waveformViewport.followPlayback(playingWaveformProgress)
        }
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
        track(for: target)?.fileURL
    }

    private var comparisonSummaryText: String {
        switch comparisonPresentation {
        case .selectable:
            comparisonPairSummary(preview.comparisonPair)
        case .fixed(let summary):
            summary
        }
    }

    private var activeSideTitle: String {
        sideTitle(for: preview.activeComparisonSide)
    }

    private func sideTitle(for side: AudioComparisonSide) -> String {
        switch side {
        case .a: activeSideATitle
        case .b: activeSideBTitle
        }
    }

    private func track(for target: AudioPreviewTarget) -> AudioWaveformTrackPresentation? {
        tracks.first(where: { $0.target == target })
    }

    private func waveformHeight(for target: AudioPreviewTarget) -> Binding<CGFloat> {
        switch target {
        case .input: $inputWaveformHeight
        case .corrected: $correctedWaveformHeight
        case .mastered: $masteredWaveformHeight
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

private struct WaveformTransportButton: View {
    enum Layout {
        case text
        case icon
    }

    let title: String
    var systemImage: String?
    var layout: Layout = .text
    var iconFont: Font = .headline
    var isSelected = false
    var isDisabled = false
    var showsSelectedAccessibilityTrait = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var isHovering = false
    @Namespace private var glassNamespace

    var body: some View {
        Button(action: action) {
            label
                .font(labelFont)
                .foregroundStyle(
                    isSelected
                        ? LiquidGlassSegmentedPickerStyle.selectedText
                        : Color.primary
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .contentShape(Capsule())
        }
        .buttonStyle(
            WaveformTransportButtonStyle(
                tint: LiquidGlassSegmentedPickerStyle.selectedTint,
                isSelected: isSelected,
                isHovering: isHovering,
                isDisabled: isDisabled,
                reduceMotion: reduceMotion,
                namespace: glassNamespace
            )
        )
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.38 : 1)
        .onHover(perform: updateHover)
        .help(AppLanguageSettings.string(title))
        .accessibilityLabel(AppLanguageSettings.string(title))
        .environment(\.locale, locale)
        .accessibilityAddTraits(
            showsSelectedAccessibilityTrait && isSelected ? .isSelected : []
        )
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(AppLanguageSettings.string(title), systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            AppLocalizedText(title)
        }
    }

    private var labelFont: Font {
        switch layout {
        case .text:
            .callout.weight(isSelected ? .semibold : .regular)
        case .icon:
            iconFont
        }
    }

    private var horizontalPadding: CGFloat {
        layout == .icon ? 10 : 12
    }

    private var verticalPadding: CGFloat {
        layout == .icon ? 10 : 7
    }

    @MainActor
    private func updateHover(_ hovering: Bool) {
        let nextValue = !isDisabled && hovering
        guard isHovering != nextValue else { return }

        LiquidGlassMotion.perform(
            reduceMotion: reduceMotion,
            animation: LiquidGlassMotion.selection
        ) {
            isHovering = nextValue
        }
    }
}

private struct WaveformTransportButtonStyle: ButtonStyle {
    let tint: Color
    let isSelected: Bool
    let isHovering: Bool
    let isDisabled: Bool
    let reduceMotion: Bool
    let namespace: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && !isDisabled
        let surfaceOpacity = if isPressed {
            0.42
        } else if isSelected && isHovering {
            0.36
        } else if isSelected {
            0.30
        } else if isHovering {
            0.16
        } else {
            0.0
        }

        configuration.label
            .modifier(
                WaveformTransportButtonSurface(
                    tint: tint.opacity(surfaceOpacity),
                    isVisible: surfaceOpacity > 0,
                    reduceMotion: reduceMotion,
                    namespace: namespace
                )
            )
            .scaleEffect(isPressed && !reduceMotion ? 0.94 : 1)
            .brightness(isPressed ? -0.04 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: isPressed
            )
    }
}

private struct WaveformTransportButtonSurface: ViewModifier {
    let tint: Color
    let isVisible: Bool
    let reduceMotion: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if isVisible {
            content
                .velouraAdaptiveGlass(
                    in: .capsule,
                    interactive: true,
                    tint: tint
                )
                .glassEffectID("waveform-transport-button", in: namespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else {
            content
        }
    }
}

struct SeekableWaveformView: View {
    let samples: [WaveformEnvelopeSample]
    let progress: Double
    let hoverProgress: Double?
    let duration: TimeInterval
    let viewport: WaveformViewport
    let tint: Color
    let isSelected: Bool
    let isAvailable: Bool
    let showsHoverTime: Bool
    let onSeek: (Double) -> Void
    let onActivateKeyboardPan: () -> Void
    let onPanChanged: (Double) -> Void
    let onPanEnded: (Double) -> Void
    let onHover: (Double?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let localProgress = viewport.localProgress(
                forGlobalProgress: clampedProgress
            )

            ZStack(alignment: .leading) {
                if isAvailable, !samples.isEmpty {
                    waveform(playedWidth: proxy.size.width * localProgress)

                    if let hoverProgress, viewport.contains(hoverProgress) {
                        let localHoverProgress = viewport.localProgress(
                            forGlobalProgress: hoverProgress
                        )
                        let hoverX = min(
                            proxy.size.width * localHoverProgress,
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

                    if viewport.contains(clampedProgress) {
                        Rectangle()
                            .fill(tint)
                            .frame(width: 2)
                            .offset(
                                x: min(
                                    proxy.size.width * localProgress,
                                    max(proxy.size.width - 2, 0)
                                )
                            )
                    }
                } else {
                    Text("音声なし")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    guard isAvailable, proxy.size.width > 0 else { return }
                    let localProgress = min(
                        max(location.x / proxy.size.width, 0),
                        1
                    )
                    onHover(
                        viewport.globalProgress(
                            forLocalProgress: localProgress
                        )
                    )
                case .ended:
                    onHover(nil)
                }
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        onActivateKeyboardPan()
                        guard let progress = seekProgress(
                            at: value.location.x,
                            width: proxy.size.width
                        ) else { return }
                        onSeek(progress)
                    }
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard isAvailable, proxy.size.width > 0 else { return }
                        onActivateKeyboardPan()
                        onPanChanged(
                            Double(value.translation.width / proxy.size.width)
                        )
                    }
                    .onEnded { value in
                        guard isAvailable, proxy.size.width > 0 else { return }
                        onPanEnded(
                            Double(value.translation.width / proxy.size.width)
                        )
                    },
                including: isAvailable && viewport.canZoomOut ? .gesture : .none
            )
        }
        .accessibilityLabel("再生位置")
        .accessibilityValue(
            "\(waveformTimeText(duration * min(max(progress, 0), 1))) / \(waveformTimeText(duration))"
        )
        .accessibilityAdjustableAction { direction in
            let increment = viewport.visibleProgressSpan * 0.02
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

    private func seekProgress(at locationX: CGFloat, width: CGFloat) -> Double? {
        guard isAvailable, width > 0 else { return nil }
        let localProgress = min(max(locationX / width, 0), 1)
        return viewport.globalProgress(forLocalProgress: localProgress)
    }

    private func waveform(playedWidth: CGFloat) -> some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let waveformTint = isSelected
                ? tint
                : Color(nsColor: .secondaryLabelColor)
            let renderedSamples = renderedSamples(for: size.width)
            let peakPath = verticalEnvelopePath(
                samples: renderedSamples,
                in: size
            ) { sample in
                (minimum: sample.minimum, maximum: sample.maximum)
            }
            let rmsPath = verticalEnvelopePath(
                samples: renderedSamples,
                in: size
            ) { sample in
                (
                    minimum: max(-sample.rms, min(sample.minimum, 0)),
                    maximum: min(sample.rms, max(sample.maximum, 0))
                )
            }
            let columnWidth = max(
                size.width / CGFloat(max(renderedSamples.count, 1)),
                1
            )

            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: size.height / 2))
            centerLine.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                centerLine,
                with: .color(.secondary.opacity(0.18)),
                lineWidth: 1
            )

            context.stroke(
                peakPath,
                with: .color(waveformTint.opacity(0.20)),
                lineWidth: columnWidth
            )
            context.stroke(
                rmsPath,
                with: .color(waveformTint.opacity(isSelected ? 0.48 : 0.36)),
                lineWidth: columnWidth
            )

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
            playedContext.stroke(
                peakPath,
                with: .color(waveformTint.opacity(0.62)),
                lineWidth: columnWidth
            )
            playedContext.stroke(
                rmsPath,
                with: .color(waveformTint.opacity(isSelected ? 0.95 : 0.78)),
                lineWidth: columnWidth
            )
        }
    }

    private func verticalEnvelopePath(
        samples: [WaveformEnvelopeSample],
        in size: CGSize,
        range: (WaveformEnvelopeSample) -> (minimum: Float, maximum: Float)
    ) -> Path {
        var path = Path()
        let columnWidth = size.width / CGFloat(max(samples.count, 1))
        let centerY = size.height / 2

        for (index, sample) in samples.enumerated() {
            let sampleRange = range(sample)
            let minimum = min(max(CGFloat(sampleRange.minimum), -1), 1)
            let maximum = min(max(CGFloat(sampleRange.maximum), -1), 1)
            let x = (CGFloat(index) + 0.5) * columnWidth
            path.move(
                to: CGPoint(
                    x: x,
                    y: centerY - maximum * size.height * 0.42
                )
            )
            path.addLine(
                to: CGPoint(
                    x: x,
                    y: centerY - minimum * size.height * 0.42
                )
            )
        }

        return path
    }

    private func renderedSamples(for width: CGFloat) -> [WaveformEnvelopeSample] {
        let visibleSamples = visibleSamples()
        let targetCount = min(
            max(Int(width.rounded(.up)), 1),
            visibleSamples.count
        )
        guard targetCount < visibleSamples.count else { return visibleSamples }

        let samplesPerGroup = Double(visibleSamples.count) / Double(targetCount)
        return (0..<targetCount).map { groupIndex in
            let startIndex = Int(floor(Double(groupIndex) * samplesPerGroup))
            let endIndex = min(
                max(Int(ceil(Double(groupIndex + 1) * samplesPerGroup)), startIndex + 1),
                visibleSamples.count
            )
            let group = visibleSamples[startIndex..<endIndex]
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

    private func visibleSamples() -> [WaveformEnvelopeSample] {
        guard samples.count > 1, viewport.zoomScale > 1 else { return samples }

        let lastIndex = samples.count - 1
        let startIndex = min(
            max(Int(floor(viewport.startProgress * Double(lastIndex))), 0),
            lastIndex
        )
        let endIndex = min(
            max(Int(ceil(viewport.endProgress * Double(lastIndex))), startIndex),
            lastIndex
        )
        return Array(samples[startIndex...endIndex])
    }
}
