import Foundation

func runCancellableDetachedWorker<Result: Sendable>(
    priority: TaskPriority = .userInitiated,
    operation: @escaping @Sendable () throws -> Result
) async throws -> Result {
    let worker = Task.detached(priority: priority, operation: operation)
    return try await withTaskCancellationHandler {
        do {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } catch {
            try Task.checkCancellation()
            throw error
        }
    } onCancel: {
        worker.cancel()
    }
}

func removeFileIfPresent(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
    try? FileManager.default.removeItem(at: url)
}
