import Foundation

enum DisplayAnalysisSupport {
    static func runWorker<T: Sendable>(
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let result = try await work()
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func measure<T: Sendable>(
        _ label: String,
        logHandler: (@Sendable (String) -> Void)?,
        work: @Sendable () async throws -> T
    ) async throws -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let result = try await work()
            logHandler?("表示解析/計測: \(label): \(formatProcessingDuration(durationSeconds(since: start)))")
            return result
        } catch {
            logHandler?("表示解析/計測: \(label): \(formatProcessingDuration(durationSeconds(since: start)))")
            throw error
        }
    }

    static func measureOptional<T: Sendable>(
        _ label: String,
        isEnabled: Bool,
        logHandler: (@Sendable (String) -> Void)?,
        work: @Sendable () async throws -> T
    ) async throws -> T? {
        guard isEnabled else { return nil }
        return try await measure(label, logHandler: logHandler, work: work)
    }

    private static func durationSeconds(since start: UInt64) -> Double {
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }
}
