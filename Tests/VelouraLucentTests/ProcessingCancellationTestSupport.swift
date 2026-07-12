import Foundation

enum ProcessingSaveWaitOutcome: Equatable {
    case saveStarted
    case taskFinished
    case timedOut

    func failureMessage(operation: String) -> String {
        switch self {
        case .saveStarted:
            return ""
        case .taskFinished:
            return "\(operation)が書き出し工程へ到達する前に終了しました"
        case .timedOut:
            return "\(operation)が5分以内に書き出し工程へ到達しませんでした"
        }
    }
}

func waitForSaveStartOrTaskCompletion(
    saveEvents: AsyncStream<Void>,
    taskFinished: DispatchSemaphore,
    timeout: DispatchTimeInterval = .seconds(300)
) async -> ProcessingSaveWaitOutcome {
    let saveStarted = DispatchSemaphore(value: 0)
    let observer = Task {
        var iterator = saveEvents.makeAsyncIterator()
        if await iterator.next() != nil {
            saveStarted.signal()
        }
    }
    defer { observer.cancel() }

    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = DispatchTime.now() + timeout
            while DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds {
                if saveStarted.wait(timeout: .now() + .milliseconds(50)) == .success {
                    continuation.resume(returning: .saveStarted)
                    return
                }
                if taskFinished.wait(timeout: .now()) == .success {
                    continuation.resume(returning: .taskFinished)
                    return
                }
            }
            continuation.resume(returning: .timedOut)
        }
    }
}
