import SwiftUI

struct SidebarProcessStatusSection: Identifiable {
    let id: String
    let title: String
    let status: String
    let activeStepTitle: String?
    let activeStepDetail: String?
    let startedAt: Date?
    let finishedAt: Date?
    let isRunning: Bool
    let isComplete: Bool
    let hasFailed: Bool
    let progress: Double
    let steps: [SidebarProcessStepDisplay]
    let tint: Color
}

struct SidebarProcessingStatusListView: View {
    let sections: [SidebarProcessStatusSection]

    var body: some View {
        Group {
            if sections.contains(where: \.isRunning) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    rows(now: timeline.date)
                }
            } else {
                rows(now: .now)
            }
        }
    }

    private func rows(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections.indices, id: \.self) { index in
                let section = sections[index]
                SidebarProcessStatusRow(
                    title: section.title,
                    status: section.status,
                    activeStepTitle: section.activeStepTitle,
                    activeStepDetail: section.activeStepDetail,
                    startedAt: section.startedAt,
                    finishedAt: section.finishedAt,
                    isRunning: section.isRunning,
                    isComplete: section.isComplete,
                    hasFailed: section.hasFailed,
                    progress: section.progress,
                    steps: section.steps,
                    tint: section.tint,
                    now: now
                )

                if index < sections.count - 1 {
                    Divider()
                }
            }
        }
    }
}

struct SidebarProcessingStatusView: View {
    @Bindable var job: ProcessingJob

    var body: some View {
        SidebarProcessingStatusListView(sections: sections)
    }

    private var sections: [SidebarProcessStatusSection] {
        [
            SidebarProcessStatusSection(
                id: "correction",
                title: "補正",
                status: job.statusMessage,
                activeStepTitle: job.activeStep?.title,
                activeStepDetail: job.activeStepDetail,
                startedAt: job.processingStartedAt,
                finishedAt: job.processingFinishedAt,
                isRunning: job.isProcessing,
                isComplete: job.statusMessage == "完了",
                hasFailed: !job.failedSteps.isEmpty || job.lastError != nil,
                progress: job.progressValue,
                steps: correctionSteps,
                tint: correctionTint
            ),
            SidebarProcessStatusSection(
                id: "mastering",
                title: "マスタリング",
                status: job.masteringStatusMessage,
                activeStepTitle: job.masteringActiveStep?.title,
                activeStepDetail: job.masteringActiveStepDetail,
                startedAt: job.masteringStartedAt,
                finishedAt: job.masteringFinishedAt,
                isRunning: job.isMastering,
                isComplete: job.masteringStatusMessage == "完了",
                hasFailed: !job.failedMasteringSteps.isEmpty || job.masteringLastError != nil,
                progress: job.masteringProgressValue,
                steps: masteringSteps,
                tint: masteringTint
            ),
        ]
    }

    private var correctionSteps: [SidebarProcessStepDisplay] {
        ProcessingStep.allCases.map { step in
            SidebarProcessStepDisplay(
                id: step.eventID,
                title: step.title,
                detail: job.activeStep == step ? job.activeStepDetail : nil,
                state: stepState(
                    step: step,
                    activeStep: job.activeStep,
                    completedSteps: job.completedSteps,
                    skippedSteps: job.skippedSteps,
                    failedSteps: job.failedSteps
                )
            )
        }
    }

    private var masteringSteps: [SidebarProcessStepDisplay] {
        MasteringStep.allCases.map { step in
            SidebarProcessStepDisplay(
                id: step.eventID,
                title: step.title,
                detail: job.masteringActiveStep == step ? job.masteringActiveStepDetail : nil,
                state: stepState(
                    step: step,
                    activeStep: job.masteringActiveStep,
                    completedSteps: job.completedMasteringSteps,
                    skippedSteps: job.skippedMasteringSteps,
                    failedSteps: job.failedMasteringSteps
                )
            )
        }
    }

    private func stepState<Step: Hashable>(
        step: Step,
        activeStep: Step?,
        completedSteps: Set<Step>,
        skippedSteps: Set<Step>,
        failedSteps: Set<Step>
    ) -> SidebarProcessStepState {
        if failedSteps.contains(step) {
            return .failed
        }
        if activeStep == step {
            return .active
        }
        if completedSteps.contains(step) {
            return .completed
        }
        if skippedSteps.contains(step) {
            return .skipped
        }
        return .pending
    }

    private var correctionTint: Color {
        if job.isProcessing {
            return ProcessingStatusColors.active
        }
        if job.lastError != nil {
            return .red
        }
        if job.hasExistingOutput {
            return ProcessingStatusColors.complete
        }
        return .secondary
    }

    private var masteringTint: Color {
        if job.isMastering {
            return ProcessingStatusColors.active
        }
        if job.masteringLastError != nil {
            return .red
        }
        if job.hasExistingMasteredOutput {
            return ProcessingStatusColors.complete
        }
        return .secondary
    }

}
