import Foundation
import Testing
@testable import VelouraLucent

struct CancellableWorkerTests {
    private struct WorkerFailure: Error {}

    @Test
    func cancellingParentCancelsDetachedWorker() async {
        let (startedEvents, startedContinuation) = AsyncStream<Void>.makeStream()
        let continueWork = DispatchSemaphore(value: 0)
        let task = Task {
            try await runCancellableDetachedWorker {
                startedContinuation.yield()
                continueWork.wait()
                try Task.checkCancellation()
                return 1
            }
        }

        var startedIterator = startedEvents.makeAsyncIterator()
        _ = await startedIterator.next()
        task.cancel()
        continueWork.signal()

        do {
            _ = try await task.value
            Issue.record("キャンセル済みの作業は完了値を返してはいけません")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("CancellationError以外が返りました: \(error)")
        }
    }

    @Test
    func parentCancellationWinsOverWorkerFailure() async {
        let (startedEvents, startedContinuation) = AsyncStream<Void>.makeStream()
        let continueWork = DispatchSemaphore(value: 0)
        let task = Task {
            try await runCancellableDetachedWorker {
                startedContinuation.yield()
                continueWork.wait()
                throw WorkerFailure()
            }
        }

        var startedIterator = startedEvents.makeAsyncIterator()
        _ = await startedIterator.next()
        task.cancel()
        continueWork.signal()

        do {
            _ = try await task.value
            Issue.record("キャンセル済みの作業は完了してはいけません")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("親タスクのCancellationErrorよりワーカーのエラーが優先されました: \(error)")
        }
    }
}
