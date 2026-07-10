import AppKit
import SwiftUI

struct ContentView: View {
    static let inspectorVisibleMinimumWindowWidth: CGFloat = 1_380
    static let inspectorHiddenMinimumWindowWidth: CGFloat = 960
    static let minimumWindowHeight: CGFloat = 720

    @State private var job = ProcessingJob(notificationReporter: NotificationService.shared)
    @State private var preview = AudioPreviewController()
    @State private var inputSelectionID = UUID()
    @State private var displayAnalysisTasks: [DisplayAnalysisTarget: Task<Void, Never>] = [:]
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorPresented = true
    @State private var isWindowFullScreen = false
    @State private var inputAudioDropVisualState: InputAudioDropVisualState = .inactive
    @State private var windowBackgroundMaterialAmount = AppAppearanceSettings.storedWindowBackgroundMaterialAmount()
    @State private var highlightedToolbarTarget: LiquidGlassToolbarTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var toolbarGlassNamespace
    @Namespace private var inspectorGlassNamespace

    var body: some View {
        mainContent
            .frame(minWidth: minimumWindowWidth, minHeight: Self.minimumWindowHeight)
            .velouraWindowBackground(
                amount: windowBackgroundMaterialAmount,
                isFullScreen: isWindowFullScreen
            )
            .background(
                WindowChromeConfigurator(
                    minSize: NSSize(width: minimumWindowWidth, height: Self.minimumWindowHeight),
                    isFullScreen: $isWindowFullScreen
                )
            )
            .background(TitlebarSidebarToggleConfigurator(visibility: $sidebarVisibility))
            .background(TitlebarInspectorToggleConfigurator(isPresented: $isInspectorPresented))
            .background(WindowScrollbarAppearanceConfigurator())
            .onChange(of: job.selectedMasteringProfile) { _, newValue in
                job.applyMasteringProfile(newValue)
            }
            .onDisappear {
                cancelDisplayAnalysisTasks()
                PreviewFileStore.removeAllPreviewFiles()
            }
    }

    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            VelouraSidebarView(job: job)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            HStack(spacing: 0) {
                ZStack {
                    VelouraMainWorkspaceView(
                        job: job,
                        preview: preview
                    )
                    .frame(minWidth: 620, maxWidth: .infinity)

                    InputAudioDropReceiver(
                        isEnabled: canAcceptInputAudioDrop,
                        visualState: $inputAudioDropVisualState,
                        onDrop: acceptDroppedInputAudio
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)

                    switch inputAudioDropVisualState {
                    case .inactive:
                        EmptyView()
                    case .accepted:
                        InputAudioDropOverlay(kind: .accepted)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    case .rejected:
                        InputAudioDropOverlay(kind: .rejected)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)

                if isInspectorPresented {
                    Divider()
                    VelouraInspectorView(
                        job: job,
                        completionReport: completionReport,
                        windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                        isWindowFullScreen: isWindowFullScreen
                    )
                    .frame(width: 440)
                    .glassEffectID("right-inspector-panel", in: inspectorGlassNamespace)
                    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                    .transition(inspectorTransition)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarActionGroup
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .principal)

            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(AudioExportFormat.allCases) { format in
                        Menu(format.menuTitle) {
                            Button("補正後を書き出し") {
                                exportCorrectedAudio(as: format)
                            }
                            .disabled(!job.hasExistingOutput || job.isProcessing)

                            Button("最終版を書き出し") {
                                exportMasteredAudio(as: format)
                            }
                            .disabled(!job.hasExistingMasteredOutput || job.isMastering)
                        }
                    }
                } label: {
                    toolbarExportLabel("書き出し", systemImage: "square.and.arrow.down")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .padding(4)
                .glassEffect(.clear.interactive(), in: .capsule)
                .onHover { updateToolbarHighlight(.export, isHovering: $0) }
                .accessibilityLabel("書き出し")
                .help("補正後または最終版を書き出します")
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var toolbarActionGroup: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: chooseInputAudio) {
                    toolbarActionLabel("音声を選ぶ", systemImage: "waveform.badge.plus", target: .chooseInput)
                }
                .buttonStyle(.plain)
                .onHover { updateToolbarHighlight(.chooseInput, isHovering: $0) }
                .help("入力音声を選びます")
                .disabled(job.isProcessing || job.isMastering)

                Button(action: startCorrectionProcessing) {
                    toolbarActionLabel(
                        job.isProcessing ? "補正中..." : "補正を実行",
                        systemImage: "wand.and.sparkles",
                        target: .runCorrection
                    )
                }
                .buttonStyle(.plain)
                .onHover { updateToolbarHighlight(.runCorrection, isHovering: $0) }
                .help("入力音声に補正処理をかけます")
                .disabled(job.inputFile == nil || job.isProcessing || job.isMastering)

                Button(action: startMasteringProcessing) {
                    toolbarActionLabel(
                        job.isMastering ? "マスタリング中..." : "マスタリングを実行",
                        systemImage: "slider.horizontal.3",
                        target: .runMastering
                    )
                }
                .buttonStyle(.plain)
                .onHover { updateToolbarHighlight(.runMastering, isHovering: $0) }
                .help("補正後音声を最終版へ仕上げます")
                .disabled(!canStartMastering)
            }
            .padding(4)
            .glassEffect(.clear.interactive(), in: .capsule)
        }
        .accessibilityElement(children: .contain)
    }

    private var inspectorTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .trailing).combined(with: .opacity)
    }

    private func toolbarActionLabel(
        _ title: String,
        systemImage: String,
        target: LiquidGlassToolbarTarget
    ) -> some View {
        toolbarLabel(title, systemImage: systemImage)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassCapsuleMorphSurface(
                isActive: highlightedToolbarTarget == target,
                effectID: "toolbar-action-highlight",
                namespace: toolbarGlassNamespace,
                reduceMotion: reduceMotion
            )
    }

    private func toolbarExportLabel(_ title: String, systemImage: String) -> some View {
        toolbarLabel(title, systemImage: systemImage)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassCapsuleMorphSurface(
                isActive: highlightedToolbarTarget == .export,
                effectID: "toolbar-action-highlight",
                namespace: toolbarGlassNamespace,
                reduceMotion: reduceMotion
            )
    }

    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
        .font(.callout)
        .fixedSize()
    }

    @MainActor
    private func updateToolbarHighlight(_ target: LiquidGlassToolbarTarget, isHovering: Bool) {
        let nextTarget = isHovering ? target : (highlightedToolbarTarget == target ? nil : highlightedToolbarTarget)
        guard nextTarget != highlightedToolbarTarget else { return }
        LiquidGlassMotion.perform(
            reduceMotion: reduceMotion,
            animation: LiquidGlassMotion.selection
        ) {
            highlightedToolbarTarget = nextTarget
        }
    }

    private var completionReport: CompletionReport? {
        CompletionReportService.makeReport(
            input: job.inputMetrics,
            corrected: job.outputMetrics,
            mastered: job.masteredMetrics,
            inputNoise: job.inputNoiseMeasurements,
            correctedNoise: job.outputNoiseMeasurements,
            masteredNoise: job.masteredNoiseMeasurements,
            correctionSettings: job.appliedCorrectionSettings ?? job.editableCorrectionSettings,
            masteringSettings: job.appliedMasteringSettings ?? job.editableMasteringSettings
        )
    }

    private var minimumWindowWidth: CGFloat {
        isInspectorPresented ? Self.inspectorVisibleMinimumWindowWidth : Self.inspectorHiddenMinimumWindowWidth
    }

    private var canStartMastering: Bool {
        job.hasExistingOutput
            && job.canUseCorrectedAnalysisForMastering
            && !job.isMastering
            && !job.isProcessing
    }

    private var canAcceptInputAudioDrop: Bool {
        !job.isProcessing && !job.isMastering
    }

    private func chooseInputAudio() {
        FilePanelService.chooseAudioFile { url in
            guard let url else { return }
            let selectionID = beginInputSelection(for: url)
            analyzeMetrics(for: url, target: .input, selectionID: selectionID)
        }
    }

    private func acceptDroppedInputAudio(_ urls: [URL]) -> Bool {
        guard canAcceptInputAudioDrop else { return false }
        guard case let .accepted(url) = InputAudioDropSupport.validate(urls) else {
            return false
        }

        let selectionID = beginInputSelection(for: url)
        analyzeMetrics(for: url, target: .input, selectionID: selectionID)
        return true
    }

    private func startCorrectionProcessing() {
        guard let inputFile = job.inputFile else { return }
        let selectionID = inputSelectionID
        let appliedSettings = job.editableCorrectionSettings
        let resolvedAnalysisMode = job.selectedAnalysisMode.resolvedMode
        let initialAnalysis = job.inputCorrectionAnalysisMode == resolvedAnalysisMode ? job.inputCorrectionAnalysis : nil
        cancelDisplayAnalysisTasks(for: [.corrected, .mastered])
        job.beginProcessing(appliedSettings: appliedSettings)

        Task {
            do {
                let outputFile = try await AudioProcessingService().process(
                    inputFile: inputFile,
                    denoiseStrength: job.selectedDenoiseStrength,
                    correctionSettings: appliedSettings,
                    analysisMode: job.selectedAnalysisMode,
                    initialAnalysis: initialAnalysis,
                    initialNoiseMeasurements: job.inputNoiseMeasurements
                ) { message in
                    Task { @MainActor in
                        job.appendLog(message)
                    }
                }

                let shouldStartCorrectedAnalysis = await MainActor.run {
                    guard isCurrentInputSelection(selectionID, inputFile: inputFile) else { return false }
                    job.finishSuccess(outputFile, appliedSettings: appliedSettings)
                    preview.preparePreview(for: job.inputFile, target: .input, measureLoudness: false)
                    if let inputMetrics = job.inputMetrics {
                        preview.setIntegratedLoudnessLUFS(inputMetrics.integratedLoudnessLUFS, for: .input)
                    }
                    preview.preparePreview(for: nil, target: .mastered)
                    return true
                }
                guard shouldStartCorrectedAnalysis else { return }
                await MainActor.run {
                    startDisplayAnalysisTask(
                        for: outputFile,
                        target: .corrected,
                        selectionID: selectionID,
                        includePreview: true,
                        includeMasteringAnalysis: true,
                        correctionAnalysisMode: nil,
                        logHandler: { message in
                            Task { @MainActor in
                                job.appendLog(message)
                            }
                        }
                    )
                }
            } catch {
                await MainActor.run {
                    guard isCurrentInputSelection(selectionID, inputFile: inputFile) else { return }
                    job.resetDisplayAnalysisStates(for: .corrected)
                    job.finishFailure(error.localizedDescription)
                }
            }
        }
    }

    private func startMasteringProcessing() {
        guard let correctedFile = job.outputFile else { return }
        guard canStartMastering else { return }
        let selectionID = inputSelectionID
        let appliedSettings = job.editableMasteringSettings
        cancelDisplayAnalysisTasks(for: [.mastered])
        job.beginMastering(appliedSettings: appliedSettings)

        Task {
            do {
                let masteredFile = try await MasteringService().process(
                    inputFile: correctedFile,
                    settings: appliedSettings,
                    initialAnalysis: job.outputMasteringAnalysis,
                    referenceNoiseMeasurements: job.outputNoiseMeasurements,
                    originalReferenceFile: job.inputFile,
                    originalReferenceNoiseMeasurements: job.inputNoiseMeasurements
                ) { message in
                    Task { @MainActor in
                        job.appendMasteringLog(message)
                    }
                }

                let shouldStartMasteredAnalysis = await MainActor.run {
                    guard isCurrentMasteringSelection(selectionID, correctedFile: correctedFile) else { return false }
                    job.finishMasteringSuccess(masteredFile, appliedSettings: appliedSettings)
                    return true
                }
                guard shouldStartMasteredAnalysis else { return }
                await MainActor.run {
                    startDisplayAnalysisTask(
                        for: masteredFile,
                        target: .mastered,
                        selectionID: selectionID,
                        includePreview: true,
                        includeMasteringAnalysis: false,
                        correctionAnalysisMode: nil,
                        logHandler: { message in
                            Task { @MainActor in
                                job.appendMasteringLog(message)
                            }
                        }
                    )
                }
            } catch {
                await MainActor.run {
                    guard isCurrentMasteringSelection(selectionID, correctedFile: correctedFile) else { return }
                    job.resetDisplayAnalysisStates(for: .mastered)
                    job.finishMasteringFailure(error.localizedDescription)
                }
            }
        }
    }

    private func analyzeMetrics(for url: URL, target: DisplayAnalysisTarget, selectionID: UUID) {
        startDisplayAnalysisTask(
            for: url,
            target: target,
            selectionID: selectionID,
            includePreview: target == .input,
            includeMasteringAnalysis: target == .corrected,
            correctionAnalysisMode: target == .input ? job.selectedAnalysisMode.resolvedMode : nil,
            logHandler: displayAnalysisLogHandler(for: target)
        )
    }

    private func startDisplayAnalysisTask(
        for url: URL,
        target: DisplayAnalysisTarget,
        selectionID: UUID,
        includePreview: Bool,
        includeMasteringAnalysis: Bool,
        correctionAnalysisMode: AudioAnalysisMode?,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) {
        displayAnalysisTasks[target]?.cancel()
        displayAnalysisTasks[target] = Task {
            await runDisplayAnalysis(
                for: url,
                target: target,
                selectionID: selectionID,
                includePreview: includePreview,
                includeMasteringAnalysis: includeMasteringAnalysis,
                correctionAnalysisMode: correctionAnalysisMode,
                logHandler: logHandler
            )
        }
    }

    private func cancelDisplayAnalysisTasks(for targets: [DisplayAnalysisTarget] = DisplayAnalysisTarget.allDisplayTargets) {
        for target in targets {
            displayAnalysisTasks[target]?.cancel()
            displayAnalysisTasks[target] = nil
        }
    }

    private func runDisplayAnalysis(
        for url: URL,
        target: DisplayAnalysisTarget,
        selectionID: UUID,
        includePreview: Bool,
        includeMasteringAnalysis: Bool,
        correctionAnalysisMode: AudioAnalysisMode?,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) async {
        let isCurrentSelection = await MainActor.run {
            isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url)
        }
        guard isCurrentSelection else { return }

        let requiredKinds = requiredDisplayAnalysisKinds(
            includePreview: includePreview,
            includeMasteringAnalysis: includeMasteringAnalysis,
            correctionAnalysisMode: correctionAnalysisMode
        )
        let missingKinds = await MainActor.run {
            requiredKinds.filter {
                !hasCachedAnalysis($0, for: target, fileURL: url, correctionAnalysisMode: correctionAnalysisMode)
            }
        }
        guard !missingKinds.isEmpty else { return }

        await MainActor.run {
            guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
            for kind in missingKinds {
                job.beginDisplayAnalysis(kind, for: target)
            }
        }
        guard await shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }

        let signal: AudioSignal
        do {
            signal = try await DisplayAnalysisSupport.measure("ファイル読み込み", logHandler: logHandler) {
                try await DisplayAnalysisSupport.runWorker {
                    try AudioFileService.loadAudio(from: url)
                }
            }
        } catch {
            await failDisplayAnalysisKinds(missingKinds, for: target, selectionID: selectionID, fileURL: url)
            return
        }

        guard await shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if includePreview && (missingKinds.contains(.preview) || missingKinds.contains(.spectrogram)) {
            do {
                let snapshots = try await DisplayAnalysisSupport.measure("プレビュー/スペクトログラム生成", logHandler: logHandler) {
                    try await DisplayAnalysisSupport.runWorker {
                        AudioFileService.makeDisplaySnapshots(from: signal)
                    }
                }
                await MainActor.run {
                    guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                    preview.setPreviewSnapshot(snapshots.previewSnapshot, for: previewTarget(for: target), sourceURL: url)
                    job.finishDisplayAnalysis(.preview, for: target)
                    finishSpectrogramAnalysis(snapshots.spectrogram, for: target)
                }
            } catch {
                await failDisplayAnalysisKinds([.preview, .spectrogram].filter { missingKinds.contains($0) }, for: target, selectionID: selectionID, fileURL: url)
            }
        } else if missingKinds.contains(.spectrogram) {
            do {
                let spectrogram = try await DisplayAnalysisSupport.measure("スペクトログラム生成", logHandler: logHandler) {
                    try await DisplayAnalysisSupport.runWorker {
                        AudioFileService.makeSpectrogramSnapshot(from: signal)
                    }
                }
                await MainActor.run {
                    guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                    finishSpectrogramAnalysis(spectrogram, for: target)
                }
            } catch {
                await failDisplayAnalysisKinds([.spectrogram], for: target, selectionID: selectionID, fileURL: url)
            }
        }

        guard await shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if missingKinds.contains(.metrics) {
            do {
                let metrics = try await DisplayAnalysisSupport.measure("比較指標", logHandler: logHandler) {
                    try await AudioComparisonService.analyzeConcurrently(signal: signal)
                }
                await MainActor.run {
                    guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                    finishMetricsAnalysis(metrics, for: target)
                    preview.setIntegratedLoudnessLUFS(metrics.integratedLoudnessLUFS, for: previewTarget(for: target))
                }
            } catch {
                await failDisplayAnalysisKinds([.metrics], for: target, selectionID: selectionID, fileURL: url)
            }
        }

        guard await shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if includeMasteringAnalysis, missingKinds.contains(.masteringAnalysis) {
            do {
                let masteringAnalysis = try await DisplayAnalysisSupport.measure("マスタリング解析", logHandler: logHandler) {
                    try await DisplayAnalysisSupport.runWorker {
                        MasteringAnalysisService.analyze(signal: signal)
                    }
                }
                await MainActor.run {
                    guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                    job.finishOutputMasteringAnalysis(masteringAnalysis)
                }
            } catch {
                await failDisplayAnalysisKinds([.masteringAnalysis], for: target, selectionID: selectionID, fileURL: url)
            }
        }

        guard await shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if let correctionAnalysisMode, missingKinds.contains(.correctionAnalysis) {
            do {
                let correctionAnalysis = try await DisplayAnalysisSupport.measure("補正解析", logHandler: logHandler) {
                    try await DisplayAnalysisSupport.runWorker {
                        AudioAnalyzer(mode: correctionAnalysisMode).analyze(signal: signal)
                    }
                }
                await MainActor.run {
                    guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                    job.finishInputCorrectionAnalysis(correctionAnalysis, mode: correctionAnalysisMode)
                }
            } catch {
                await failDisplayAnalysisKinds([.correctionAnalysis], for: target, selectionID: selectionID, fileURL: url)
            }
        }

        guard await shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if missingKinds.contains(.noise) {
            do {
                let noiseMeasurements = try await DisplayAnalysisSupport.measure("ノイズ測定", logHandler: logHandler) {
                    try await DisplayAnalysisSupport.runWorker {
                        try NoiseMeasurementService.analyzeCancellable(signal: signal)
                    }
                }
                await MainActor.run {
                    guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                    finishNoiseAnalysis(noiseMeasurements, for: target)
                }
            } catch {
                await failDisplayAnalysisKinds([.noise], for: target, selectionID: selectionID, fileURL: url)
            }
        }
    }

    private func shouldContinueDisplayAnalysis(
        target: DisplayAnalysisTarget,
        selectionID: UUID,
        fileURL: URL
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        return await MainActor.run {
            isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: fileURL)
        }
    }

    private func displayAnalysisLogHandler(for target: DisplayAnalysisTarget) -> (@Sendable (String) -> Void) {
        switch target {
        case .input, .corrected:
            { message in
                Task { @MainActor in
                    job.appendLog(message)
                }
            }
        case .mastered:
            { message in
                Task { @MainActor in
                    job.appendMasteringLog(message)
                }
            }
        }
    }

    private func preparePreviewCards(loadInputPreview: Bool = true) {
        if loadInputPreview {
            preview.preparePreview(for: job.inputFile, target: .input, measureLoudness: false)
        } else {
            preview.preparePreviewPlaceholder(for: job.inputFile, target: .input)
        }
        if let inputMetrics = job.inputMetrics {
            preview.setIntegratedLoudnessLUFS(inputMetrics.integratedLoudnessLUFS, for: .input)
        }

        preview.preparePreview(for: job.hasExistingOutput ? job.outputFile : nil, target: .corrected, measureLoudness: job.outputMetrics == nil)
        if let outputMetrics = job.outputMetrics {
            preview.setIntegratedLoudnessLUFS(outputMetrics.integratedLoudnessLUFS, for: .corrected)
        }

        preview.preparePreview(for: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil, target: .mastered, measureLoudness: job.masteredMetrics == nil)
        if let masteredMetrics = job.masteredMetrics {
            preview.setIntegratedLoudnessLUFS(masteredMetrics.integratedLoudnessLUFS, for: .mastered)
        }
    }

    private func requiredDisplayAnalysisKinds(
        includePreview: Bool,
        includeMasteringAnalysis: Bool,
        correctionAnalysisMode: AudioAnalysisMode?
    ) -> [DisplayAnalysisKind] {
        var kinds: [DisplayAnalysisKind] = [.spectrogram, .metrics, .noise]
        if includePreview {
            kinds.insert(.preview, at: 0)
        }
        if includeMasteringAnalysis {
            kinds.append(.masteringAnalysis)
        }
        if correctionAnalysisMode != nil {
            kinds.append(.correctionAnalysis)
        }
        return kinds
    }

    private func hasCachedAnalysis(
        _ kind: DisplayAnalysisKind,
        for target: DisplayAnalysisTarget,
        fileURL: URL,
        correctionAnalysisMode: AudioAnalysisMode?
    ) -> Bool {
        guard isCurrentMetricSelection(target: target, selectionID: inputSelectionID, fileURL: fileURL) else {
            return false
        }
        switch (target, kind) {
        case (.input, .metrics):
            return job.inputMetrics != nil
        case (.corrected, .metrics):
            return job.outputMetrics != nil
        case (.mastered, .metrics):
            return job.masteredMetrics != nil
        case (.input, .spectrogram):
            return job.inputSpectrogram != nil
        case (.corrected, .spectrogram):
            return job.outputSpectrogram != nil
        case (.mastered, .spectrogram):
            return job.masteredSpectrogram != nil
        case (.input, .noise):
            return job.inputNoiseMeasurements != nil
        case (.corrected, .noise):
            return job.outputNoiseMeasurements != nil
        case (.mastered, .noise):
            return job.masteredNoiseMeasurements != nil
        case (.input, .correctionAnalysis):
            return job.inputCorrectionAnalysis != nil
                && job.inputCorrectionAnalysisMode == correctionAnalysisMode
        case (.corrected, .masteringAnalysis):
            return job.outputMasteringAnalysis != nil
        case (_, .preview):
            return false
        default:
            return true
        }
    }

    private func finishMetricsAnalysis(_ metrics: AudioMetricSnapshot, for target: DisplayAnalysisTarget) {
        switch target {
        case .input:
            job.finishInputMetricAnalysis(metrics)
        case .corrected:
            job.finishOutputMetricAnalysis(metrics)
        case .mastered:
            job.finishMasteredMetricAnalysis(metrics)
        }
    }

    private func finishSpectrogramAnalysis(_ spectrogram: SpectrogramSnapshot, for target: DisplayAnalysisTarget) {
        switch target {
        case .input:
            job.finishInputSpectrogram(spectrogram)
        case .corrected:
            job.finishOutputSpectrogram(spectrogram)
        case .mastered:
            job.finishMasteredSpectrogram(spectrogram)
        }
    }

    private func finishNoiseAnalysis(_ noiseMeasurements: NoiseMeasurementSnapshot, for target: DisplayAnalysisTarget) {
        switch target {
        case .input:
            job.finishInputNoiseMeasurement(noiseMeasurements)
        case .corrected:
            job.finishOutputNoiseMeasurement(noiseMeasurements)
        case .mastered:
            job.finishMasteredNoiseMeasurement(noiseMeasurements)
        }
    }

    private func failDisplayAnalysisKinds(
        _ kinds: [DisplayAnalysisKind],
        for target: DisplayAnalysisTarget,
        selectionID: UUID,
        fileURL: URL
    ) async {
        await MainActor.run {
            guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: fileURL) else { return }
            for kind in kinds {
                job.failDisplayAnalysis(kind, for: target)
            }
        }
    }

    private func previewTarget(for target: DisplayAnalysisTarget) -> AudioPreviewTarget {
        switch target {
        case .input:
            .input
        case .corrected:
            .corrected
        case .mastered:
            .mastered
        }
    }

    @discardableResult
    private func beginInputSelection(for url: URL) -> UUID {
        let selectionID = UUID()
        cancelDisplayAnalysisTasks()
        inputSelectionID = selectionID
        PreviewFileStore.removeAllPreviewFiles()
        job.prepareForSelection(url)
        preview.stopPlayback()
        preview.setComparisonPair(.inputVsCorrected)
        preparePreviewCards(loadInputPreview: false)
        return selectionID
    }

    private func exportCorrectedAudio(as format: AudioExportFormat) {
        guard let sourceURL = job.outputFile, let inputFile = job.inputFile else { return }
        let suggestedName = exportFileName(baseURL: AudioProcessingService.defaultOutputURL(for: inputFile), format: format)
        FilePanelService.chooseSaveLocation(
            suggestedFileName: suggestedName,
            allowedContentTypes: [format.contentType]
        ) { destinationURL in
            guard let destinationURL else { return }
            do {
                try AudioFileService.exportAudio(from: sourceURL, to: destinationURL, format: format)
                job.finishCorrectedExport(destinationURL)
            } catch {
                job.finishFailure(error.localizedDescription)
            }
        }
    }

    private func exportMasteredAudio(as format: AudioExportFormat) {
        guard let sourceURL = job.masteredOutputFile else { return }
        let baseURL = job.inputFile.map { MasteringService.defaultOutputURL(for: $0) } ?? sourceURL
        let suggestedName = exportFileName(baseURL: baseURL, format: format)
        FilePanelService.chooseSaveLocation(
            suggestedFileName: suggestedName,
            allowedContentTypes: [format.contentType]
        ) { destinationURL in
            guard let destinationURL else { return }
            do {
                try AudioFileService.exportAudio(from: sourceURL, to: destinationURL, format: format)
                job.finishMasteredExport(destinationURL)
            } catch {
                job.finishMasteringFailure(error.localizedDescription)
            }
        }
    }

    private func exportFileName(baseURL: URL, format: AudioExportFormat) -> String {
        baseURL.deletingPathExtension().appendingPathExtension(format.fileExtension).lastPathComponent
    }

    private func isCurrentInputSelection(_ selectionID: UUID, inputFile: URL) -> Bool {
        inputSelectionID == selectionID && job.inputFile == inputFile
    }

    private func isCurrentMasteringSelection(_ selectionID: UUID, correctedFile: URL) -> Bool {
        inputSelectionID == selectionID && job.outputFile == correctedFile
    }

    private func isCurrentMetricSelection(target: DisplayAnalysisTarget, selectionID: UUID, fileURL: URL) -> Bool {
        guard inputSelectionID == selectionID else { return false }

        switch target {
        case .input:
            return job.inputFile == fileURL
        case .corrected:
            return job.outputFile == fileURL
        case .mastered:
            return job.masteredOutputFile == fileURL
        }
    }

}

