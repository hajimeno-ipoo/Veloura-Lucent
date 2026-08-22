import AppKit
import SwiftUI

/// Owns the lifetime shared by Standard Mode and Stem Mode.
///
/// Switching modes changes only the visible workflow. It must not tear down an
/// approved model acquisition that is continuing in the background, nor may it
/// silently switch back to Stem Mode after that acquisition completes.
@MainActor
struct VelouraRootView: View {
    @State private var runtime: VelouraAppRuntime
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorPresented = true
    @State private var isWindowFullScreen = false
    @State private var isModelAcquisitionProgressPresented = false
    @State private var isKeyboardShortcutManagerPresented = false
    @SceneStorage("inspectorSettingsSelectedSection")
    private var inspectorSettingsSelectedSectionRawValue =
        InspectorSettingsSection.correction.rawValue
    @SceneStorage("stemModeInspectorSettingsSelectedSection")
    private var stemModeInspectorSettingsSelectedSectionRawValue =
        StemModeInspectorSettingsSection.correction.rawValue
    @SceneStorage("inspectorAnalysisSelectedAudio")
    private var inspectorAnalysisSelectedAudioRawValue = InspectorAudioSelection.input.rawValue
    @SceneStorage("stemModeInspectorAnalysisSelectedAudio")
    private var stemModeInspectorAnalysisSelectedAudioRawValue =
        InspectorAudioSelection.input.rawValue
    @State private var isStandardCompletionReportPresented = false
    @State private var isStemCompletionReportPresented = false
    @State private var windowBackgroundMaterialAmount =
        AppAppearanceSettings.storedWindowBackgroundMaterialAmount()
    @State private var isWindowBackgroundBlurEnabled =
        AppAppearanceSettings.storedWindowBackgroundBlurEnabled()
    @State private var windowBackgroundBlurLevel =
        AppAppearanceSettings.storedWindowBackgroundBlurLevel()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(runtime: VelouraAppRuntime = .shared) {
        _runtime = State(initialValue: runtime)
    }

