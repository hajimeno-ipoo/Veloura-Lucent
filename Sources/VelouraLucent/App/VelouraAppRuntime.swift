import Foundation
import Observation

@MainActor
@Observable
final class VelouraAppRuntime {
    static let shared = VelouraAppRuntime()

    private(set) var processingMode: ProcessingMode = .standard

    let standardActions: ProcessingActions
    let stemModelManager: StemModelManager
    let stemWorkflowSession: StemWorkflowSession
    let stemWorkflowController: StemWorkflowController
    let stemWorkspaceModel: StemModeWorkspaceModel

    @ObservationIgnored private var didStart = false

    init(
        standardActions: ProcessingActions = ProcessingActions(
            notificationReporter: NotificationService.shared
        ),
        stemModelManager: StemModelManager = StemModelManager(),
        stemWorkflowSession: StemWorkflowSession = StemWorkflowSession(),
        stemWorkflowControllerFactory: ((
            StemWorkflowSession,
            StemModelManager
        ) -> StemWorkflowController)? = nil
    ) {
        self.standardActions = standardActions
        self.stemModelManager = stemModelManager
        self.stemWorkflowSession = stemWorkflowSession

        let controller = stemWorkflowControllerFactory?(
            stemWorkflowSession,
            stemModelManager
        ) ?? StemWorkflowController(
            session: stemWorkflowSession,
            modelManager: stemModelManager
        )
        let workspaceModel = StemModeWorkspaceModel(
            session: stemWorkflowSession,
            actions: controller.actions
        )
        controller.attachWorkspaceModel(workspaceModel)
        stemWorkflowController = controller
        stemWorkspaceModel = workspaceModel
    }

    var isModeSwitchDisabled: Bool {
        standardActions.job.isProcessing
            || standardActions.job.isMastering
            || stemWorkflowController.isProcessingRun
    }

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        await stemModelManager.inspectLocalResources()
        stemWorkflowController.synchronizeModelReadiness()
    }

    @discardableResult
    func selectMode(_ mode: ProcessingMode) -> Bool {
        guard !isModeSwitchDisabled else { return false }
        if processingMode == .standard, mode != .standard {
            standardActions.preview.stopPlayback()
        } else if processingMode == .stem, mode != .stem {
            stemWorkspaceModel.stopPreviewPlayback()
        }
        processingMode = mode
        return true
    }

    func shutdown() {
        stemWorkflowController.shutdown()
        standardActions.shutdown()
        stemModelManager.shutdown()
    }
}