private extension View {
    @ViewBuilder
    func velouraWindowBackground(amount: Double, isFullScreen: Bool) -> some View {
        if isFullScreen {
            self
        } else {
            let clampedAmount = AppAppearanceSettings.clampedWindowBackgroundMaterialAmount(amount)
            containerBackground(
                .thinMaterial.materialActiveAppearance(.active).opacity(clampedAmount),
                for: .window
            )
        }
    }

}

private struct WindowChromeConfigurator: NSViewRepresentable {
    let minSize: NSSize
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(isFullScreen: $isFullScreen)
        updateWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isFullScreen: $isFullScreen)
        updateWindow(for: nsView, context: context)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.stopObservingWindow()
        }
    }

    private func updateWindow(for view: NSView, context: Context) {
        Task { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.observe(window)
            configure(window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow, coordinator: Coordinator) {
        if window.minSize.width != minSize.width || window.minSize.height != minSize.height {
            window.minSize = minSize
        }
        coordinator.applyChrome(to: window)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }

    final class Coordinator: @unchecked Sendable {
        private weak var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var isFullScreen: Binding<Bool>?
        private var restoresFullSizeContentView = false

        @MainActor
        func update(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
        }

        @MainActor
        func observe(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObservingWindow()
            observedWindow = window
            restoresFullSizeContentView = window.styleMask.contains(.fullSizeContentView)

            let notificationCenter = NotificationCenter.default
            observers = [
                notificationCenter.addObserver(
                    forName: NSWindow.willEnterFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor in
                        guard let self, let window else { return }
                        self.applyChrome(to: window, isFullScreen: true)
                    }
                },
                notificationCenter.addObserver(
                    forName: NSWindow.didEnterFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor in
                        guard let self, let window else { return }
                        self.applyChrome(to: window, isFullScreen: true)
                    }
                },
                notificationCenter.addObserver(
                    forName: NSWindow.didExitFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor in
                        guard let self, let window else { return }
                        self.applyChrome(to: window, isFullScreen: false)
                    }
                },
                notificationCenter.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.stopObservingWindow()
                    }
                }
            ]
        }

        func stopObservingWindow() {
            let notificationCenter = NotificationCenter.default
            observers.forEach(notificationCenter.removeObserver)
            observers.removeAll()
            observedWindow = nil
        }

        @MainActor
        func applyChrome(to window: NSWindow) {
            applyChrome(to: window, isFullScreen: window.styleMask.contains(.fullScreen))
        }

        @MainActor
        private func applyChrome(to window: NSWindow, isFullScreen: Bool) {
            if isFullScreen {
                window.styleMask.remove(.fullSizeContentView)
            } else if restoresFullSizeContentView {
                window.styleMask.insert(.fullSizeContentView)
            }
            window.isOpaque = isFullScreen
            window.backgroundColor = isFullScreen ? .windowBackgroundColor : .clear
            if self.isFullScreen?.wrappedValue != isFullScreen {
                self.isFullScreen?.wrappedValue = isFullScreen
            }
        }

        deinit {
            stopObservingWindow()
        }
    }
}

