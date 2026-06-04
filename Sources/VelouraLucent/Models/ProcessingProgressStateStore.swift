struct ProcessingProgressStateStore<Step: Hashable> {
    private(set) var activeStep: Step?
    private(set) var completedSteps: Set<Step> = []
    private(set) var skippedSteps: Set<Step> = []
    private(set) var failedSteps: Set<Step> = []
    private(set) var activeStepDetail: String?

    mutating func reset() {
        activeStep = nil
        completedSteps = []
        skippedSteps = []
        failedSteps = []
        activeStepDetail = nil
    }

    mutating func apply(
        step: Step,
        state: ProcessingProgressEvent.State,
        detail: String?
    ) {
        switch state {
        case .started:
            if let activeStep, activeStep != step {
                completedSteps.insert(activeStep)
            }
            skippedSteps.remove(step)
            failedSteps.remove(step)
            activeStep = step
            activeStepDetail = detail
        case .completed:
            completedSteps.insert(step)
            skippedSteps.remove(step)
            failedSteps.remove(step)
            clearActiveStep(ifMatching: step)
        case .skipped:
            skippedSteps.insert(step)
            completedSteps.remove(step)
            failedSteps.remove(step)
            clearActiveStep(ifMatching: step)
        case .failed:
            failedSteps.insert(step)
            completedSteps.remove(step)
            skippedSteps.remove(step)
            clearActiveStep(ifMatching: step)
        case .detail:
            activeStep = step
            activeStepDetail = detail
        }
    }

    mutating func completeAll<S: Sequence>(_ steps: S) where S.Element == Step {
        completedSteps = Set(steps).subtracting(skippedSteps)
        activeStep = nil
        activeStepDetail = nil
    }

    mutating func failActiveStep() {
        if let activeStep {
            failedSteps.insert(activeStep)
        }
        activeStep = nil
        activeStepDetail = nil
    }

    private mutating func clearActiveStep(ifMatching step: Step) {
        guard activeStep == step else { return }
        activeStep = nil
        activeStepDetail = nil
    }
}