    var body: some View {
        let appearanceState = AppAppearanceSettings.windowAppearanceState(
            materialAmount: windowBackgroundMaterialAmount,
            isBlurEnabled: isWindowBackgroundBlurEnabled,
            blurLevel: windowBackgroundBlurLevel,
            isFullScreen: isWindowFullScreen,
            reduceTransparency: reduceTransparency
        )

        workspaceShell
        .environment(\.velouraIsFullScreen, isWindowFullScreen)
        .frame(
            minWidth: minimumWindowWidth,
            minHeight: WorkspaceLayoutMetrics.minimumWindowHeight
        )
        .velouraWindowBackground(state: appearanceState)
        .background(
            WindowChromeConfigurator(
                minSize: NSSize(
                    width: minimumWindowWidth,
                    height: WorkspaceLayoutMetrics.minimumWindowHeight
                ),
                appearanceState: appearanceState,
                isFullScreen: $isWindowFullScreen
            )
        )
        .focusedSceneValue(
            \.velouraWorkspaceChromeActions,
            workspaceChromeActions
        )
        .focusedSceneValue(
            \.velouraCommandActions,
            commandActions
        )
        .focusedSceneValue(
            \.velouraInspectorSettingsPresentationState,
            inspectorSettingsPresentationState
        )
        .focusedSceneValue(
            \.velouraInspectorAnalysisPresentationState,
            inspectorAnalysisPresentationState
        )
        .focusedSceneValue(
            \.velouraPlaybackPresentationState,
            playbackPresentationState
        )
        .focusedSceneValue(
            \.velouraStemPlaybackPresentationState,
            stemPlaybackPresentationState
        )
        .focusedSceneValue(
            \.velouraStemSelectionPresentationState,
            stemSelectionPresentationState
        )
        .focusedSceneValue(
            \.velouraKeyboardShortcutManagerPresentation,
            $isKeyboardShortcutManagerPresented
        )
        .focusedSceneValue(
            \.velouraCommandsSuspended,
            isKeyboardShortcutManagerPresented
        )
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                WorkspaceToolbarView(
                    commandActions: commandActions,
                    processingMode: processingModeBinding,
                    isModeSwitchDisabled: runtime.isModeSwitchDisabled
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .background(
            TitlebarSidebarToggleConfigurator(
                visibility: $sidebarVisibility,
                isAvailable: true
            )
        )
        .background(
            TitlebarInspectorToggleConfigurator(
                isPresented: $isInspectorPresented,
                isAvailable: true
            )
        )
        .onChange(of: runtime.stemModelManager.inspectionState, initial: true) { _, _ in
            runtime.stemWorkflowController.synchronizeModelReadiness()
        }
        .onChange(of: runtime.stemModelManager.isModelOperationInProgress, initial: true) { _, _ in
            runtime.stemWorkflowController.synchronizeModelReadiness()
        }
        .onChange(
            of: runtime.stemModelManager.operationState,
            initial: true
        ) { _, newState in
            synchronizeModelAcquisitionProgress(with: newState)
        }
        .overlay {
            if isKeyboardShortcutManagerPresented {
                ZStack {
                    Color.black.opacity(0.20)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())

                    KeyboardShortcutManagementView(
                        settings: .shared,
                        processedAudioTitle: commandActions.processedAudioTitle,
                        onDismiss: { isKeyboardShortcutManagerPresented = false }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(2)
            } else if isModelAcquisitionProgressPresented {
                ZStack {
                    Color.black.opacity(0.14)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())

                    StemModelAcquisitionProgressSheet(
                        modelManager: runtime.stemModelManager
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private var workspaceShell: some View {
        WorkspaceShellView(
            sidebarVisibility: $sidebarVisibility,
            isInspectorPresented: isInspectorPresented
        ) {
            switch runtime.processingMode {
            case .standard:
                VelouraSidebarView(job: runtime.standardActions.job)
            case .stem:
                StemModeSidebarView(model: runtime.stemWorkspaceModel)
            }
        } center: {
            switch runtime.processingMode {
            case .standard:
                ContentView(
                    processingActions: runtime.standardActions,
                    shutsDownOnDisappear: false
                )
            case .stem:
                StemModeWorkspaceView(model: runtime.stemWorkspaceModel)
            }
        } inspector: {
            switch runtime.processingMode {
            case .standard:
                VelouraInspectorView(
                    job: runtime.standardActions.job,
                    completionReport: standardCompletionReport,
                    windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                    isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled,
                    windowBackgroundBlurLevel: $windowBackgroundBlurLevel,
                    selectedSettingsSectionRawValue: $inspectorSettingsSelectedSectionRawValue,
                    selectedAnalysisAudio: standardAnalysisSelectionBinding,
                    isCompletionReportPresented: $isStandardCompletionReportPresented,
                    isWindowFullScreen: isWindowFullScreen,
                    openKeyboardShortcutManager: openKeyboardShortcutManager
                )
            case .stem:
                StemModeInspectorView(
                    model: runtime.stemWorkspaceModel,
                    modelManager: runtime.stemModelManager,
                    windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                    isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled,
                    windowBackgroundBlurLevel: $windowBackgroundBlurLevel,
                    selectedSettingsSectionRawValue: $stemModeInspectorSettingsSelectedSectionRawValue,
                    selectedAnalysisAudio: stemAnalysisSelectionBinding,
                    isCompletionReportPresented: $isStemCompletionReportPresented,
                    isWindowFullScreen: isWindowFullScreen,
                    openKeyboardShortcutManager: openKeyboardShortcutManager
                )
            }
        }
    }

    private var processingModeBinding: Binding<ProcessingMode> {
        Binding(
            get: { runtime.processingMode },
            set: { requestedMode in
                _ = runtime.selectMode(requestedMode)
            }
        )
    }

    private var minimumWindowWidth: CGFloat {
        return isInspectorPresented
            ? WorkspaceLayoutMetrics.inspectorVisibleMinimumWindowWidth
            : WorkspaceLayoutMetrics.inspectorHiddenMinimumWindowWidth
    }

    private var standardCompletionReport: CompletionReport? {
        let job = runtime.standardActions.job
        return CompletionReportService.makeReport(
            input: job.inputMetrics,
            corrected: job.outputMetrics,
            mastered: job.masteredMetrics,
            inputNoise: job.inputNoiseMeasurements,
            correctedNoise: job.outputNoiseMeasurements,
            masteredNoise: job.masteredNoiseMeasurements,
            correctionSettings: job.appliedCorrectionSettings
                ?? job.editableCorrectionSettings,
            masteringSettings: job.appliedMasteringSettings
                ?? job.editableMasteringSettings,
            mode: .standard,
            trackTitle: job.inputFile?.deletingPathExtension().lastPathComponent,
            inputFileInfo: job.inputFileInfo,
            processedFileInfo: job.outputFileInfo,
            masteredFileInfo: job.masteredFileInfo
        )
    }

    private var workspaceChromeActions: VelouraWorkspaceChromeActions {
        VelouraWorkspaceChromeActions(
            isSidebarPresented: isSidebarPresented,
            isInspectorPresented: isInspectorPresented,
            toggleSidebar: toggleSidebar,
            toggleInspector: { isInspectorPresented.toggle() }
        )
    }

    private func openKeyboardShortcutManager() {
        isKeyboardShortcutManagerPresented = true
    }

    private var inspectorSettingsPresentationState: VelouraInspectorSettingsPresentationState {
        VelouraInspectorSettingsPresentationState(
            isStemMode: runtime.processingMode == .stem,
            selection: inspectorSettingsSelectionBinding,
            isInspectorPresented: $isInspectorPresented
        )
    }

    private var inspectorAnalysisPresentationState: VelouraInspectorAnalysisPresentationState {
        VelouraInspectorAnalysisPresentationState(
            canShowCompletionReport: currentCompletionReport != nil,
            selection: currentAnalysisSelectionBinding,
            isInspectorPresented: $isInspectorPresented,
            isCompletionReportPresented: currentCompletionReportPresentationBinding
        )
    }

    private var playbackPresentationState: VelouraPlaybackPresentationState {
        switch runtime.processingMode {
        case .standard:
            let preview = runtime.standardActions.preview
            return VelouraPlaybackPresentationState(
                preview: preview,
                playbackInterlocks: [],
                sideACommandTitle: playbackCommandTitle(for: .a, preview: preview),
                sideBCommandTitle: playbackCommandTitle(for: .b, preview: preview)
            )
        case .stem:
            let model = runtime.stemWorkspaceModel
            return VelouraPlaybackPresentationState(
                preview: model.previewController,
                playbackInterlocks: [
                    model.stemPreviewController,
                    model.remixPreviewController,
                ],
                sideACommandTitle: playbackCommandTitle(
                    for: .a,
                    preview: model.previewController
                ),
                sideBCommandTitle: playbackCommandTitle(
                    for: .b,
                    preview: model.previewController
                )
            )
        }
    }

    private func playbackCommandTitle(
        for side: AudioComparisonSide,
        preview: AudioPreviewController
    ) -> String {
        let target = preview.comparisonTarget(for: side)
        let title = switch target {
        case .input: "入力"
        case .corrected: commandActions.processedAudioTitle
        case .mastered: "最終版"
        }
        return "\(title)を再生"
    }

    private var stemPlaybackPresentationState: VelouraStemPlaybackPresentationState? {
        guard runtime.processingMode == .stem else { return nil }
        let model = runtime.stemWorkspaceModel
        return VelouraStemPlaybackPresentationState(
            selectedStemTitle: model.selectedStemPreviewRole.stemModeDisplayTitle,
            stemComparison: VelouraPlaybackPresentationState(
                preview: model.stemPreviewController,
                playbackInterlocks: [
                    model.previewController,
                    model.remixPreviewController,
                ],
                sideACommandTitle: "rawを再生",
                sideBCommandTitle: "補正後を再生",
                comparisonSwitchCommandTitle: "raw／補正後切替",
                allowsComparisonPairSelection: false
            ),
            remixComparison: VelouraPlaybackPresentationState(
                preview: model.remixPreviewController,
                playbackInterlocks: [
                    model.previewController,
                    model.stemPreviewController,
                ],
                sideACommandTitle: "補正後を再生",
                sideBCommandTitle: "再ミックスを再生",
                comparisonSwitchCommandTitle: "補正後／再ミックス切替",
                allowsComparisonPairSelection: false
            )
        )
    }

    private var stemSelectionPresentationState: VelouraStemSelectionPresentationState? {
        guard runtime.processingMode == .stem else { return nil }
        let model = runtime.stemWorkspaceModel
        return VelouraStemSelectionPresentationState(
            availableRoles: model.availableStemRoles,
            previewRole: mainActorBinding(
                get: { model.selectedStemPreviewRole },
                set: { model.selectStemPreviewRole($0) }
            )
        )
    }

    private var currentCompletionReport: CompletionReport? {
        switch runtime.processingMode {
        case .standard:
            standardCompletionReport
        case .stem:
            runtime.stemWorkspaceModel.qualityReports?.completion
        }
    }

    private var standardAnalysisSelectionBinding: Binding<InspectorAudioSelection> {
        Binding(
            get: {
                InspectorAudioSelection(rawValue: inspectorAnalysisSelectedAudioRawValue) ?? .input
            },
            set: { inspectorAnalysisSelectedAudioRawValue = $0.rawValue }
        )
    }

    private var stemAnalysisSelectionBinding: Binding<InspectorAudioSelection> {
        Binding(
            get: {
                InspectorAudioSelection(
                    rawValue: stemModeInspectorAnalysisSelectedAudioRawValue
                ) ?? .input
            },
            set: { stemModeInspectorAnalysisSelectedAudioRawValue = $0.rawValue }
        )
    }

    private var currentAnalysisSelectionBinding: Binding<InspectorAudioSelection> {
        switch runtime.processingMode {
        case .standard:
            standardAnalysisSelectionBinding
        case .stem:
            stemAnalysisSelectionBinding
        }
    }

    private var currentCompletionReportPresentationBinding: Binding<Bool> {
        switch runtime.processingMode {
        case .standard:
            $isStandardCompletionReportPresented
        case .stem:
            $isStemCompletionReportPresented
        }
    }

    private var inspectorSettingsSelectionBinding: Binding<VelouraInspectorSettingsSelection> {
        Binding(
            get: {
                switch runtime.processingMode {
                case .standard:
                    switch InspectorSettingsSection(
                        rawValue: inspectorSettingsSelectedSectionRawValue
                    ) ?? .correction {
                    case .correction: .correction
                    case .mastering: .mastering
                    case .app: .app
                    }
                case .stem:
                    switch StemModeInspectorSettingsSection(
                        rawValue: stemModeInspectorSettingsSelectedSectionRawValue
                    ) ?? .correction {
                    case .correction: .correction
                    case .remix: .remix
                    case .mastering: .mastering
                    case .app: .app
                    }
                }
            },
            set: { selection in
                switch runtime.processingMode {
                case .standard:
                    switch selection {
                    case .correction:
                        inspectorSettingsSelectedSectionRawValue = InspectorSettingsSection.correction.rawValue
                    case .mastering:
                        inspectorSettingsSelectedSectionRawValue = InspectorSettingsSection.mastering.rawValue
                    case .app:
                        inspectorSettingsSelectedSectionRawValue = InspectorSettingsSection.app.rawValue
                    case .remix:
                        break
                    }
                case .stem:
                    stemModeInspectorSettingsSelectedSectionRawValue = switch selection {
                    case .correction: StemModeInspectorSettingsSection.correction.rawValue
                    case .remix: StemModeInspectorSettingsSection.remix.rawValue
                    case .mastering: StemModeInspectorSettingsSection.mastering.rawValue
                    case .app: StemModeInspectorSettingsSection.app.rawValue
                    }
                }
            }
        )
    }

    private var commandActions: VelouraCommandActions {
        switch runtime.processingMode {
        case .standard:
            standardCommandActions
        case .stem:
            stemCommandActions
        }
    }

    private var standardCommandActions: VelouraCommandActions {
        let actions = runtime.standardActions
        let job = actions.job

        return VelouraCommandActions(
            processingMode: .standard,
            processedAudioTitle: "補正後",
            canSwitchProcessingMode: !runtime.isModeSwitchDisabled,
            canChooseInput: !job.isProcessing && !job.isMastering,
            canRunCorrection: job.inputFile != nil
                && !job.isProcessing
                && !job.isMastering,
            canRunMastering: actions.canStartMastering,
            isCorrectionRunning: job.isProcessing,
            isMasteringRunning: job.isMastering,
            isCorrectionCancelling: job.isCancellingProcessing,
            isMasteringCancelling: job.isCancellingMastering,
            canCancelCorrection: job.isProcessing
                && !job.isCancellingProcessing,
            canCancelMastering: job.isMastering
                && !job.isCancellingMastering,
            exportActions: [
                VelouraExportCommandAction(
                    id: "standard-corrected",
                    title: "補正済み",
                    isEnabled: job.hasExistingOutput && !job.isProcessing,
                    perform: actions.exportCorrectedAudio
                ),
                VelouraExportCommandAction(
                    id: "standard-mastered",
                    title: "マスタリング済み",
                    isEnabled: job.hasExistingMasteredOutput && !job.isMastering,
                    perform: actions.exportMasteredAudio
                ),
            ],
            selectProcessingMode: selectProcessingMode,
            chooseInputAudio: actions.chooseInputAudio,
            runCorrection: actions.startCorrectionProcessing,
            runMastering: actions.startMasteringProcessing,
            cancelCorrection: actions.cancelCorrectionProcessing,
            cancelMastering: actions.cancelMasteringProcessing
        )
    }

    private var stemCommandActions: VelouraCommandActions {
        let model = runtime.stemWorkspaceModel
        let isCorrectionRunning = stemCorrectionIsRunning
        let isMasteringRunning = stemMasteringIsRunning

        return VelouraCommandActions(
            processingMode: .stem,
            processedAudioTitle: model.remixedPreviewArtifact == nil
                ? "補正後"
                : "Stem再ミックス",
            stemCount: model.availableStemRoles.count,
            canSwitchProcessingMode: !runtime.isModeSwitchDisabled,
            canChooseInput: model.canChooseInput,
            canRunCorrection: model.canRunCorrection,
            canRunRemix: model.canRunRemix,
            canRunMastering: model.canRunMastering,
            isCorrectionRunning: isCorrectionRunning,
            isRemixRunning: model.session.isRemixProcessing,
            isMasteringRunning: isMasteringRunning,
            isCorrectionCancelling: model.isCorrectionCancelling,
            isRemixCancelling: model.isRemixCancelling,
            isMasteringCancelling: model.isMasteringCancelling,
            canCancelCorrection: isCorrectionRunning
                && model.canCancelProcessing,
            canCancelRemix: model.session.isRemixProcessing
                && model.canCancelProcessing,
            canCancelMastering: isMasteringRunning
                && model.canCancelProcessing,
            exportActions: stemExportCommandActions,
            selectProcessingMode: selectProcessingMode,
            chooseInputAudio: chooseStemInputAudio,
            runCorrection: {
                Task { await model.beginCorrection() }
            },
            runRemix: {
                Task { await model.beginRemix() }
            },
            runMastering: {
                Task { await model.beginMastering() }
            },
            cancelCorrection: {
                Task { await model.cancelCorrection() }
            },
            cancelRemix: {
                Task { await model.cancelRemix() }
            },
            cancelMastering: {
                Task { await model.cancelMastering() }
            }
        )
    }

    private var stemExportCommandActions: [VelouraExportCommandAction] {
        let model = runtime.stemWorkspaceModel
        var hasStartedStemSection = false
        return model.exportableArtifacts.map { artifact in
            let startsSection = artifact.kind.isCorrectedStemArtifact
                && !hasStartedStemSection
            if startsSection {
                hasStartedStemSection = true
            }
            return VelouraExportCommandAction(
                id: artifact.id,
                title: artifact.kind.stemModeExportMenuTitle,
                isEnabled: !model.isExporting(artifact),
                startsSection: startsSection,
                perform: { format in
                    Task {
                        await model.exportArtifact(artifact, as: format)
                    }
                }
            )
        }
    }

    private var stemCorrectionIsRunning: Bool {
        runtime.stemWorkspaceModel.session.isCorrectionProcessing
    }

    private var stemMasteringIsRunning: Bool {
        runtime.stemWorkspaceModel.session.isMasteringProcessing
    }

    private func selectProcessingMode(_ mode: ProcessingMode) {
        _ = runtime.selectMode(mode)
    }

    private var isSidebarPresented: Bool {
        sidebarVisibility != .detailOnly
    }

    private func toggleSidebar() {
        sidebarVisibility = isSidebarPresented ? .detailOnly : .all
    }

    private func chooseStemInputAudio() {
        guard runtime.processingMode == .stem,
              runtime.stemWorkspaceModel.canChooseInput else {
            return
        }
        let model = runtime.stemWorkspaceModel
        FilePanelService.chooseAudioFile { URL in
            guard let URL else { return }
            Task { await model.inspectInput(URL) }
        }
    }

    private func synchronizeModelAcquisitionProgress(
        with state: StemModelManagerOperationState
    ) {
        switch state {
        case .acquiring, .cancelling, .failed:
            isModelAcquisitionProgressPresented = true
        case .idle, .awaitingConfirmation:
            isModelAcquisitionProgressPresented = false
        }
    }

}