private struct TitlebarSidebarToggleConfigurator: NSViewRepresentable {
    @Binding var visibility: NavigationSplitViewVisibility

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(visibility: $visibility)
        updateWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(visibility: $visibility)
        updateWindow(for: nsView, context: context)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.stopObservingToolbar()
        }
    }

    private func updateWindow(for view: NSView, context: Context) {
        Task { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.observeToolbar(in: window)
            context.coordinator.installIfNeeded(in: window)
            context.coordinator.removeDefaultSidebarToggle(from: window)
            await Task.yield()
            context.coordinator.removeDefaultSidebarToggle(from: window)
        }
    }

    @MainActor
    final class Coordinator {
        private static let accessoryIdentifier = NSUserInterfaceItemIdentifier("VelouraLucentSidebarToggleAccessory")
        // SwiftUI NavigationSplitView uses this runtime toolbar item for its default sidebar toggle.
        private static let swiftUISidebarToggleIdentifier = NSToolbarItem.Identifier(
            "com.apple.SwiftUI.navigationSplitView.toggleSidebar"
        )

        private weak var observedToolbar: NSToolbar?
        private var toolbarWillAddObserver: NSObjectProtocol?
        private var accessoryController: NSTitlebarAccessoryViewController?
        private var hostingView: NSHostingView<TitlebarSidebarToggleButton>?
        private var visibility: Binding<NavigationSplitViewVisibility>?

        func update(visibility: Binding<NavigationSplitViewVisibility>) {
            self.visibility = visibility
            hostingView?.rootView = TitlebarSidebarToggleButton(visibility: visibility)
        }

        func observeToolbar(in window: NSWindow) {
            guard let toolbar = window.toolbar, toolbar !== observedToolbar else { return }

            if let toolbarWillAddObserver {
                NotificationCenter.default.removeObserver(toolbarWillAddObserver)
            }

            observedToolbar = toolbar
            toolbarWillAddObserver = NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification,
                object: toolbar,
                queue: .main
            ) { [weak self, weak toolbar] _ in
                Task { @MainActor in
                    await Task.yield()
                    guard let toolbar else { return }
                    self?.removeDefaultSidebarToggle(from: toolbar)
                }
            }
        }

        func installIfNeeded(in window: NSWindow) {
            guard accessoryController == nil, let visibility else { return }

            removeStaleAccessory(from: window)

            let button = TitlebarSidebarToggleButton(visibility: visibility)
            let hostingView = NSHostingView(rootView: button)
            hostingView.frame = NSRect(x: 0, y: 0, width: 36, height: 30)
            hostingView.identifier = Self.accessoryIdentifier

            let controller = NSTitlebarAccessoryViewController()
            controller.view = hostingView
            controller.layoutAttribute = .left

            window.addTitlebarAccessoryViewController(controller)

            self.hostingView = hostingView
            self.accessoryController = controller
        }

        func removeDefaultSidebarToggle(from window: NSWindow) {
            guard let toolbar = window.toolbar else { return }
            removeDefaultSidebarToggle(from: toolbar)
        }

        func removeDefaultSidebarToggle(from toolbar: NSToolbar) {
            let indexes = toolbar.items.enumerated().compactMap { index, item in
                let isSidebarToggle = item.itemIdentifier == .toggleSidebar
                    || item.itemIdentifier == Self.swiftUISidebarToggleIdentifier
                return isSidebarToggle ? index : nil
            }

            for index in indexes.reversed() {
                toolbar.removeItem(at: index)
            }
        }

        func stopObservingToolbar() {
            if let toolbarWillAddObserver {
                NotificationCenter.default.removeObserver(toolbarWillAddObserver)
                self.toolbarWillAddObserver = nil
            }
            observedToolbar = nil
        }

        private func removeStaleAccessory(from window: NSWindow) {
            guard let index = window.titlebarAccessoryViewControllers.firstIndex(where: {
                $0.view.identifier == Self.accessoryIdentifier
            }) else {
                return
            }

            window.removeTitlebarAccessoryViewController(at: index)
        }
    }
}

