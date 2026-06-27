import AppKit
import SwiftUI

struct WindowScrollbarAppearanceConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.install(on: nsView)
    }

    @MainActor
    final class Coordinator: NSObject {
        private static let retryDelays: [TimeInterval] = [0, 0.05, 0.15, 0.35, 0.75]

        private weak var hostView: NSView?
        private weak var observedWindow: NSWindow?
        private var isConfigurationScheduled = false

        deinit {
            NotificationCenter.default.removeObserver(self)
            NSObject.cancelPreviousPerformRequests(withTarget: self)
        }

        func install(on view: NSView) {
            hostView = view
            scheduleConfiguration(from: view)
        }

        private func scheduleConfiguration(from view: NSView) {
            guard !isConfigurationScheduled else { return }
            isConfigurationScheduled = true

            for (index, delay) in Self.retryDelays.enumerated() {
                perform(
                    #selector(runScheduledConfiguration(_:)),
                    with: NSNumber(value: index),
                    afterDelay: delay
                )
            }
        }

        @objc
        private func runScheduledConfiguration(_ sender: NSNumber) {
            guard let hostView else {
                isConfigurationScheduled = false
                return
            }
            observeWindowIfNeeded(from: hostView)
            configureScrollbars(from: hostView)
            if sender.intValue == Self.retryDelays.count - 1 {
                isConfigurationScheduled = false
            }
        }

        private func observeWindowIfNeeded(from view: NSView) {
            guard let window = view.window, observedWindow !== window else { return }

            NotificationCenter.default.removeObserver(self)
            observedWindow = window

            let notificationCenter = NotificationCenter.default
            for name in [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResizeNotification,
                NSWindow.didUpdateNotification
            ] {
                notificationCenter.addObserver(
                    self,
                    selector: #selector(windowNeedsScrollbarConfiguration(_:)),
                    name: name,
                    object: window,
                )
            }
        }

        @objc
        private func windowNeedsScrollbarConfiguration(_ notification: Notification) {
            guard let hostView else { return }
            scheduleConfiguration(from: hostView)
        }

        private func configureScrollbars(from view: NSView) {
            guard let contentView = view.window?.contentView else { return }

            for scrollView in contentView.descendants(ofType: NSScrollView.self) {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.verticalScroller?.knobStyle = .light
                scrollView.horizontalScroller?.knobStyle = .light
                scrollView.verticalScroller?.controlSize = .small
                scrollView.horizontalScroller?.controlSize = .small
            }
        }
    }
}

private extension NSView {
    func descendants<T: NSView>(ofType type: T.Type) -> [T] {
        subviews.flatMap { subview -> [T] in
            var matches = subview.descendants(ofType: type)
            if let match = subview as? T {
                matches.insert(match, at: 0)
            }
            return matches
        }
    }
}
