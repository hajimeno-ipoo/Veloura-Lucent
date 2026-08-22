import Testing
@testable import VelouraLucent

struct ProcessingProgressStateStoreTests {
    private enum Step: Hashable {
        case first
        case second
        case third
    }

    @Test
    func startedStepBecomesActiveAndCompletesPreviousActiveStep() {
        var store = ProcessingProgressStateStore<Step>()

        store.apply(step: .first, state: .started, detail: nil)
        store.apply(step: .second, state: .started, detail: "確認中")

        #expect(store.activeStep == .second)
        #expect(store.activeStepDetail == "確認中")
        #expect(store.completedSteps == [.first])
    }

    @Test
    func completedSkippedAndFailedStatesRemainExclusive() {
        var store = ProcessingProgressStateStore<Step>()

        store.apply(step: .first, state: .completed, detail: nil)
        store.apply(step: .first, state: .skipped, detail: nil)
        store.apply(step: .first, state: .failed, detail: nil)

        #expect(store.completedSteps.isEmpty)
        #expect(store.skippedSteps.isEmpty)
        #expect(store.failedSteps == [.first])
    }

    @Test
    func completeAllKeepsSkippedStepsOutOfCompletedSteps() {
        var store = ProcessingProgressStateStore<Step>()

        store.apply(step: .second, state: .skipped, detail: nil)
        store.apply(step: .third, state: .started, detail: "処理中")
        store.completeAll([Step.first, .second, .third])

        #expect(store.completedSteps == [.first, .third])
        #expect(store.skippedSteps == [.second])
        #expect(store.activeStep == nil)
        #expect(store.activeStepDetail == nil)
    }

    @Test
    func failActiveStepAndResetClearExpectedState() {
        var store = ProcessingProgressStateStore<Step>()

        store.apply(step: .first, state: .started, detail: "処理中")
        store.failActiveStep()

        #expect(store.failedSteps == [.first])
        #expect(store.activeStep == nil)
        #expect(store.activeStepDetail == nil)

        store.reset()

        #expect(store.completedSteps.isEmpty)
        #expect(store.skippedSteps.isEmpty)
        #expect(store.failedSteps.isEmpty)
    }
}
