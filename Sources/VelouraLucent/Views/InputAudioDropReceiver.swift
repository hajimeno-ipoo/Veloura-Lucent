import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum InputAudioDropVisualState: Equatable {
    case inactive
    case validating
    case accepted
    case rejected
}

struct InputAudioDropDelegate: DropDelegate {
    let isEnabled: Bool
    @Binding var visualState: InputAudioDropVisualState
    @Binding var acceptedURLs: [URL]
    @Binding var validationRequestID: UUID
    let onDrop: ([URL]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        updateVisualState(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateVisualState(for: info)
        return DropProposal(operation: visualState == .accepted ? .copy : .cancel)
    }

    func dropExited(info: DropInfo) {
        resetDropState()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled,
              visualState == .accepted,
              info.hasItemsConforming(to: [.fileURL]),
              case .accepted = InputAudioDropSupport.validate(acceptedURLs) else {
            resetDropState()
            return false
        }

        let didDrop = onDrop(acceptedURLs)
        resetDropState()
        return didDrop
    }

    private func updateVisualState(for info: DropInfo) {
        guard isEnabled else {
            resetDropState()
            return
        }
        guard visualState == .inactive else { return }

        let requestID = UUID()
        validationRequestID = requestID
        acceptedURLs = []
        visualState = .validating

        loadFileURLs(from: info) { urls in
            guard validationRequestID == requestID else { return }
            updateAcceptedDropState(for: urls)
        }
    }

    private func updateAcceptedDropState(for urls: [URL]) {
        switch InputAudioDropSupport.validate(urls) {
        case let .accepted(url):
            acceptedURLs = [url]
            visualState = .accepted
        case .rejected:
            acceptedURLs = []
            visualState = urls.isEmpty ? .inactive : .rejected
        }
    }

    private func resetDropState() {
        validationRequestID = UUID()
        acceptedURLs = []
        visualState = .inactive
    }

    private func loadFileURLs(from info: DropInfo, completion: @escaping ([URL]) -> Void) {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let loadedURLs = LoadedFileURLs()

        for provider in providers {
            group.enter()
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, _, _ in
                if let url {
                    loadedURLs.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(loadedURLs.values())
        }
    }
}

private final class LoadedFileURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.withLock {
            storage.append(url)
        }
    }

    func values() -> [URL] {
        lock.withLock {
            storage
        }
    }
}