private struct TitlebarSidebarToggleButton: View {
    @Binding var visibility: NavigationSplitViewVisibility

    var body: some View {
        Button {
            visibility = isSidebarVisible ? .detailOnly : .all
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(isSidebarVisible ? "サイドバーを隠す" : "サイドバーを表示")
        .help("左側のサイドバーを表示または非表示にします")
    }

    private var isSidebarVisible: Bool {
        visibility != .detailOnly
    }
}

private struct TitlebarInspectorToggleConfigurator: NSViewRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(isPresented: $isPresented)
        updateWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isPresented: $isPresented)
        updateWindow(for: nsView, context: context)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.stopObservingWindow()
        }
    }

    private func updateWindow(for view: NSView, context: Context) {
        Task { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.observeWindow(in: window)
            context.coordinator.installIfNeeded(in: window)
        }
    }

    @MainActor
    final class Coordinator {
        private static let accessoryIdentifier = NSUserInterfaceItemIdentifier("VelouraLucentInspectorToggleAccessory")

        private weak var observedWindow: NSWindow?
        private var windowObservers: [NSObjectProtocol] = []
        private var accessoryController: NSTitlebarAccessoryViewController?
        private var hostingView: NSHostingView<TitlebarInspectorToggleButton>?
        private var isPresented: Binding<Bool>?

        func update(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
            hostingView?.rootView = TitlebarInspectorToggleButton(isPresented: isPresented)
        }

        func observeWindow(in window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObservingWindow()
            observedWindow = window

            let notificationCenter = NotificationCenter.default
            windowObservers = [
                notificationCenter.addObserver(
                    forName: NSWindow.didEnterFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor in
                        guard let self, let window else { return }
                        await Task.yield()
                        self.reinstallAccessory(in: window)
                    }
                },
                notificationCenter.addObserver(
                    forName: NSWindow.didExitFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor in
                        guard let self, let window else { return }
                        await Task.yield()
                        self.reinstallAccessory(in: window)
                    }
                },
                notificationCenter.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.stopObservingWindow()
                    }
                }
            ]
        }

        func installIfNeeded(in window: NSWindow) {
            guard accessoryController == nil, let isPresented else { return }

            removeStaleAccessory(from: window)

            let button = TitlebarInspectorToggleButton(isPresented: isPresented)
            let hostingView = NSHostingView(rootView: button)
            hostingView.frame = NSRect(x: 0, y: 0, width: 36, height: 30)
            hostingView.identifier = Self.accessoryIdentifier

            let controller = NSTitlebarAccessoryViewController()
            controller.view = hostingView
            controller.layoutAttribute = .right

            window.addTitlebarAccessoryViewController(controller)

            self.hostingView = hostingView
            self.accessoryController = controller
        }

        func stopObservingWindow() {
            let notificationCenter = NotificationCenter.default
            windowObservers.forEach(notificationCenter.removeObserver)
            windowObservers.removeAll()
            observedWindow = nil
        }

        private func removeStaleAccessory(from window: NSWindow) {
            guard let index = window.titlebarAccessoryViewControllers.firstIndex(where: {
                $0.view.identifier == Self.accessoryIdentifier
            }) else {
                return
            }

            window.removeTitlebarAccessoryViewController(at: index)
        }

        private func reinstallAccessory(in window: NSWindow) {
            if let accessoryController,
               let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessoryController }) {
                window.removeTitlebarAccessoryViewController(at: index)
            } else {
                removeStaleAccessory(from: window)
            }

            accessoryController = nil
            hostingView = nil
            installIfNeeded(in: window)
        }
    }
}

private struct TitlebarInspectorToggleButton: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            LiquidGlassMotion.perform(
                reduceMotion: reduceMotion,
                animation: LiquidGlassMotion.panel
            ) {
                isPresented.toggle()
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(isPresented ? "設定を隠す" : "設定を表示")
        .help("右側の設定パネルを表示または非表示にします")
    }
}

#Preview {
    ContentView()
}
