import Foundation
import Observation

@MainActor
@Observable
final class StemModeWorkspaceModel {
    let session: StemWorkflowSession
    /// 通常モードとは共有しない、Stem Mode専用の実音声preview stateです。
    let previewController = AudioPreviewController()
    /// 選択中Stemのraw／補正後だけを扱う、2mix試聴とは独立したpreview stateです。
    let stemPreviewController = AudioPreviewController()
    /// 補正済み純粋加算とStem再ミックスのA/Bだけを扱う専用preview stateです。
    let remixPreviewController = AudioPreviewController()

    private(set) var selectedInputURL: URL?
    private(set) var selectedInputFileInfo: AudioFileInfo?
    private(set) var isInspectingInput = false
    private(set) var isStartingRun = false
    private(set) var exportingArtifactIDs: Set<String> = []
    private(set) var previewArtifacts: [StemAudioArtifact] = []
    private(set) var finalCommitLockState: StemModeFinalCommitLockState = .unlocked
    private(set) var isModelOperationInProgress = false
    private(set) var cancellingProcessDomain: StemModeProcessDomain?
    var presentedError: StemModeWorkspaceErrorPresentation?

    var selectedMasteringProfile: MasteringProfile = .streaming {
        didSet {
            guard selectedMasteringProfile != oldValue else { return }
            isApplyingMasteringProfile = true
            masteringSettings = selectedMasteringProfile.settings
            isApplyingMasteringProfile = false
            isUsingCustomMasteringSettings = false
        }
    }

    var masteringSettings: MasteringSettings = MasteringProfile.streaming.settings {
        didSet {
            guard !isApplyingMasteringProfile else { return }
            isUsingCustomMasteringSettings = masteringSettings != selectedMasteringProfile.settings
        }
    }

    var selectedAnalysisMode: AudioAnalysisMode = .auto

    private(set) var isUsingCustomMasteringSettings = false
    private(set) var selectedCorrectionRole: StemRole = .vocals
    private(set) var selectedStemPreviewRole: StemRole = .vocals
    private(set) var correctionSettings = StemRoleCorrectionSettings(
        all: DenoiseStrength.balanced.settings
    )
    private(set) var separationSettings: StemSeparationSettings?
    private(set) var runContract: StemModelRunContract?
    private(set) var modelPresentation: StemModeModelPresentation?
    private(set) var remixAnalysisPresentation: StemModeRemixAnalysisPresentation?
    private(set) var automaticRemixPlan: StemRemixAutomaticPlan?
    private(set) var manualRemixOverrides = StemRemixManualOverrides()
    private(set) var isRemixManualEditingEnabled = false
    private(set) var qualityReports: StemModeQualityReports?
    private(set) var finalArtifact: StemAudioArtifact?
    /// 選択した入力ファイルそのものの表示・試聴用評価です。
    private(set) var inputEvaluation: StemAudioEvaluationSnapshot?
    private(set) var inputDisplayMetrics: AudioMetricSnapshot?
    private(set) var inputDisplayNoiseMeasurements: NoiseMeasurementSnapshot?
    private(set) var inputDisplayAudioAnalysis: AnalysisData?
    /// 補正workflowが作るcanonical input評価です。入力表示の正本には使用しません。
    private(set) var workflowInputEvaluation: StemAudioEvaluationSnapshot?
    private(set) var finalEvaluation: StemAudioEvaluationSnapshot?
    private(set) var inputSpectrogram: SpectrogramSnapshot?
    private(set) var correctedRemixSpectrogram: SpectrogramSnapshot?
    private(set) var finalSpectrogram: SpectrogramSnapshot?
    private(set) var isAnalyzingDisplayAudio = false
    private(set) var isAnalyzingInput = false
    private(set) var inputAnalysisError: String?
    private(set) var displayAnalysisError: String?
    private(set) var stemEvaluationsByRole: [StemRole: StemModeStemEvaluationPresentation] = [:]

    @ObservationIgnored private let actions: StemModeWorkspaceActions
    @ObservationIgnored private var inputInspectionIdentifier: UUID?
    @ObservationIgnored private var isApplyingMasteringProfile = false
    @ObservationIgnored private var displayAnalysisGeneration = UUID()
    @ObservationIgnored private var displayAnalysisTask: Task<Void, Never>?
    @ObservationIgnored private var inputAnalysisGeneration = UUID()
    @ObservationIgnored private var inputAnalysisTask: Task<Void, Never>?

    init(
        session: StemWorkflowSession,
        actions: StemModeWorkspaceActions
    ) {
        self.session = session
        self.actions = actions
    }

    var stemEvaluations: [StemModeStemEvaluationPresentation] {
        (runContract?.activeRoles ?? []).compactMap { stemEvaluationsByRole[$0] }
    }

    var availableStemRoles: [StemRole] {
        if let runContract {
            return runContract.activeRoles
        }
        if let modelPresentation {
            return modelPresentation.runContract.activeRoles
        }
        if let separationSettings {
            return StemProductionModelProfile.profile(for: separationSettings.model).sourceOrder
        }
        return StemProductionModelProfile.profile(for: .htdemucs).sourceOrder
    }

