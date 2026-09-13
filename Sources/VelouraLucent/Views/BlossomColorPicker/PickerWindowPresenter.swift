#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit
    import SwiftUI

    /// Manages the NSWindow lifecycle for the expanded color picker.
    /// Shows a borderless, floating window at the swatch's screen position.
    @MainActor
    final class PickerWindowPresenter {
        private var window: NSWindow?
        private var localEventMonitor: Any?
        private var appDeactivateObserver: NSObjectProtocol?
        private var model: BlossomColorPickerModel?
        private var colorSampler: NSColorSampler?
        private var isSamplingColor = false

        func show(
            at screenPoint: CGPoint,
            model: BlossomColorPickerModel,
            layout: PetalLayout,
            recentColors: [Color] = [],
            parentWindow: NSWindow? = nil,
            style: BlossomStyle = .default
        ) {
            dismissImmediately()
            self.model = model

            let contentSize = ExpandedBlossomView.totalSize(layout: layout, style: style)
            let flowerSize = ExpandedBlossomView.flowerSize(layout: layout, style: style)
            let contentView = ExpandedBlossomView(
                model: model,
                layout: layout,
                recentColors: recentColors,
                onSampleColor: { [weak self] in
                    self?.sampleColor()
                }
            )
                .blossomStyle(style)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = parentWindow?.level ?? .floating
            window.hasShadow = false
            window.isReleasedWhenClosed = false

            let origin = NSPoint(
                x: screenPoint.x - contentSize.width / 2,
                y: screenPoint.y - contentSize.height + flowerSize / 2
            )
            window.setFrameOrigin(origin)

            let hostingView = NSHostingView(rootView: contentView)
            window.contentView = hostingView
            if let parentWindow {
                parentWindow.addChildWindow(window, ordered: .above)
            } else {
                window.orderFront(nil)
            }

            self.window = window
            setupLocalEventMonitor()
            setupAppDeactivateObserver()

            Task { @MainActor in
                model.expand()
            }
        }

        func dismiss() {
            removeObservers()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if let window {
                    window.parent?.removeChildWindow(window)
                    window.close()
                }
                window = nil
                model = nil
            }
        }

        private func dismissImmediately() {
            removeObservers()
            if let window {
                window.parent?.removeChildWindow(window)
                window.close()
            }
            window = nil
            model = nil
            colorSampler = nil
            isSamplingColor = false
        }

        private func removeObservers() {
            if let monitor = localEventMonitor {
                NSEvent.removeMonitor(monitor)
                localEventMonitor = nil
            }
            if let observer = appDeactivateObserver {
                NotificationCenter.default.removeObserver(observer)
                appDeactivateObserver = nil
            }
        }

        private func setupLocalEventMonitor() {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]
            ) { [weak self] event in
                self?.handleLocalEvent(event) ?? event
            }
        }

        func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
            guard let window else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                model?.collapse()
                return nil
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown,
               !window.frame.contains(NSEvent.mouseLocation) {
                model?.collapse()
            }
            return event
        }

        private func setupAppDeactivateObserver() {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard self.window != nil else { return }

                self.appDeactivateObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, !self.isSamplingColor else { return }
                        self.model?.collapse()
                    }
                }
            }
        }

        private func sampleColor() {
            guard colorSampler == nil else { return }

            let sampler = NSColorSampler()
            colorSampler = sampler
            isSamplingColor = true
            Task { @MainActor [weak self] in
                let color = await sampler.sample()
                guard let self else { return }
                self.colorSampler = nil
                self.isSamplingColor = false
                guard let color else { return }
                self.model?.selectSampledColor(Color(color))
            }
        }
    }
#endif
