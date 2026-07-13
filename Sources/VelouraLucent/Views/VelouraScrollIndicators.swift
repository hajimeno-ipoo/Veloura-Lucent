import AppKit
import SwiftUI

private final class VelouraTransientOverlayScroller: NSScroller {
    private static let subduedAlpha: CGFloat = 0.55

    private var isScrollActive = false

    override class var isCompatibleWithOverlayScrollers: Bool {
        self == VelouraTransientOverlayScroller.self
    }

    func setScrollActive(_ isActive: Bool) {
        alphaValue = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ? 1
            : Self.subduedAlpha
        guard isScrollActive != isActive else { return }
        isScrollActive = isActive
        needsDisplay = true
    }

    override func drawKnob() {
        guard isScrollActive else { return }
        super.drawKnob()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        guard isScrollActive else { return }
        super.drawKnobSlot(in: slotRect, highlight: flag)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isScrollActive else { return nil }
        return super.hitTest(point)
    }
}

private struct VelouraScrollIndicatorConfigurator: NSViewRepresentable {
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
        private static let retryDelays: [TimeInterval] = [0, 0.05, 0.15, 0.35]
        private static let hideDelay: TimeInterval = 0.55

        private weak var hostView: NSView?
        private weak var observedScrollView: NSScrollView?
        private var isConfigurationScheduled = false

        deinit {
            NotificationCenter.default.removeObserver(self)
            NSObject.cancelPreviousPerformRequests(withTarget: self)
        }

        func install(on view: NSView) {
            hostView = view
            scheduleConfiguration()
        }

        private func scheduleConfiguration() {
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
            if let scrollView = hostView?.enclosingScrollView {
                observeScrolling(in: scrollView)
                configure(scrollView)
                hideScrollers(in: scrollView)
            }

            if sender.intValue == Self.retryDelays.count - 1 {
                isConfigurationScheduled = false
            }
        }

        private func observeScrolling(in scrollView: NSScrollView) {
            guard observedScrollView !== scrollView else { return }

            NotificationCenter.default.removeObserver(self)
            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollPositionDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        private func configure(_ scrollView: NSScrollView) {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = false

            if !(scrollView.verticalScroller is VelouraTransientOverlayScroller) {
                let scroller = VelouraTransientOverlayScroller(frame: .zero)
                scroller.controlSize = .small
                scrollView.verticalScroller = scroller
            }
            scrollView.hasVerticalScroller = true
        }

        @objc
        private func scrollPositionDidChange(_ notification: Notification) {
            guard let scrollView = observedScrollView else { return }

            configure(scrollView)
            setScrollActive(true, in: scrollView)
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(hideObservedScrollers),
                object: nil
            )
            perform(#selector(hideObservedScrollers), with: nil, afterDelay: Self.hideDelay)
        }

        @objc
        private func hideObservedScrollers() {
            guard let scrollView = observedScrollView else { return }
            hideScrollers(in: scrollView)
        }

        private func hideScrollers(in scrollView: NSScrollView) {
            setScrollActive(false, in: scrollView)
        }

        private func setScrollActive(_ isActive: Bool, in scrollView: NSScrollView) {
            (scrollView.verticalScroller as? VelouraTransientOverlayScroller)?
                .setScrollActive(isActive)
        }
    }
}

extension View {
    func velouraTransientOverlayScrollIndicators() -> some View {
        background {
            VelouraScrollIndicatorConfigurator()
                .frame(width: 0, height: 0)
        }
    }
}
