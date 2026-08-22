import Foundation
import Testing

struct ProcessingCancellationTestSupportTests {
    @Test
    func waitReturnsWhenProcessingFinishesBeforeSave() async {
        let (saveEvents, _) = AsyncStream<Void>.makeStream()
        let taskFinished = DispatchSemaphore(value: 0)
        taskFinished.signal()

        let outcome = await waitForSaveStartOrTaskCompletion(
            saveEvents: saveEvents,
            taskFinished: taskFinished,
            timeout: .seconds(1)
        )

        #expect(outcome == .taskFinished)
    }

    @Test
    func waitTimesOutWhenNeitherEventOccurs() async {
        let (saveEvents, _) = AsyncStream<Void>.makeStream()
        let taskFinished = DispatchSemaphore(value: 0)

        let outcome = await waitForSaveStartOrTaskCompletion(
            saveEvents: saveEvents,
            taskFinished: taskFinished,
            timeout: .milliseconds(20)
        )

        #expect(outcome == .timedOut)
    }
}