    /// 実行前は選択モデルの契約、実行開始後はSessionが保持するrun契約の工程を表示します。
    var correctionDisplayProgress: [StemModeProcessStepProgress] {
        if session.runContract != nil {
            return session.correctionDisplayProgress
        }
        let roles = runContract?.activeRoles ?? availableStemRoles
        return StemModeProcessStep.correctionSteps(for: roles).map {
            StemModeProcessStepProgress(step: $0, status: .pending, fraction: 0)
        }
    }

    var selectedRawStemPreviewURL: URL? {
        validatedStemArtifact(kind: .rawStem(selectedStemPreviewRole))?.fileURL
    }

    var selectedCorrectedStemPreviewURL: URL? {
        validatedStemArtifact(kind: .correctedStem(selectedStemPreviewRole))?.fileURL
    }

    var selectedRoleCorrectionSettings: CorrectionSettings {
        correctionSettings.settings(for: selectedCorrectionRole)
    }

    var selectedDenoiseStrength: DenoiseStrength {
        selectedRoleCorrectionSettings.profile
    }

    var isUsingCustomCorrectionSettings: Bool {
        selectedRoleCorrectionSettings != selectedDenoiseStrength.settings
    }

    var exportableArtifacts: [StemAudioArtifact] {
        var artifactsByID: [String: StemAudioArtifact] = [:]
        for state in session.artifactStates {
            guard let artifact = state.artifact,
                  artifact.kind.isStemModeUserExportable,
                  state.allowsStemModeExport else {
                continue
            }
            artifactsByID[artifact.id] = artifact
        }
        return artifactsByID.values.sorted { lhs, rhs in
            let leftRank = lhs.kind.stemModeExportSortRank
            let rightRank = rhs.kind.stemModeExportSortRank
            if leftRank == rightRank {
                return lhs.id < rhs.id
            }
            return leftRank < rightRank
        }
    }

    var isRunActive: Bool {
        switch session.state {
        case .running:
            true
        case .ready:
            session.runID != nil
        case .readyForRemix, .readyForMastering:
            false
        case .idle,
             .completed,
             .failed:
            false
        }
    }

    var isExportingAnyArtifact: Bool {
        !exportingArtifactIDs.isEmpty
    }

    var canChooseInput: Bool {
        !isRunActive
            && !isStartingRun
            && !isInspectingInput
    }

    var hasValidatedModelPresentation: Bool {
        modelPresentation != nil
    }

    var canRunCorrection: Bool {
        selectedInputURL != nil
            && separationSettings != nil
            && modelPresentation != nil
            && !isRunActive
            && !isStartingRun
            && !isInspectingInput
            && !isModelOperationInProgress
    }

    var canRunMastering: Bool {
        guard let runID = session.runID else {
            return false
        }
        switch session.state {
        case .readyForMastering(let readyRunID), .completed(let readyRunID):
            guard readyRunID == runID else { return false }
        default:
            return false
        }
        return !isStartingRun
            && !isInspectingInput
            && !isModelOperationInProgress
    }

    var canRunRemix: Bool {
        guard automaticRemixPlan != nil,
              let runID = session.runID else {
            return false
        }
        switch session.state {
        case .readyForRemix(let readyRunID),
             .readyForMastering(let readyRunID),
             .completed(let readyRunID):
            guard readyRunID == runID else { return false }
        default:
            return false
        }
        return !isStartingRun
            && !isInspectingInput
            && !isModelOperationInProgress
    }

    var canCancelProcessing: Bool {
        isRunActive
            && !isStartingRun
            && cancellingProcessDomain == nil
            && finalCommitLockState == .unlocked
    }

    var isCorrectionCancelling: Bool {
        cancellingProcessDomain == .correction
    }

    var isRemixCancelling: Bool {
        cancellingProcessDomain == .remix
    }

    var isMasteringCancelling: Bool {
        cancellingProcessDomain == .mastering
    }

    var isMasteringSettingsDisabled: Bool {
        isRunActive || isStartingRun
    }

    var isCorrectionSettingsDisabled: Bool {
        return isRunActive || isStartingRun
    }

    var isRemixSettingsDisabled: Bool {
        selectedInputURL == nil || isInspectingInput || isRunActive || isStartingRun
    }

    var inputPreviewArtifact: StemAudioArtifact? {
        previewArtifacts.first(where: { $0.kind == .input44100 })
    }

    var inputPreviewURL: URL? {
        selectedInputURL
    }

    var correctedPureSumPreviewArtifact: StemAudioArtifact? {
        previewArtifacts.first(where: { $0.kind == .correctedPureSum48000 })
    }

    var remixedPreviewArtifact: StemAudioArtifact? {
        previewArtifacts.first(where: { $0.kind == .remixed48000 })
    }

