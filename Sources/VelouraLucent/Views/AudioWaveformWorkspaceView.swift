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
    @State private var hoveredWaveformProgress: Double?
    @State private var hoveredWaveformTarget: AudioPreviewTarget?
    @State private var waveformViewport = WaveformViewport()
    @State private var waveformPanStartProgress: Double?
    @State private var isWaveformPanning = false
    @State private var inputWaveformHeight = WaveformTrackResizeHandle.defaultHeight
    @State private var correctedWaveformHeight = WaveformTrackResizeHandle.defaultHeight
    @State private var masteredWaveformHeight = WaveformTrackResizeHandle.defaultHeight
    @State private var maximumWaveformZoomScale = 1.0
    @FocusState private var isWaveformKeyboardFocused: Bool

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
        playbackInterlocks: [AudioPreviewController] = []
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
        self.waveformLabelColumnWidth = 112
        self.topAccessory = nil
        self.resetToken = inputFileURL?.path ?? ""
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
        playbackInterlocks: [AudioPreviewController] = []
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
                    ForEach(tracks.indices, id: \.self) { index in
                        waveformRow(
                            track: tracks[index],
                            height: waveformHeight(for: tracks[index].target)
                        )
                        Divider()
                    }
                    waveformTimeRuler
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
                let playingWaveformProgress
            else {
                return
            }
            waveformViewport.followPlayback(playingWaveformProgress)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(workspaceTitle)
                .font(.headline)
            Text(playbackStatusText ?? preview.playbackLabel)
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
        Text(comparisonSummaryText)
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
                WaveformTransportButton(
                    title: sideAButtonTitle,
                    isSelected: preview.activeComparisonSide == .a
                        && comparisonFileURL(for: .a) != nil,
                    isDisabled: comparisonFileURL(for: .a) == nil,
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
                    isDisabled: activeComparisonFileURL == nil
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
                    isDisabled: comparisonFileURL(for: .b) == nil,
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
            .accessibilityLabel(volumeAccessibilityLabel)
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
        .help(loudnessHelp)
    }

    private var activeComparisonLabel: some View {
        let displayTint = activeComparisonTint.opacity(0.65)

        return HStack(spacing: 6) {
            Circle()
                .fill(displayTint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("現在 \(activeSideTitle)")
                .font(.callout.weight(.bold))
                .foregroundStyle(displayTint)
        }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("現在再生中")
            .accessibilityValue(activeSideTitle)
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

        return HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(track.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let comparisonSide {
                    Text(sideTitle(for: comparisonSide))
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
                title: track.title,
                height: height
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(track.accessibilityLabel)
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
                .onAppear {
                    maximumWaveformZoomScale = maximumZoomScale
                }
                .onChange(of: maximumZoomScale) { _, newValue in
                    maximumWaveformZoomScale = newValue
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

        if let playingWaveformProgress {
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
    var isSelected = false
    var isDisabled = false
    var showsSelectedAccessibilityTrait = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(
            showsSelectedAccessibilityTrait && isSelected ? .isSelected : []
        )
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            Text(title)
        }
    }

    private var labelFont: Font {
        switch layout {
        case .text:
            .callout.weight(isSelected ? .semibold : .regular)
        case .icon:
            .headline
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
