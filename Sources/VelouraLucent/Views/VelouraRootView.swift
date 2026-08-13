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
            if isModelAcquisitionProgressPresented {
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
                    isWindowFullScreen: isWindowFullScreen
                )
            case .stem:
                StemModeInspectorView(
                    model: runtime.stemWorkspaceModel,
                    modelManager: runtime.stemModelManager,
                    windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                    isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled,
                    windowBackgroundBlurLevel: $windowBackgroundBlurLevel,
                    isWindowFullScreen: isWindowFullScreen
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
        let preview = actions.preview

        return VelouraCommandActions(
            processingMode: .standard,
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
            canTogglePlayback: preview.canToggleComparisonPlayback,
            canStopPlayback: preview.activeTarget != nil,
            canToggleComparisonSide: preview.canToggleComparisonSide,
            isPlaybackRunning: preview.isComparisonPlaybackRunning,
            selectProcessingMode: selectProcessingMode,
            chooseInputAudio: actions.chooseInputAudio,
            runCorrection: actions.startCorrectionProcessing,
            runMastering: actions.startMasteringProcessing,
            cancelCorrection: actions.cancelCorrectionProcessing,
            cancelMastering: actions.cancelMasteringProcessing,
            togglePlayback: preview.toggleComparisonPlayback,
            stopPlayback: {
                preview.stopPlayback()
            },
            toggleComparisonSide: preview.toggleComparisonSide
        )
    }

    private var stemCommandActions: VelouraCommandActions {
        let model = runtime.stemWorkspaceModel
        let preview = model.previewController
        let isCorrectionRunning = stemCorrectionIsRunning
        let isMasteringRunning = stemMasteringIsRunning

        return VelouraCommandActions(
            processingMode: .stem,
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
            canTogglePlayback: preview.canToggleComparisonPlayback,
            canStopPlayback: preview.activeTarget != nil,
            canToggleComparisonSide: preview.canToggleComparisonSide,
            isPlaybackRunning: preview.isComparisonPlaybackRunning,
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
            },
            togglePlayback: {
                model.stopAuxiliaryPreviewPlayback()
                preview.toggleComparisonPlayback()
            },
            stopPlayback: {
                preview.stopPlayback()
            },
            toggleComparisonSide: {
                model.stopAuxiliaryPreviewPlayback()
                preview.toggleComparisonSide()
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