    /// 既存の入力／処理後／最終版previewでは、再ミックスがあればそれを優先します。
    var correctedRemixPreviewArtifact: StemAudioArtifact? {
        remixedPreviewArtifact ?? correctedPureSumPreviewArtifact
    }

    var finalPreviewArtifact: StemAudioArtifact? {
        previewArtifacts.first(where: { $0.kind == .finalMaster })
    }

    var correctedRemixEvaluation: StemAudioEvaluationSnapshot? {
        remixAnalysisPresentation?.processedRemixEvaluation
            ?? remixAnalysisPresentation?.correctedRemixEvaluation
    }

    var effectiveRemixSettings: StemRemixSettings? {
        automaticRemixPlan.map { plan in
            isRemixManualEditingEnabled
                ? manualRemixOverrides.applying(to: plan.settings)
                : plan.settings
        }
    }

    /// 補正前は中立値、補正後は自動値を土台に、手動中だけ変更済み項目を上書きします。
    /// 実行可否は`effectiveRemixSettings`で判定し、補正前の表示値を実行には使いません。
    var displayedRemixSettings: StemRemixSettings {
        let base = automaticRemixPlan?.settings ?? StemRemixSettings()
        return isRemixManualEditingEnabled
            ? manualRemixOverrides.applying(to: base)
            : base
    }

    var inputMetrics: AudioMetricSnapshot? {
        inputDisplayMetrics
    }

    var correctedRemixMetrics: AudioMetricSnapshot? {
        correctedRemixEvaluation?.audioMetrics
    }

    var finalMetrics: AudioMetricSnapshot? {
        finalEvaluation?.audioMetrics
    }

    var inputNoiseMeasurements: NoiseMeasurementSnapshot? {
        inputDisplayNoiseMeasurements
    }

    var correctedRemixNoiseMeasurements: NoiseMeasurementSnapshot? {
        correctedRemixEvaluation?.noiseMeasurements
    }

    var finalNoiseMeasurements: NoiseMeasurementSnapshot? {
        finalEvaluation?.noiseMeasurements
    }

    func inspectInput(_ inputURL: URL) async {
        guard canChooseInput else {
            presentError(
                title: "入力を変更できません",
                message: "Stem Mode処理の実行中は入力音源を変更できません。"
            )
            return
        }

        let identifier = UUID()
        inputInspectionIdentifier = identifier
        isInspectingInput = true
        presentedError = nil
        defer {
            if inputInspectionIdentifier == identifier {
                isInspectingInput = false
                inputInspectionIdentifier = nil
            }
        }

        do {
            try await actions.inspectInput(inputURL)
            guard inputInspectionIdentifier == identifier else { return }
            try await actions.resetForInputChange()
            acceptSelectedInput(inputURL)
        } catch is CancellationError {
            return
        } catch {
            guard inputInspectionIdentifier == identifier else { return }
            presentError(
                title: "入力音源を確認できません",
                message: error.localizedDescription
            )
        }

    }
    func resetMasteringSettingsToProfile() {
        isApplyingMasteringProfile = true
        masteringSettings = selectedMasteringProfile.settings
        isApplyingMasteringProfile = false
        isUsingCustomMasteringSettings = false
    }

    func selectCorrectionRole(_ role: StemRole) {
        guard availableStemRoles.contains(role) else { return }
        guard selectedCorrectionRole != role else { return }
        selectedCorrectionRole = role
    }

    func selectStemPreviewRole(_ role: StemRole) {
        guard availableStemRoles.contains(role) else { return }
        guard selectedStemPreviewRole != role else { return }
        stemPreviewController.stopPlayback()
        selectedStemPreviewRole = role
        refreshSelectedStemPreviewSources()
    }

    func applyCorrectionProfile(_ profile: DenoiseStrength) throws {
        try requireMutableCorrectionSettings()
        correctionSettings = correctionSettings.replacing(
            profile.settings,
            for: selectedCorrectionRole
        )
    }

    func updateCorrectionSettings(
        _ update: (inout CorrectionSettings) -> Void
    ) throws {
        try requireMutableCorrectionSettings()
        var updated = selectedRoleCorrectionSettings
        update(&updated)
        updated.profile = selectedDenoiseStrength
        correctionSettings = correctionSettings.replacing(
            updated,
            for: selectedCorrectionRole
        )
    }

    func resetCorrectionSettingsToProfile() throws {
        try applyCorrectionProfile(selectedDenoiseStrength)
    }

    func setProductionSeparationSettings(
        _ settings: StemSeparationSettings
    ) throws {
        try requireMutableRunSettings()
        _ = try settings.validatedParameters()
        let isApproved = settings.shifts == 2
            && settings.overlap == 0.25
            && settings.split
            && settings.segmentLength == .modelContract
            && settings.batchSize == 1
            && settings.seed != nil
        guard isApproved else {
            throw StemModeWorkspaceSettingsError.unapprovedProductionSettings
        }
        separationSettings = settings
        reconcileRoleSelections()
    }

    func clearSeparationSettings() {
        guard !isRunActive, !isStartingRun else { return }
        separationSettings = nil
        reconcileRoleSelections()
    }

