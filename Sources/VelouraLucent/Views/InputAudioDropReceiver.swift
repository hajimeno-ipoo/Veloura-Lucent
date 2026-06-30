import AppKit
import SwiftUI

enum InputAudioDropVisualState: Equatable {
    case inactive
    case accepted
    case rejected
}

struct InputAudioDropReceiver: NSViewRepresentable {
    let isEnabled: Bool
    @Binding var visualState: InputAudioDropVisualState
    let onDrop: ([URL]) -> Bool

    func makeNSView(context: Context) -> DropReceiverView {
        let view = DropReceiverView()
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: DropReceiverView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onVisualStateChange = { state in
            visualState = state
        }
        nsView.onDrop = onDrop

        if !isEnabled, visualState != .inactive {
            visualState = .inactive
        }
    }
}

final class DropReceiverView: NSView {
    var isEnabled = true
    var onVisualStateChange: ((InputAudioDropVisualState) -> Void)?
    var onDrop: (([URL]) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateVisualState(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateVisualState(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onVisualStateChange?(.inactive)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onVisualStateChange?(.inactive)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEnabled else { return false }
        return isAcceptedAudioDrop(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEnabled,
              case let .accepted(url) = InputAudioDropSupport.validate(fileURLs(from: sender)) else {
            onVisualStateChange?(.inactive)
            return false
        }

        let didDrop = onDrop?([url]) ?? false
        onVisualStateChange?(.inactive)
        return didDrop
    }

    private func updateVisualState(for sender: NSDraggingInfo) -> NSDragOperation {
        guard isEnabled else {
            onVisualStateChange?(.inactive)
            return []
        }

        let urls = fileURLs(from: sender)
        switch InputAudioDropSupport.validate(urls) {
        case .accepted:
            onVisualStateChange?(.accepted)
            return .copy
        case .rejected:
            onVisualStateChange?(urls.isEmpty ? .inactive : .rejected)
            return []
        }
    }

    private func isAcceptedAudioDrop(_ sender: NSDraggingInfo) -> Bool {
        if case .accepted = InputAudioDropSupport.validate(fileURLs(from: sender)) {
            return true
        }
        return false
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        InputAudioDropSupport.fileURLs(from: sender.draggingPasteboard)
    }
}
