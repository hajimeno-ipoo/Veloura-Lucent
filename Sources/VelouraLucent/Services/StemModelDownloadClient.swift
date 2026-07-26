import Foundation

enum StemModelDownloadEvent: Equatable, Sendable {
    case waitingForConnectivity
    case progress(receivedBytes: Int64, expectedBytes: Int64?)
}

struct StemModelSourceRevisionEvidence: Equatable, Sendable {
    let responseHeaderName: String
    let revision: String
}

struct StemModelDownloadResult: Equatable, Sendable {
    let stagedURL: URL
    let sourceRevisionEvidence: StemModelSourceRevisionEvidence
}

enum StemModelDownloadError: Error, Equatable, LocalizedError, Sendable {
    case invalidSourceURL(String)
    case insecureSourceScheme(String?)
    case unexpectedSourceHost(String?)
    case invalidInstallationRelativePath(String)
    case invalidRevisionHeaderName
    case invalidExpectedRevision
    case httpStatus(Int)
    case insecureRedirectScheme(String?)
    case unexpectedRedirectHost(String?)
    case missingRevisionHeader(String)
    case revisionMismatch(expected: String, actual: String)
    case invalidContentLength(bytesWritten: Int64, totalBytesWritten: Int64, expectedBytes: Int64)
    case stagingFailure(path: String, reason: String)
    case duplicateDownloadIdentifier(UUID)
    case downloadNotFound(UUID)
    case callbackRace(String)
    case transport(code: Int, description: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL(let value):
            return "Invalid model download URL: \(value)"
        case .insecureSourceScheme(let scheme):
            return "Model downloads require HTTPS; source scheme was '\(scheme ?? "missing")'."
        case .unexpectedSourceHost(let host):
            return "Model download source host '\(host ?? "missing")' is not allowed by the signed manifest."
        case .invalidInstallationRelativePath(let path):
            return "Invalid model installation relative path: \(path)"
        case .invalidRevisionHeaderName:
            return "The signed manifest does not define a valid revision response header."
        case .invalidExpectedRevision:
            return "The signed manifest does not define a valid model revision."
        case .httpStatus(let statusCode):
            return "Model download failed with HTTP status \(statusCode)."
        case .insecureRedirectScheme(let scheme):
            return "Model download redirect requires HTTPS; redirect scheme was '\(scheme ?? "missing")'."
        case .unexpectedRedirectHost(let host):
            return "Model download redirect host '\(host ?? "missing")' is not allowed by the signed manifest."
        case .missingRevisionHeader(let headerName):
            return "Model source response is missing required revision header '\(headerName)'."
        case .revisionMismatch(let expected, let actual):
            return "Model source revision mismatch: expected '\(expected)', received '\(actual)'."
        case .invalidContentLength(let bytesWritten, let totalBytesWritten, let expectedBytes):
            return "Invalid model download progress lengths: chunk \(bytesWritten), total \(totalBytesWritten), expected \(expectedBytes)."
        case .stagingFailure(let path, let reason):
            return "Could not move the completed model download to staging at '\(path)': \(reason)"
        case .duplicateDownloadIdentifier(let identifier):
            return "A model download with identifier '\(identifier)' is already active."
        case .downloadNotFound(let identifier):
            return "No active model download was found for identifier '\(identifier)'."
        case .callbackRace(let reason):
            return "Model download callback order was invalid: \(reason)"
        case .transport(_, let description):
            return "Model download transport failed: \(description)"
        case .cancelled:
            return "Model download was cancelled."
        }
    }
}

protocol StemModelDownloading: Sendable {
    func download(
        downloadIdentifier: UUID,
        asset: StemDownloadableModelAsset,
        modelRevision: String,
        policy: StemModelDownloadPolicy,
        stagingDirectoryURL: URL,
        eventHandler: @escaping @Sendable (StemModelDownloadEvent) -> Void
    ) async throws -> StemModelDownloadResult

    func cancel(downloadIdentifier: UUID) async throws
}

final class StemModelDownloadClient: StemModelDownloading, @unchecked Sendable {
    private let sessionDelegate: StemModelDownloadSessionDelegate
    private let session: URLSession

    init(
        configuration: URLSessionConfiguration? = nil,
        fileManager: FileManager = .default
    ) {
        let resolvedConfiguration = Self.resolvedConfiguration(from: configuration)
        let sessionDelegate = StemModelDownloadSessionDelegate(fileManager: fileManager)
        self.sessionDelegate = sessionDelegate
        self.session = URLSession(
            configuration: resolvedConfiguration,
            delegate: sessionDelegate,
            delegateQueue: nil
        )
    }

    deinit {
        sessionDelegate.cancelAll()
        session.invalidateAndCancel()
    }