    func setModelPresentation(_ presentation: StemModeModelPresentation) {
        modelPresentation = presentation
        reconcileRoleSelections()
    }

    func beginCorrection() async {
        guard let selectedInputURL else {
            presentError(
                title: "Stem Modeを開始できません",
                message: "先に入力音源を選択してください。"
            )
            return
        }
        guard let separationSettings else {
            presentError(
                title: "Stem Modeを開始できません",
                message: "承認済みの本番分離設定がまだ準備されていません。"
            )
            return
        }
        guard modelPresentation != nil else {
            presentError(
                title: "Stem Modeを開始できません",
                message: "検証済みactiveモデルの情報がまだ準備されていません。"
            )
            return
        }
        guard canRunCorrection else {
            presentError(
                title: "Stem Modeを開始できません",
                message: "入力確認または別のStem Mode処理が進行中です。"
            )
            return
        }

        isStartingRun = true
        presentedError = nil
        let previousRemixAnalysisPresentation = remixAnalysisPresentation
        let previousQualityReports = qualityReports
        let previousFinalArtifact = finalArtifact
        let previousInputEvaluation = inputEvaluation
        let previousFinalEvaluation = finalEvaluation
        let previousStemEvaluationsByRole = stemEvaluationsByRole
        let previousPreviewArtifacts = previewArtifacts
        let request = StemModeStartRequest(
            inputURL: selectedInputURL,
            separationSettings: separationSettings,
            correctionSettings: correctionSettings,
            masteringProfile: selectedMasteringProfile,
            masteringSettings: masteringSettings,
            analysisMode: StemAudioAnalysisMode(selectedAnalysisMode)
        )

        do {
            try await actions.beginCorrection(request)
        } catch is CancellationError {
            remixAnalysisPresentation = previousRemixAnalysisPresentation
            qualityReports = previousQualityReports
            finalArtifact = previousFinalArtifact
            inputEvaluation = previousInputEvaluation
            finalEvaluation = previousFinalEvaluation
            stemEvaluationsByRole = previousStemEvaluationsByRole
            replacePreviewSources(previousPreviewArtifacts)
            isStartingRun = false
            return
        } catch {
            remixAnalysisPresentation = previousRemixAnalysisPresentation
            qualityReports = previousQualityReports
            finalArtifact = previousFinalArtifact
            inputEvaluation = previousInputEvaluation
            finalEvaluation = previousFinalEvaluation
            stemEvaluationsByRole = previousStemEvaluationsByRole
            replacePreviewSources(previousPreviewArtifacts)
            presentError(
                title: "Stem Modeを開始できません",
                message: error.localizedDescription
            )
        }
        isStartingRun = false
    }

    func beginMastering() async {
        guard canRunMastering else {
            presentError(
                title: "マスタリングを開始できません",
                message: "Stem再ミックスの検証が完了してからマスタリングを実行してください。"
            )
            return
        }
        isStartingRun = true
        presentedError = nil
        defer { isStartingRun = false }
        do {
            try await actions.beginMastering(
                StemModeMasteringRequest(masteringSettings: masteringSettings)
            )
        } catch is CancellationError {
            return
        } catch {
            presentError(
                title: "マスタリングを開始できません",
                message: error.localizedDescription
            )
        }
    }

    func beginRemix() async {
        guard canRunRemix, let effectiveRemixSettings else {
            let stemCount = runContract?.stemCount ?? availableStemRoles.count
            presentError(
                title: "再ミックスを開始できません",
                message: "補正済み\(stemCount)Stemと補正後の検証が完了してから再ミックスを実行してください。"
            )
            return
        }
        isStartingRun = true
        presentedError = nil
        defer { isStartingRun = false }
        do {
            switch session.state {
            case .readyForMastering, .completed:
                try actions.invalidateRemix()
            default:
                break
            }
            try await actions.beginRemix(
                StemModeRemixRequest(settings: effectiveRemixSettings)
            )
        } catch is CancellationError {
            return
        } catch {
            presentError(
                title: "再ミックスを開始できません",
                message: error.localizedDescription
            )
        }
    }

    func cancelCorrection() async {
        await performCancellation(
            domain: .correction,
            errorTitle: "補正をキャンセルできません",
            action: actions.cancelCorrection
        )
    }

    func cancelMastering() async {
        await performCancellation(
            domain: .mastering,
            errorTitle: "マスタリングをキャンセルできません",
            action: actions.cancelMastering
        )
    }

    func cancelRemix() async {
        await performCancellation(
            domain: .remix,
            errorTitle: "再ミックスをキャンセルできません",
            action: actions.cancelRemix
        )
    }

    private func performCancellation(
        domain: StemModeProcessDomain,
        errorTitle: String,
        action: @MainActor () async throws -> Void
    ) async {
        guard canCancelProcessing else { return }
        cancellingProcessDomain = domain
        defer {
            cancellingProcessDomain = nil
        }
        do {
            try await action()
        } catch is CancellationError {
            return
        } catch {
            presentError(
                title: errorTitle,
                message: error.localizedDescription
            )
        }
    }

