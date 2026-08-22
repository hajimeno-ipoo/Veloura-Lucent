import Foundation
import Testing
@testable import VelouraLucent

private let fixtureRevision = "d4519e24ddc2dd4a11d56a193092433d852c3961"
private let fixtureRevisionHeader = "X-Repo-Commit"

private final class StemDownloadFixtureStore: @unchecked Sendable {
    typealias Handler = @Sendable (StemDownloadURLProtocol, URLRequest) -> Void

    private let lock = NSLock()
    private var handler: Handler?
    private var requests: [URLRequest] = []

    func reset(handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        requests.removeAll()
        lock.unlock()
    }

    func record(_ request: URLRequest) -> Handler? {
        lock.lock()
        requests.append(request)
        let handler = self.handler
        lock.unlock()
        return handler
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requests.compactMap(\.url)
    }
}

private final class StemDownloadURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = StemDownloadFixtureStore()

    private let stateLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme?.lowercased() == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.fixtures.record(request) else {
            client?.urlProtocol(
                self,
                didFailWithError: StemModelDownloadError.callbackRace(
                    "test fixture received a request without a handler"
                )
            )
            return
        }
        handler(self, request)
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }

    func complete(
        statusCode: Int = 200,
        headers: [String: String],
        data: Data
    ) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
              ),
              isActive else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    func beginWithoutCompleting(
        statusCode: Int = 200,
        headers: [String: String]
    ) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
              ),
              isActive else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func redirect(to url: URL, headers: [String: String]) {
        guard let sourceURL = request.url,
              let response = HTTPURLResponse(
                url: sourceURL,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: headers.merging(["Location": url.absoluteString]) { current, _ in current }
              ),
              isActive else {
            return
        }
        client?.urlProtocol(
            self,
            wasRedirectedTo: URLRequest(url: url),
            redirectResponse: response
        )
    }

    private var isActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !stopped
    }
}

private final class StemDownloadEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [StemModelDownloadEvent] = []

    func record(_ event: StemModelDownloadEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    var events: [StemModelDownloadEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private func makeDownloadClient() -> StemModelDownloadClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StemDownloadURLProtocol.self]
    return StemModelDownloadClient(configuration: configuration)
}

private func makePolicy(
    allowedHosts: [String] = ["models.test", "cdn.test"]
) -> StemModelDownloadPolicy {
    StemModelDownloadPolicy(
        requiresExplicitUserConfirmation: true,
        revisionResponseHeader: fixtureRevisionHeader,
        allowedRedirectHosts: allowedHosts
    )
}

private func makeAsset(
    url: URL = URL(string: "https://models.test/htdemucs_config.json")!,
    byteCount: Int64 = 8
) -> StemDownloadableModelAsset {
    StemDownloadableModelAsset(
        kind: .modelConfiguration,
        downloadURL: url.absoluteString,
        installationRelativePath: "htdemucs/htdemucs_config.json",
        byteCount: byteCount,
        sha256: String(repeating: "0", count: 64)
    )
}