    func download(
        downloadIdentifier: UUID,
        asset: StemDownloadableModelAsset,
        modelRevision: String,
        policy: StemModelDownloadPolicy,
        stagingDirectoryURL: URL,
        eventHandler: @escaping @Sendable (StemModelDownloadEvent) -> Void
    ) async throws -> StemModelDownloadResult {
        let sourceURL = try Self.validatedSourceURL(
            asset.downloadURL,
            allowedHosts: policy.allowedRedirectHosts
        )
        let destinationURL = try Self.destinationURL(
            for: asset.installationRelativePath,
            stagingDirectoryURL: stagingDirectoryURL
        )
        let revisionHeaderName = policy.revisionResponseHeader
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revisionHeaderName.isEmpty else {
            throw StemModelDownloadError.invalidRevisionHeaderName
        }
        let expectedRevision = modelRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedRevision.isEmpty else {
            throw StemModelDownloadError.invalidExpectedRevision
        }

        let allowedHosts = Set(
            policy.allowedRedirectHosts.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        var request = URLRequest(
            url: sourceURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData
        )
        request.httpMethod = "GET"
        let task = session.downloadTask(with: request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let registrationError = sessionDelegate.register(
                    downloadIdentifier: downloadIdentifier,
                    task: task,
                    destinationURL: destinationURL,
                    expectedRevision: expectedRevision,
                    revisionHeaderName: revisionHeaderName,
                    allowedRedirectHosts: allowedHosts,
                    eventHandler: eventHandler,
                    continuation: continuation
                )
                if let registrationError {
                    task.cancel()
                    continuation.resume(throwing: registrationError)
                    return
                }

                if Task.isCancelled {
                    sessionDelegate.cancel(taskIdentifier: task.taskIdentifier)
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            self.sessionDelegate.cancel(taskIdentifier: task.taskIdentifier)
        }
    }

    func cancel(downloadIdentifier: UUID) async throws {
        try sessionDelegate.cancel(downloadIdentifier: downloadIdentifier)
    }

    /// Exposed internally so focused tests can verify that injected configurations retain
    /// production privacy and connectivity requirements.
    var effectiveConfiguration: URLSessionConfiguration {
        session.configuration
    }

    private static func resolvedConfiguration(
        from injectedConfiguration: URLSessionConfiguration?
    ) -> URLSessionConfiguration {
        let configuration: URLSessionConfiguration
        if let injectedConfiguration,
           let copied = injectedConfiguration.copy() as? URLSessionConfiguration {
            configuration = copied
        } else {
            configuration = .ephemeral
        }
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return configuration
    }

    private static func validatedSourceURL(
        _ value: String,
        allowedHosts: [String]
    ) throws -> URL {
        guard let url = URL(string: value), url.absoluteString == value else {
            throw StemModelDownloadError.invalidSourceURL(value)
        }
        guard url.scheme?.lowercased() == "https" else {
            throw StemModelDownloadError.insecureSourceScheme(url.scheme)
        }
        let normalizedAllowedHosts = Set(
            allowedHosts.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        guard let host = url.host?.lowercased(), normalizedAllowedHosts.contains(host) else {
            throw StemModelDownloadError.unexpectedSourceHost(url.host)
        }
        return url
    }

    private static func destinationURL(
        for relativePath: String,
        stagingDirectoryURL: URL
    ) throws -> URL {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !relativePath.hasPrefix("/"),
              !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw StemModelDownloadError.invalidInstallationRelativePath(relativePath)
        }
        return stagingDirectoryURL.appending(
            path: relativePath,
            directoryHint: .notDirectory
        )
    }
}

private final class StemModelDownloadSessionDelegate: NSObject, @unchecked Sendable {
    private final class Operation: @unchecked Sendable {
        let downloadIdentifier: UUID
        let task: URLSessionDownloadTask
        let destinationURL: URL
        let expectedRevision: String
        let revisionHeaderName: String
        let allowedRedirectHosts: Set<String>
        let eventHandler: @Sendable (StemModelDownloadEvent) -> Void
        let continuation: CheckedContinuation<StemModelDownloadResult, Error>

        var revisionVerified = false
        var didFinishDownloading = false
        var stagedURL: URL?

        init(
            downloadIdentifier: UUID,
            task: URLSessionDownloadTask,
            destinationURL: URL,
            expectedRevision: String,
            revisionHeaderName: String,
            allowedRedirectHosts: Set<String>,
            eventHandler: @escaping @Sendable (StemModelDownloadEvent) -> Void,
            continuation: CheckedContinuation<StemModelDownloadResult, Error>
        ) {
            self.downloadIdentifier = downloadIdentifier
            self.task = task
            self.destinationURL = destinationURL
            self.expectedRevision = expectedRevision
            self.revisionHeaderName = revisionHeaderName
            self.allowedRedirectHosts = allowedRedirectHosts
            self.eventHandler = eventHandler
            self.continuation = continuation
        }
    }

    private struct CompletionAction {
        let operation: Operation
        let result: Result<StemModelDownloadResult, Error>
        let cancelTask: Bool
        let removeStagedFile: Bool
    }

    private let lock = NSLock()
    private let fileManager: FileManager
    private var operationsByTaskIdentifier: [Int: Operation] = [:]
    private var taskIdentifierByDownloadIdentifier: [UUID: Int] = [:]

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func register(
        downloadIdentifier: UUID,
        task: URLSessionDownloadTask,
        destinationURL: URL,
        expectedRevision: String,
        revisionHeaderName: String,
        allowedRedirectHosts: Set<String>,
        eventHandler: @escaping @Sendable (StemModelDownloadEvent) -> Void,
        continuation: CheckedContinuation<StemModelDownloadResult, Error>
    ) -> StemModelDownloadError? {
        lock.lock()
        defer { lock.unlock() }
        guard taskIdentifierByDownloadIdentifier[downloadIdentifier] == nil else {
            return .duplicateDownloadIdentifier(downloadIdentifier)
        }
        let operation = Operation(
            downloadIdentifier: downloadIdentifier,
            task: task,
            destinationURL: destinationURL,
            expectedRevision: expectedRevision,
            revisionHeaderName: revisionHeaderName,
            allowedRedirectHosts: allowedRedirectHosts,
            eventHandler: eventHandler,
            continuation: continuation
        )
        operationsByTaskIdentifier[task.taskIdentifier] = operation
        taskIdentifierByDownloadIdentifier[downloadIdentifier] = task.taskIdentifier
        return nil
    }

    func cancel(downloadIdentifier: UUID) throws {
        lock.lock()
        guard let taskIdentifier = taskIdentifierByDownloadIdentifier[downloadIdentifier],
              let operation = operationsByTaskIdentifier[taskIdentifier] else {
            lock.unlock()
            throw StemModelDownloadError.downloadNotFound(downloadIdentifier)
        }
        let action = detachLocked(
            operation,
            result: .failure(StemModelDownloadError.cancelled),
            cancelTask: true,
            removeStagedFile: true
        )
        lock.unlock()
        perform(action)
    }

    func cancel(taskIdentifier: Int) {
        lock.lock()
        guard let operation = operationsByTaskIdentifier[taskIdentifier] else {
            lock.unlock()
            return
        }
        let action = detachLocked(
            operation,
            result: .failure(StemModelDownloadError.cancelled),
            cancelTask: true,
            removeStagedFile: true
        )
        lock.unlock()
        perform(action)
    }

    func cancelAll() {
        lock.lock()
        let operations = Array(operationsByTaskIdentifier.values)
        let actions = operations.map {
            detachLocked(
                $0,
                result: .failure(StemModelDownloadError.cancelled),
                cancelTask: true,
                removeStagedFile: true
            )
        }
        lock.unlock()
        for action in actions {
            perform(action)
        }
    }

    private func detachLocked(
        _ operation: Operation,
        result: Result<StemModelDownloadResult, Error>,
        cancelTask: Bool,
        removeStagedFile: Bool
    ) -> CompletionAction {
        operationsByTaskIdentifier.removeValue(forKey: operation.task.taskIdentifier)
        taskIdentifierByDownloadIdentifier.removeValue(forKey: operation.downloadIdentifier)
        return CompletionAction(
            operation: operation,
            result: result,
            cancelTask: cancelTask,
            removeStagedFile: removeStagedFile
        )
    }

    private func perform(_ action: CompletionAction) {
        if action.cancelTask {
            action.operation.task.cancel()
        }
        if action.removeStagedFile, let stagedURL = action.operation.stagedURL {
            try? fileManager.removeItem(at: stagedURL)
        }
        action.operation.continuation.resume(with: action.result)
    }

    private func revisionError(
        response: HTTPURLResponse,
        operation: Operation
    ) -> StemModelDownloadError? {
        guard !operation.revisionVerified else { return nil }
        guard let received = response.value(
            forHTTPHeaderField: operation.revisionHeaderName
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !received.isEmpty else {
            return .missingRevisionHeader(operation.revisionHeaderName)
        }
        guard received == operation.expectedRevision else {
            return .revisionMismatch(
                expected: operation.expectedRevision,
                actual: received
            )
        }
        operation.revisionVerified = true
        return nil
    }
}

extension StemModelDownloadSessionDelegate: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        guard let operation = operationsByTaskIdentifier[downloadTask.taskIdentifier] else {
            lock.unlock()
            return
        }
        guard bytesWritten >= 0,
              totalBytesWritten >= 0,
              totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown
                || totalBytesExpectedToWrite >= 0 else {
            let action = detachLocked(
                operation,
                result: .failure(
                    StemModelDownloadError.invalidContentLength(
                        bytesWritten: bytesWritten,
                        totalBytesWritten: totalBytesWritten,
                        expectedBytes: totalBytesExpectedToWrite
                    )
                ),
                cancelTask: true,
                removeStagedFile: true
            )
            lock.unlock()
            perform(action)
            return
        }
        let handler = operation.eventHandler
        let expectedBytes = totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown
            ? nil
            : totalBytesExpectedToWrite
        lock.unlock()
        handler(
            .progress(
                receivedBytes: totalBytesWritten,
                expectedBytes: expectedBytes
            )
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        guard let operation = operationsByTaskIdentifier[downloadTask.taskIdentifier] else {
            lock.unlock()
            return
        }

        var failure: StemModelDownloadError?
        if operation.didFinishDownloading {
            failure = .callbackRace("didFinishDownloadingTo was delivered more than once")
        } else if let response = downloadTask.response as? HTTPURLResponse {
            if !(200...299).contains(response.statusCode) {
                failure = .httpStatus(response.statusCode)
            } else if let error = revisionError(response: response, operation: operation) {
                failure = error
            }
        } else {
            failure = .callbackRace("download completed without an HTTP response")
        }

        operation.didFinishDownloading = true
        if failure == nil {
            do {
                let parentDirectory = operation.destinationURL.deletingLastPathComponent()
                try fileManager.createDirectory(
                    at: parentDirectory,
                    withIntermediateDirectories: true
                )
                guard !fileManager.fileExists(atPath: operation.destinationURL.path) else {
                    throw StemModelDownloadError.stagingFailure(
                        path: operation.destinationURL.path,
                        reason: "destination already exists"
                    )
                }
                try fileManager.moveItem(at: location, to: operation.destinationURL)
                operation.stagedURL = operation.destinationURL
            } catch let error as StemModelDownloadError {
                failure = error
            } catch {
                failure = .stagingFailure(
                    path: operation.destinationURL.path,
                    reason: error.localizedDescription
                )
            }
        }

        if let failure {
            let action = detachLocked(
                operation,
                result: .failure(failure),
                cancelTask: true,
                removeStagedFile: true
            )
            lock.unlock()
            perform(action)
        } else {
            lock.unlock()
        }
    }
}

extension StemModelDownloadSessionDelegate {
    func urlSession(
        _ session: URLSession,
        taskIsWaitingForConnectivity task: URLSessionTask
    ) {
        lock.lock()
        let handler = operationsByTaskIdentifier[task.taskIdentifier]?.eventHandler
        lock.unlock()
        handler?(.waitingForConnectivity)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        lock.lock()
        guard let operation = operationsByTaskIdentifier[task.taskIdentifier] else {
            lock.unlock()
            completionHandler(nil)
            return
        }

        let redirectError: StemModelDownloadError?
        if request.url?.scheme?.lowercased() != "https" {
            redirectError = .insecureRedirectScheme(request.url?.scheme)
        } else if let host = request.url?.host?.lowercased(),
                  operation.allowedRedirectHosts.contains(host) {
            redirectError = revisionError(response: response, operation: operation)
        } else {
            redirectError = .unexpectedRedirectHost(request.url?.host)
        }

        if let redirectError {
            let action = detachLocked(
                operation,
                result: .failure(redirectError),
                cancelTask: true,
                removeStagedFile: true
            )
            lock.unlock()
            completionHandler(nil)
            perform(action)
        } else {
            lock.unlock()
            completionHandler(request)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        guard let operation = operationsByTaskIdentifier[task.taskIdentifier] else {
            lock.unlock()
            return
        }

        let action: CompletionAction
        if let error {
            let nsError = error as NSError
            let typedError: StemModelDownloadError
            if nsError.domain == NSURLErrorDomain,
               nsError.code == URLError.cancelled.rawValue {
                typedError = .cancelled
            } else {
                typedError = .transport(
                    code: nsError.code,
                    description: error.localizedDescription
                )
            }
            action = detachLocked(
                operation,
                result: .failure(typedError),
                cancelTask: false,
                removeStagedFile: true
            )
        } else if let stagedURL = operation.stagedURL,
                  operation.didFinishDownloading,
                  operation.revisionVerified {
            let result = StemModelDownloadResult(
                stagedURL: stagedURL,
                sourceRevisionEvidence: StemModelSourceRevisionEvidence(
                    responseHeaderName: operation.revisionHeaderName,
                    revision: operation.expectedRevision
                )
            )
            action = detachLocked(
                operation,
                result: .success(result),
                cancelTask: false,
                removeStagedFile: false
            )
        } else {
            action = detachLocked(
                operation,
                result: .failure(
                    StemModelDownloadError.callbackRace(
                        "task completed before a verified file was moved to staging"
                    )
                ),
                cancelTask: false,
                removeStagedFile: true
            )
        }
        lock.unlock()
        perform(action)
    }
}