    func revealArtifact(_ artifact: StemAudioArtifact) {
        actions.revealArtifact(artifact.fileURL)
    }

    func exportArtifact(
        _ artifact: StemAudioArtifact,
        as format: AudioExportFormat
    ) async {
        guard !exportingArtifactIDs.contains(artifact.id) else { return }
        exportingArtifactIDs.insert(artifact.id)
        defer { exportingArtifactIDs.remove(artifact.id) }
        do {
            let destinationURL = try await actions.exportArtifact(artifact, format)
            session.recordExportSuccess(
                artifact: artifact,
                destinationURL: destinationURL,
                fileInfo: try? AudioFileService.fileInfo(for: destinationURL)
            )
        } catch is CancellationError {
            return
        } catch {
            session.recordExportFailure(artifact: artifact, message: error.localizedDescription)
            presentError(
                title: "成果物を書き出せません",
                message: error.localizedDescription
            )
        }
    }

    func isExporting(_ artifact: StemAudioArtifact) -> Bool {
        exportingArtifactIDs.contains(artifact.id)
    }

    func setRemixAnalysisPresentation(
        _ presentation: StemModeRemixAnalysisPresentation?
    ) {
        remixAnalysisPresentation = presentation
    }

    func setAutomaticRemixPlan(_ plan: StemRemixAutomaticPlan) {
        automaticRemixPlan = plan
    }

    func setRemixManualEditingEnabled(_ isEnabled: Bool) throws {
        guard isEnabled != isRemixManualEditingEnabled else { return }
        try requireMutableRemixSettings()
        if !manualRemixOverrides.isEmpty {
            try invalidateRemixIfNeeded()
        }
        isRemixManualEditingEnabled = isEnabled
    }

    func setDrumsToBassMaskingEnabled(_ value: Bool?) throws {
        try prepareForManualRemixValueChange()
        manualRemixOverrides.drumsToBassEnabled = value
    }

    func setRemixResult(_ result: StemWorkflowRemixResult) {
        do {
            remixAnalysisPresentation = try StemModeRemixAnalysisPresentation(
                remixResult: result
            )
        } catch {
            presentError(
                title: "再ミックス解析を表示できません",
                message: error.localizedDescription
            )
        }
    }

    func clearRemixResult() {
        guard let correctionResultPresentation = remixAnalysisPresentation else {
            return
        }
        remixAnalysisPresentation = correctionResultPresentation.removingProcessedRemix()
        qualityReports = nil
        finalArtifact = nil
        finalEvaluation = nil
    }

    func setRemixGainDB(_ value: Float?, for role: StemRole) throws {
        try updateRemixRoleOverrides(for: role) { $0.gainDB = value }
    }

    func setRemixPan(_ value: Float?, for role: StemRole) throws {
        try updateRemixRoleOverrides(for: role) { $0.pan = value }
    }

    func setRemixReverbSend(_ value: Float?, for role: StemRole) throws {
        try updateRemixRoleOverrides(for: role) { $0.reverbSend = value }
    }

    func setDrumsToBassMasking(_ value: Float?) throws {
        try prepareForManualRemixValueChange()
        manualRemixOverrides.drumsToBassAmount = value
    }

    func setVocalsToAccompanimentMaskingEnabled(_ value: Bool?) throws {
        try prepareForManualRemixValueChange()
        manualRemixOverrides.vocalsToAccompanimentEnabled = value
    }

    func setVocalsToAccompanimentMasking(_ value: Float?) throws {
        try prepareForManualRemixValueChange()
        manualRemixOverrides.vocalsToAccompanimentAmount = value
    }

    func setRemixReturnLevel(_ value: Float?) throws {
        try prepareForManualRemixValueChange()
        manualRemixOverrides.reverbReturnLevel = value
    }

    func setRemixDecaySeconds(_ value: Float?) throws {
        try prepareForManualRemixValueChange()
        manualRemixOverrides.reverbDecaySeconds = value
    }

    func resetManualRemixOverrides() throws {
        guard !manualRemixOverrides.isEmpty else { return }
        try prepareForManualRemixValueChange()
        manualRemixOverrides.reset()
    }

    private func updateRemixRoleOverrides(
        for role: StemRole,
        update: (inout StemRemixRoleOverrides) -> Void
    ) throws {
        try prepareForManualRemixValueChange()
        var overrides = manualRemixOverrides.overrides(for: role)
        update(&overrides)
        manualRemixOverrides.setOverrides(overrides, for: role)
    }

    private func prepareForManualRemixValueChange() throws {
        guard isRemixManualEditingEnabled else {
            throw StemModeWorkspaceSettingsError.remixManualModeRequired
        }
        try requireMutableRemixSettings()
        try invalidateRemixIfNeeded()
    }