private func withTemporaryStagingDirectory<T>(
    _ body: (URL) async throws -> T
) async throws -> T {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory.appending(
        path: "stem-download-client-tests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }
    return try await body(directory)
}

private func capturedDownloadError(
    _ operation: () async throws -> Void
) async -> StemModelDownloadError? {
    do {
        try await operation()
        return nil
    } catch let error as StemModelDownloadError {
        return error
    } catch {
        Issue.record("Unexpected error type: \(error)")
        return nil
    }
}

private func waitForRequestCount(
    _ expectedCount: Int,
    timeout: Duration = .seconds(2)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while StemDownloadURLProtocol.fixtures.requestCount < expectedCount {
        guard clock.now < deadline else {
            throw StemModelDownloadError.callbackRace("test request did not start before timeout")
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("Stem model download client", .serialized)
struct StemModelDownloadClientTests {
    @Test("Client construction performs no request and keeps an ephemeral private session")
    func constructionDoesNotStartNetworkTraffic() {
        StemDownloadURLProtocol.fixtures.reset { _, _ in }
        let client = makeDownloadClient()

        #expect(StemDownloadURLProtocol.fixtures.requestCount == 0)
        #expect(client.effectiveConfiguration.waitsForConnectivity)
        #expect(
            client.effectiveConfiguration.requestCachePolicy
                == .reloadIgnoringLocalAndRemoteCacheData
        )
        #expect(client.effectiveConfiguration.urlCache == nil)
        #expect(client.effectiveConfiguration.httpCookieStorage == nil)
        #expect(!client.effectiveConfiguration.httpShouldSetCookies)
    }

    @Test("Successful download uses the exact stable URL and moves the callback file to staging")
    func successfulDownloadMovesTemporaryFile() async throws {
        let payload = Data("fixture-model-data".utf8)
        let asset = makeAsset(byteCount: Int64(payload.count))
        StemDownloadURLProtocol.fixtures.reset { protocolInstance, _ in
            protocolInstance.complete(
                headers: [
                    fixtureRevisionHeader: fixtureRevision,
                    "ETag": "must-not-be-treated-as-sha256",
                    "Content-Length": "\(payload.count)",
                ],
                data: payload
            )
        }

        try await withTemporaryStagingDirectory { stagingDirectory in
            let client = makeDownloadClient()
            let events = StemDownloadEventRecorder()
            let result = try await client.download(
                downloadIdentifier: UUID(),
                asset: asset,
                modelRevision: fixtureRevision,
                policy: makePolicy(),
                stagingDirectoryURL: stagingDirectory,
                eventHandler: events.record
            )

            let expectedURL = stagingDirectory.appending(
                path: asset.installationRelativePath,
                directoryHint: .notDirectory
            )
            #expect(StemDownloadURLProtocol.fixtures.requestedURLs == [URL(string: asset.downloadURL)!])
            #expect(result.stagedURL == expectedURL)
            #expect(try Data(contentsOf: result.stagedURL) == payload)
            #expect(
                result.sourceRevisionEvidence
                    == StemModelSourceRevisionEvidence(
                        responseHeaderName: fixtureRevisionHeader,
                        revision: fixtureRevision
                    )
            )
            #expect(events.events.contains { event in
                if case .progress(let receivedBytes, _) = event {
                    return receivedBytes == Int64(payload.count)
                }
                return false
            })
        }
    }

    @Test("HTTP server errors are typed and do not produce a staged file")
    func httpErrorIsRejected() async throws {
        StemDownloadURLProtocol.fixtures.reset { protocolInstance, _ in
            protocolInstance.complete(
                statusCode: 503,
                headers: [fixtureRevisionHeader: fixtureRevision],
                data: Data("unavailable".utf8)
            )
        }

        try await withTemporaryStagingDirectory { stagingDirectory in
            let asset = makeAsset()
            let client = makeDownloadClient()
            let error = await capturedDownloadError {
                _ = try await client.download(
                    downloadIdentifier: UUID(),
                    asset: asset,
                    modelRevision: fixtureRevision,
                    policy: makePolicy(),
                    stagingDirectoryURL: stagingDirectory,
                    eventHandler: { _ in }
                )
            }

            #expect(error == .httpStatus(503))
            #expect(
                !FileManager.default.fileExists(
                    atPath: stagingDirectory.appending(
                        path: asset.installationRelativePath,
                        directoryHint: .notDirectory
                    ).path
                )
            )
        }
    }

    @Test("A direct response without revision evidence is rejected")
    func missingRevisionIsRejected() async throws {
        StemDownloadURLProtocol.fixtures.reset { protocolInstance, _ in
            protocolInstance.complete(headers: [:], data: Data("data".utf8))
        }

        try await withTemporaryStagingDirectory { stagingDirectory in
            let client = makeDownloadClient()
            let error = await capturedDownloadError {
                _ = try await client.download(
                    downloadIdentifier: UUID(),
                    asset: makeAsset(),
                    modelRevision: fixtureRevision,
                    policy: makePolicy(),
                    stagingDirectoryURL: stagingDirectory,
                    eventHandler: { _ in }
                )
            }
            #expect(error == .missingRevisionHeader(fixtureRevisionHeader))
        }
    }

    @Test("A direct response with a different revision is rejected")
    func mismatchedRevisionIsRejected() async throws {
        let actualRevision = String(repeating: "a", count: 40)
        StemDownloadURLProtocol.fixtures.reset { protocolInstance, _ in
            protocolInstance.complete(
                headers: [fixtureRevisionHeader: actualRevision],
                data: Data("data".utf8)
            )
        }

        try await withTemporaryStagingDirectory { stagingDirectory in
            let client = makeDownloadClient()
            let error = await capturedDownloadError {
                _ = try await client.download(
                    downloadIdentifier: UUID(),
                    asset: makeAsset(),
                    modelRevision: fixtureRevision,
                    policy: makePolicy(),
                    stagingDirectoryURL: stagingDirectory,
                    eventHandler: { _ in }
                )
            }
            #expect(
                error == .revisionMismatch(
                    expected: fixtureRevision,
                    actual: actualRevision
                )
            )
        }
    }

    @Test("Allowed redirect verifies revision on the first response only")
    func allowedRedirectUsesInitialRevisionEvidence() async throws {
        let redirectURL = URL(string: "https://cdn.test/signed-temporary-object")!
        let payload = Data("redirected-model".utf8)
        StemDownloadURLProtocol.fixtures.reset { protocolInstance, request in
            if request.url?.host == "models.test" {
                protocolInstance.redirect(
                    to: redirectURL,
                    headers: [fixtureRevisionHeader: fixtureRevision]
                )
            } else {
                // The time-limited object response intentionally has no revision header.
                protocolInstance.complete(headers: [:], data: payload)
            }
        }

        try await withTemporaryStagingDirectory { stagingDirectory in
            let client = makeDownloadClient()
            let result = try await client.download(
                downloadIdentifier: UUID(),
                asset: makeAsset(),
                modelRevision: fixtureRevision,
                policy: makePolicy(),
                stagingDirectoryURL: stagingDirectory,
                eventHandler: { _ in }
            )

            #expect(StemDownloadURLProtocol.fixtures.requestedURLs.count == 2)
            #expect(StemDownloadURLProtocol.fixtures.requestedURLs.last == redirectURL)
            #expect(try Data(contentsOf: result.stagedURL) == payload)
            #expect(result.sourceRevisionEvidence.revision == fixtureRevision)
        }
    }

    @Test("Redirect to a host outside the exact manifest allowlist is refused")
    func unexpectedRedirectHostIsRejected() async throws {
        let unexpectedURL = URL(string: "https://subdomain.cdn.test/signed-object")!
        StemDownloadURLProtocol.fixtures.reset { protocolInstance, _ in
            protocolInstance.redirect(
                to: unexpectedURL,
                headers: [fixtureRevisionHeader: fixtureRevision]
            )
        }

        try await withTemporaryStagingDirectory { stagingDirectory in
            let client = makeDownloadClient()
            let error = await capturedDownloadError {
                _ = try await client.download(
                    downloadIdentifier: UUID(),
                    asset: makeAsset(),
                    modelRevision: fixtureRevision,
                    policy: makePolicy(),
                    stagingDirectoryURL: stagingDirectory,
                    eventHandler: { _ in }
                )
            }

            #expect(error == .unexpectedRedirectHost("subdomain.cdn.test"))
            #expect(StemDownloadURLProtocol.fixtures.requestCount == 1)
        }
    }

    @Test("Explicit async cancellation resumes once with a typed cancellation error")
    func explicitCancellationIsTyped() async throws {
        StemDownloadURLProtocol.fixtures.reset { protocolInstance, _ in
            protocolInstance.beginWithoutCompleting(
                headers: [fixtureRevisionHeader: fixtureRevision]
            )
        }

        try await withTemporaryStagingDirectory { stagingDirectory in
            let client = makeDownloadClient()
            let identifier = UUID()
            let downloadTask = Task {
                try await client.download(
                    downloadIdentifier: identifier,
                    asset: makeAsset(),
                    modelRevision: fixtureRevision,
                    policy: makePolicy(),
                    stagingDirectoryURL: stagingDirectory,
                    eventHandler: { _ in }
                )
            }

            try await waitForRequestCount(1)
            try await client.cancel(downloadIdentifier: identifier)

            do {
                _ = try await downloadTask.value
                Issue.record("Cancelled download unexpectedly completed")
            } catch let error as StemModelDownloadError {
                #expect(error == .cancelled)
            } catch {
                Issue.record("Unexpected cancellation error type: \(error)")
            }
        }
    }

    @Test("Expected content length and manifest byte count are progress hints, not acceptance checks")
    func expectedContentLengthIsNotTrustedForCompletion() async throws {
        let payload = Data("more-than-one-byte".utf8)
        StemDownloadURLProtocol.fixtures.reset { protocolInstance, _ in
            protocolInstance.complete(
                headers: [
                    fixtureRevisionHeader: fixtureRevision,
                    "Content-Length": "1",
                ],
                data: payload
            )
        }

        try await withTemporaryStagingDirectory { stagingDirectory in
            let client = makeDownloadClient()
            let result = try await client.download(
                downloadIdentifier: UUID(),
                asset: makeAsset(byteCount: 999_999),
                modelRevision: fixtureRevision,
                policy: makePolicy(),
                stagingDirectoryURL: stagingDirectory,
                eventHandler: { _ in }
            )

            #expect(try Data(contentsOf: result.stagedURL) == payload)
        }
    }
}