    private func requireMutableRemixSettings() throws {
        guard selectedInputURL != nil else {
            throw StemModeWorkspaceSettingsError.remixInputRequired
        }
        guard !isInspectingInput, !isRunActive, !isStartingRun else {
            throw StemModeWorkspaceSettingsError.settingsCannotChangeDuringRun
        }
        switch session.state {
        case .idle, .failed, .readyForRemix, .readyForMastering, .completed:
            break
        case .ready, .running:
            throw StemWorkflowSessionError.remixRequiresCorrectionCompletion
        }
    }

    private func invalidateRemixIfNeeded() throws {
        switch session.state {
        case .readyForMastering, .completed:
            try actions.invalidateRemix()
        case .idle, .failed, .readyForRemix:
            break
        case .ready, .running:
            throw StemWorkflowSessionError.remixRequiresCorrectionCompletion
        }
    }

    func setWorkflowInputEvaluation(_ evaluation: StemAudioEvaluationSnapshot?) {
        guard evaluation?.purpose == .canonicalInput || evaluation == nil else {
            return
        }
        workflowInputEvaluation = evaluation
    }

    func replaceStemEvaluations(
        _ presentations: [StemModeStemEvaluationPresentation]
    ) {
        var values: [StemRole: StemModeStemEvaluationPresentation] = [:]
        for presentation in presentations {
            values[presentation.role] = presentation
        }
        stemEvaluationsByRole = values
    }

    func setMasteringResult(_ result: StemMasteringResult) {
        qualityReports = StemModeQualityReports(masteringResult: result)
        finalArtifact = result.finalArtifact
        finalEvaluation = result.finalEvaluation
    }

    func clearMasteringResult() {
        qualityReports = nil
        finalArtifact = nil
        finalEvaluation = nil
    }

    /// Controllerがartifact検証を完了した後に、完全なpreview候補一覧を渡す境界です。
    /// 未検証のartifactをこのAPIへ渡してはいけません。
    func updatePreviewSources(
        from validatedArtifacts: [StemAudioArtifact]
    ) {
        var artifactsByID: [String: StemAudioArtifact] = [:]
        for artifact in validatedArtifacts where artifact.kind.isStemModePreviewable {
            if let existing = artifactsByID[artifact.id], existing != artifact {
                presentError(
                    title: "試聴候補を更新できません",
                    message: "同じIDで内容が異なる検証済み成果物があります（\(artifact.id)）。"
                )
                return
            }
            artifactsByID[artifact.id] = artifact
        }

        let sortedArtifacts = artifactsByID.values.sorted { lhs, rhs in
            let leftRank = lhs.kind.stemModePreviewSortRank
            let rightRank = rhs.kind.stemModePreviewSortRank
            if leftRank == rightRank {
                return lhs.id < rhs.id
            }
            return leftRank < rightRank
        }
        replacePreviewSources(sortedArtifacts)
        refreshSelectedStemPreviewSources()
    }

    func setFinalCommitLockState(_ state: StemModeFinalCommitLockState) {
        finalCommitLockState = state
    }

    /// Controllerが現在セッションの補正開始を確定した時に、新しい処理表示へ切り替えます。
    func acceptSessionStart(runContract: StemModelRunContract) {
        clearRunPresentation(resetManualRemixDraft: false)
        self.runContract = runContract
        reconcileRoleSelections()
    }

    func setModelOperationInProgress(_ isInProgress: Bool) {
        isModelOperationInProgress = isInProgress
    }

    func clearModelPresentation() {
        modelPresentation = nil
        reconcileRoleSelections()
    }

    private func requireMutableRunSettings() throws {
        guard !isRunActive, !isStartingRun else {
            throw StemModeWorkspaceSettingsError.settingsCannotChangeDuringRun
        }
    }

    private func requireMutableCorrectionSettings() throws {
        guard !isCorrectionSettingsDisabled else {
            throw StemModeWorkspaceSettingsError.settingsCannotChangeDuringRun
        }
    }

    func presentControllerFailure(title: String, message: String) {
        presentError(title: title, message: message)
    }

    func stopPreviewPlayback() {
        previewController.stopPlayback()
        stemPreviewController.stopPlayback()
        remixPreviewController.stopPlayback()
    }

    func stopTwoMixPreviewPlayback() {
        previewController.stopPlayback()
    }

    func stopStemPreviewPlayback() {
        stemPreviewController.stopPlayback()
    }

    func stopRemixPreviewPlayback() {
        remixPreviewController.stopPlayback()
    }

    func stopAuxiliaryPreviewPlayback() {
        stemPreviewController.stopPlayback()
        remixPreviewController.stopPlayback()
    }

    func refreshSelectedStemPreviewSources() {
        stemPreviewController.setComparisonPair(.inputVsCorrected)
        stemPreviewController.preparePreview(
            for: selectedRawStemPreviewURL,
            target: .input
        )
        stemPreviewController.preparePreview(
            for: selectedCorrectedStemPreviewURL,
            target: .corrected
        )
        stemPreviewController.preparePreview(for: nil, target: .mastered)
    }

    func dismissPresentedError() {
        presentedError = nil
    }

    private func clearRunPresentation(resetManualRemixDraft: Bool) {
        runContract = nil
        remixAnalysisPresentation = nil
        automaticRemixPlan = nil
        if resetManualRemixDraft {
            manualRemixOverrides.reset()
            isRemixManualEditingEnabled = false
        }
        qualityReports = nil
        finalArtifact = nil
        workflowInputEvaluation = nil
        finalEvaluation = nil
        stemEvaluationsByRole = [:]
        replacePreviewSources([])
        clearStemPreviewSources()
        clearRemixPreviewSources()
        reconcileRoleSelections()
    }

    /// 選択中のモデル／結果契約に存在しない役割をUIとpreviewへ残しません。
    private func reconcileRoleSelections() {
        let roles = availableStemRoles
        guard let fallbackRole = roles.contains(.vocals) ? StemRole.vocals : roles.first else {
            clearStemPreviewSources()
            return
        }

        if !roles.contains(selectedCorrectionRole) {
            selectedCorrectionRole = fallbackRole
        }
        if !roles.contains(selectedStemPreviewRole) {
            stemPreviewController.stopPlayback()
            selectedStemPreviewRole = fallbackRole
            refreshSelectedStemPreviewSources()
        }
    }

    func resetRunPresentationAfterCorrectionCancellation() {
        clearRunPresentation(resetManualRemixDraft: false)
    }

    func resetRunPresentationAfterCorrectionFailure() {
        clearRunPresentation(resetManualRemixDraft: false)
    }

    func resetRunPresentationForInputChange() {
        clearRunPresentation(resetManualRemixDraft: true)
    }

    private func replacePreviewSources(_ artifacts: [StemAudioArtifact]) {
        let previousPureSum = correctedPureSumPreviewArtifact
        let previousRemix = remixedPreviewArtifact
        let previousCorrected = correctedRemixPreviewArtifact
        let previousFinal = finalPreviewArtifact
        previewArtifacts = artifacts

        if previousPureSum != correctedPureSumPreviewArtifact
            || previousRemix != remixedPreviewArtifact
            || previousCorrected != correctedRemixPreviewArtifact
            || previousFinal != finalPreviewArtifact {
            preparePreviewSources()
            prepareRemixPreviewSources()
            refreshDisplayAnalysis()
        }
    }

    private func preparePreviewSources() {
        previewController.stopPlayback()
        previewController.setComparisonPair(
            finalPreviewArtifact == nil && correctedRemixPreviewArtifact != nil
                ? .inputVsCorrected
                : .inputVsMastered
        )
        previewController.preparePreview(
            for: correctedRemixPreviewArtifact?.fileURL,
            target: .corrected
        )
        previewController.preparePreview(
            for: finalPreviewArtifact?.fileURL,
            target: .mastered
        )
    }

    private func prepareRemixPreviewSources() {
        remixPreviewController.stopPlayback()
        remixPreviewController.setComparisonPair(.inputVsCorrected)
        remixPreviewController.preparePreview(
            for: correctedPureSumPreviewArtifact?.fileURL,
            target: .input
        )
        remixPreviewController.preparePreview(
            for: remixedPreviewArtifact?.fileURL,
            target: .corrected
        )
        remixPreviewController.preparePreview(for: nil, target: .mastered)
    }

    private func refreshDisplayAnalysis() {
        displayAnalysisTask?.cancel()
        let generation = UUID()
        displayAnalysisGeneration = generation
        let correctedURL = correctedRemixPreviewArtifact?.fileURL
        let finalURL = finalPreviewArtifact?.fileURL

        correctedRemixSpectrogram = nil
        finalSpectrogram = nil
        displayAnalysisError = nil

        guard correctedURL != nil || finalURL != nil else {
            isAnalyzingDisplayAudio = false
            return
        }

        isAnalyzingDisplayAudio = true
        displayAnalysisTask = Task { [weak self] in
            async let correctedResult = Self.loadSpectrogram(correctedURL)
            async let finalResult = Self.loadSpectrogram(finalURL)
            let (corrected, final) = await (
                correctedResult,
                finalResult
            )
            guard !Task.isCancelled,
                  let self,
                  self.displayAnalysisGeneration == generation else {
                return
            }

            correctedRemixSpectrogram = corrected.snapshot
            finalSpectrogram = final.snapshot
            displayAnalysisError = [corrected.error, final.error]
                .compactMap { $0 }
                .first
            isAnalyzingDisplayAudio = false
            displayAnalysisTask = nil
        }
    }

    private func acceptSelectedInput(_ inputURL: URL) {
        clearSelectedInputPresentation()
        selectedInputURL = inputURL
        selectedInputFileInfo = try? AudioFileService.fileInfo(for: inputURL)
        session.recordInputSelection(URL: inputURL, fileInfo: selectedInputFileInfo)

        previewController.stopPlayback()
        previewController.setComparisonPair(.inputVsCorrected)
        previewController.preparePreviewPlaceholder(for: inputURL, target: .input)
        startInputDisplayAnalysis(for: inputURL)
    }

    private func startInputDisplayAnalysis(for inputURL: URL) {
        inputAnalysisTask?.cancel()
        let generation = UUID()
        inputAnalysisGeneration = generation
        let analysisMode = StemAudioAnalysisMode(selectedAnalysisMode)
        inputEvaluation = nil
        inputDisplayMetrics = nil
        inputDisplayNoiseMeasurements = nil
        inputDisplayAudioAnalysis = nil
        inputSpectrogram = nil
        inputAnalysisError = nil
        isAnalyzingInput = true

        inputAnalysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let logHandler: @Sendable (String) -> Void = { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.inputAnalysisGeneration == generation,
                              self.selectedInputURL?.standardizedFileURL == inputURL.standardizedFileURL else {
                            return
                        }
                        self.session.recordInputDisplayAnalysisLog(message)
                    }
                }
                let result = try await actions.analyzeInputForDisplay(
                    inputURL,
                    analysisMode,
                    logHandler
                )
                guard !Task.isCancelled,
                      inputAnalysisGeneration == generation,
                      selectedInputURL?.standardizedFileURL == inputURL.standardizedFileURL else {
                    return
                }
                let hasValidEvaluationPurpose = result.evaluation?.purpose == .canonicalInput
                    || result.evaluation == nil
                inputEvaluation = hasValidEvaluationPurpose ? result.evaluation : nil
                inputDisplayMetrics = result.metrics
                inputDisplayNoiseMeasurements = result.noiseMeasurements
                inputDisplayAudioAnalysis = result.audioAnalysis
                inputSpectrogram = result.spectrogram
                inputAnalysisError = hasValidEvaluationPurpose
                    ? result.warning
                    : "入力表示用ではない解析結果を受け取ったため、測定値を表示しません。"
                session.recordInputAnalysis(
                    evaluation: inputEvaluation,
                    warning: inputAnalysisError
                )
                previewController.setPreviewSnapshot(
                    result.previewSnapshot,
                    for: .input,
                    sourceURL: inputURL,
                    integratedLoudnessLUFS: result.metrics?.integratedLoudnessLUFS
                )
                isAnalyzingInput = false
                inputAnalysisTask = nil
            } catch is CancellationError {
                if inputAnalysisGeneration == generation {
                    isAnalyzingInput = false
                    inputAnalysisTask = nil
                }
                return
            } catch {
                guard inputAnalysisGeneration == generation,
                      selectedInputURL?.standardizedFileURL == inputURL.standardizedFileURL else {
                    return
                }
                inputAnalysisError = error.localizedDescription
                session.recordInputAnalysisFailure(error.localizedDescription)
                isAnalyzingInput = false
                inputAnalysisTask = nil
            }
        }
    }

    private func clearSelectedInputPresentation() {
        inputAnalysisTask?.cancel()
        inputAnalysisTask = nil
        inputAnalysisGeneration = UUID()
        isAnalyzingInput = false
        inputAnalysisError = nil
        inputEvaluation = nil
        inputDisplayMetrics = nil
        inputDisplayNoiseMeasurements = nil
        inputDisplayAudioAnalysis = nil
        inputSpectrogram = nil
        previewController.preparePreviewPlaceholder(for: nil, target: .input)
        clearStemPreviewSources()
    }

    private func validatedStemArtifact(
        kind: StemArtifactKind
    ) -> StemAudioArtifact? {
        session.artifactStates.first { state in
            state.kind == kind
                && state.status == .valid
                && state.artifact?.kind == kind
        }?.artifact
    }

    private func clearStemPreviewSources() {
        stemPreviewController.stopPlayback()
        stemPreviewController.preparePreview(for: nil, target: .input)
        stemPreviewController.preparePreview(for: nil, target: .corrected)
        stemPreviewController.preparePreview(for: nil, target: .mastered)
    }

    private func clearRemixPreviewSources() {
        remixPreviewController.stopPlayback()
        remixPreviewController.preparePreview(for: nil, target: .input)
        remixPreviewController.preparePreview(for: nil, target: .corrected)
        remixPreviewController.preparePreview(for: nil, target: .mastered)
    }

    private static func loadSpectrogram(
        _ URL: URL?
    ) async -> (snapshot: SpectrogramSnapshot?, error: String?) {
        guard let URL else { return (nil, nil) }
        do {
            let snapshot = try await Task.detached(priority: .utility) {
                try Task.checkCancellation()
                return try AudioFileService.makeSpectrogramSnapshot(for: URL)
            }.value
            return (snapshot, nil)
        } catch is CancellationError {
            return (nil, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func presentError(title: String, message: String) {
        presentedError = StemModeWorkspaceErrorPresentation(
            title: title,
            message: message
        )
    }
}

private extension StemWorkflowArtifactDisplayState {
    var allowsStemModeExport: Bool {
        switch status {
        case .valid:
            true
        case .preparing, .available, .validating, .invalid:
            false
        }
    }
}
