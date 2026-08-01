import AppKit
import SwiftUI

struct ContentView: View {
    @State private var processingActions = ProcessingActions(notificationReporter: NotificationService.shared)
    private let shutsDownOnDisappear: Bool
    @State private var inputAudioDropVisualState: InputAudioDropVisualState = .inactive

    @MainActor
    init(
        processingActions: ProcessingActions,
        shutsDownOnDisappear: Bool
    ) {
        _processingActions = State(initialValue: processingActions)
        self.shutsDownOnDisappear = shutsDownOnDisappear
    }

    private var job: ProcessingJob {
        processingActions.job
    }

    private var preview: AudioPreviewController {
        processingActions.preview
    }

    var body: some View {
        @Bindable var actions = processingActions

        mainContent
            .alert(item: $actions.presentedError) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.alertMessage),
                    dismissButton: .default(Text("閉じる"))
                )
            }
            .onChange(of: job.selectedMasteringProfile) { _, newValue in
                job.applyMasteringProfile(newValue)
            }
            .onDisappear {
                if shutsDownOnDisappear {
                    processingActions.shutdown()
                }
            }
    }

    private var mainContent: some View {
        ZStack {
            VelouraMainWorkspaceView(
                job: job,
                preview: preview
            )

            InputAudioDropReceiver(
                isEnabled: processingActions.canAcceptInputAudioDrop,
                visualState: $inputAudioDropVisualState,
                onDrop: processingActions.acceptDroppedInputAudio
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)

            switch inputAudioDropVisualState {
            case .inactive:
                EmptyView()
            case .accepted:
                InputAudioDropOverlay(kind: .accepted)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            case .rejected:
                InputAudioDropOverlay(kind: .rejected)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

}

extension View {
    @ViewBuilder
    func velouraWindowBackground(state: WindowAppearanceState) -> some View {
        if state.usesOpaqueBackground {
            self
        } else {
            containerBackground(
                state.effectiveBlurLevel.material
                    .materialActiveAppearance(.active)
                    .opacity(state.materialAmount),
                for: .window
            )
        }
    }

}

private extension WindowBackgroundBlurLevel {
    var material: Material {
        switch self {
        case .ultraThin: .ultraThin
        case .thin: .thin
        case .regular: .regular
        case .thick: .thick
        case .ultraThick: .ultraThick
        }
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    let minSize: NSSize
    let appearanceState: WindowAppearanceState
    let hidesTitle: Bool
    @Binding var isFullScreen: Bool

    init(
        minSize: NSSize,
        appearanceState: WindowAppearanceState,
        hidesTitle: Bool = true,
        isFullScreen: Binding<Bool>
    ) {
        self.minSize = minSize
        self.appearanceState = appearanceState
        self.hidesTitle = hidesTitle
        _isFullScreen = isFullScreen
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(isFullScreen: $isFullScreen, appearanceState: appearanceState)
        updateWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isFullScreen: $isFullScreen, appearanceState: appearanceState)
        updateWindow(for: nsView, context: context)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.stopObservingWindow()
        }
    }

    private func updateWindow(for view: NSView, context: Context) {
        Task { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.observe(window)
            configure(window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow, coordinator: Coordinator) {
        if window.minSize.width != minSize.width || window.minSize.height != minSize.height {
            window.minSize = minSize
        }
        coordinator.applyChrome(to: window)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = hidesTitle ? .hidden : .visible
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var observedWindow: NSWindow?
        private weak var previousWindowDelegate: NSWindowDelegate?
        private var isFullScreen: Binding<Bool>?
        private var appearanceState: WindowAppearanceState?
        private var restoresFullSizeContentView = false

        func update(isFullScreen: Binding<Bool>, appearanceState: WindowAppearanceState) {
            self.isFullScreen = isFullScreen
            self.appearanceState = appearanceState
        }

        func observe(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObservingWindow()
            observedWindow = window
            previousWindowDelegate = window.delegate
            window.delegate = self
            restoresFullSizeContentView = window.styleMask.contains(.fullSizeContentView)
        }

        func stopObservingWindow() {
            if let observedWindow, observedWindow.delegate === self {
                observedWindow.delegate = previousWindowDelegate
            }
            observedWindow = nil
            previousWindowDelegate = nil
        }

        func applyChrome(to window: NSWindow) {
            applyChrome(to: window, isFullScreen: window.styleMask.contains(.fullScreen))
        }

        private func applyChrome(to window: NSWindow, isFullScreen: Bool) {
            let appearanceState = appearanceState?.updatingFullScreen(isFullScreen)
            if isFullScreen {
                prepareWindowForFullScreenTransition(window)
            } else {
                if restoresFullSizeContentView {
                    window.styleMask.insert(.fullSizeContentView)
                }
                if appearanceState?.usesOpaqueBackground == true {
                    applyOpaqueBackground(to: window)
                } else {
                    window.isOpaque = false
                    window.backgroundColor = .clear
                }
            }
            if self.isFullScreen?.wrappedValue != isFullScreen {
                self.isFullScreen?.wrappedValue = isFullScreen
            }
        }

        private func prepareWindowForFullScreenTransition(_ window: NSWindow) {
            window.styleMask.remove(.fullSizeContentView)
            applyOpaqueBackground(to: window)
            window.contentView?.needsDisplay = true
            window.displayIfNeeded()
        }

        private func applyOpaqueBackground(to window: NSWindow) {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
        }

        func window(
            _ window: NSWindow,
            willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions
        ) -> NSApplication.PresentationOptions {
            prepareWindowForFullScreenTransition(window)
            return proposedOptions
        }

        func windowWillEnterFullScreen(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            applyChrome(to: window, isFullScreen: true)
        }

        func windowDidEnterFullScreen(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            applyChrome(to: window, isFullScreen: true)
        }

        func windowDidFailToEnterFullScreen(_ window: NSWindow) {
            applyChrome(to: window, isFullScreen: false)
        }

        func windowDidExitFullScreen(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            applyChrome(to: window, isFullScreen: false)
        }

        func windowDidFailToExitFullScreen(_ window: NSWindow) {
            applyChrome(to: window, isFullScreen: true)
        }

        func windowWillClose(_ notification: Notification) {
            stopObservingWindow()
        }
    }
}

struct TitlebarSidebarToggleConfigurator: NSViewRepresentable {
    @Binding var visibility: NavigationSplitViewVisibility
    let isAvailable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(
            visibility: $visibility,
            isAvailable: isAvailable
        )
        updateWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            visibility: $visibility,
            isAvailable: isAvailable
        )
        updateWindow(for: nsView, context: context)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.stopObservingToolbar()
        }
    }

    private func updateWindow(for view: NSView, context: Context) {
        Task { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.observeToolbar(in: window)
            context.coordinator.installIfNeeded(in: window)
            context.coordinator.removeDefaultSidebarToggle(from: window)
            await Task.yield()
            context.coordinator.removeDefaultSidebarToggle(from: window)
        }
    }

    @MainActor
    final class Coordinator {
        private static let accessoryIdentifier = NSUserInterfaceItemIdentifier("VelouraLucentSidebarToggleAccessory")
        private static let swiftUISidebarToggleIdentifier = NSToolbarItem.Identifier(
            "com.apple.SwiftUI.navigationSplitView.toggleSidebar"
        )

        private weak var observedToolbar: NSToolbar?
        private var toolbarWillAddObserver: NSObjectProtocol?
        private var accessoryController: NSTitlebarAccessoryViewController?
        private var hostingView: NSHostingView<TitlebarSidebarToggleButton>?
        private var visibility: Binding<NavigationSplitViewVisibility>?
        private var isAvailable = true

        func update(
            visibility: Binding<NavigationSplitViewVisibility>,
            isAvailable: Bool
        ) {
            self.visibility = visibility
            self.isAvailable = isAvailable
            hostingView?.rootView = TitlebarSidebarToggleButton(
                visibility: visibility,
                isAvailable: isAvailable
            )
        }

        func observeToolbar(in window: NSWindow) {
            guard let toolbar = window.toolbar, toolbar !== observedToolbar else { return }

            if let toolbarWillAddObserver {
                NotificationCenter.default.removeObserver(toolbarWillAddObserver)
            }

            observedToolbar = toolbar
            toolbarWillAddObserver = NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification,
                object: toolbar,
                queue: .main
            ) { [weak self, weak toolbar] _ in
                Task { @MainActor in
                    await Task.yield()
                    guard let toolbar else { return }
                    self?.removeDefaultSidebarToggle(from: toolbar)
                }
            }
        }

        func installIfNeeded(in window: NSWindow) {
            guard accessoryController == nil, let visibility else { return }

            removeStaleAccessory(from: window)

            let button = TitlebarSidebarToggleButton(
                visibility: visibility,
                isAvailable: isAvailable
            )
            let hostingView = NSHostingView(rootView: button)
            hostingView.frame = NSRect(x: 0, y: 0, width: 36, height: 30)
            hostingView.identifier = Self.accessoryIdentifier

            let controller = NSTitlebarAccessoryViewController()
            controller.view = hostingView
            controller.layoutAttribute = .left

            window.addTitlebarAccessoryViewController(controller)

            self.hostingView = hostingView
            self.accessoryController = controller
        }

        func removeDefaultSidebarToggle(from window: NSWindow) {
            guard let toolbar = window.toolbar else { return }
            removeDefaultSidebarToggle(from: toolbar)
        }

        func removeDefaultSidebarToggle(from toolbar: NSToolbar) {
            let indexes = toolbar.items.enumerated().compactMap { index, item in
                let isSidebarToggle = item.itemIdentifier == .toggleSidebar
                    || item.itemIdentifier == Self.swiftUISidebarToggleIdentifier
                return isSidebarToggle ? index : nil
            }

            for index in indexes.reversed() {
                toolbar.removeItem(at: index)
            }
        }

        func stopObservingToolbar() {
            if let toolbarWillAddObserver {
                NotificationCenter.default.removeObserver(toolbarWillAddObserver)
                self.toolbarWillAddObserver = nil
            }
            observedToolbar = nil
        }

        private func removeStaleAccessory(from window: NSWindow) {
            guard let index = window.titlebarAccessoryViewControllers.firstIndex(where: {
                $0.view.identifier == Self.accessoryIdentifier
            }) else {
                return
            }

            window.removeTitlebarAccessoryViewController(at: index)
        }
    }
}

private struct TitlebarSidebarToggleButton: View {
    @Binding var visibility: NavigationSplitViewVisibility
    let isAvailable: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            LiquidGlassMotion.perform(
                reduceMotion: reduceMotion,
                animation: LiquidGlassMotion.panel
            ) {
                visibility = isPresented ? .detailOnly : .all
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(isAvailable ? 1 : 0)
        .allowsHitTesting(isAvailable)
        .accessibilityHidden(!isAvailable)
        .accessibilityLabel(isPresented ? "サイドバーを隠す" : "サイドバーを表示")
        .help("左側のサイドバーを表示または非表示にします")
    }

    private var isPresented: Bool {
        visibility != .detailOnly
    }
}

struct TitlebarInspectorToggleConfigurator: NSViewRepresentable {
    @Binding var isPresented: Bool
    let isAvailable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(
            isPresented: $isPresented,
            isAvailable: isAvailable
        )
        updateWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isPresented: $isPresented,
            isAvailable: isAvailable
        )
        updateWindow(for: nsView, context: context)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.stopObservingWindow()
        }
    }

    private func updateWindow(for view: NSView, context: Context) {
        Task { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.observeWindow(in: window)
            context.coordinator.installIfNeeded(in: window)
        }
    }

    @MainActor
    final class Coordinator {
        private static let accessoryIdentifier = NSUserInterfaceItemIdentifier("VelouraLucentInspectorToggleAccessory")

        private weak var observedWindow: NSWindow?
        private var windowObservers: [NSObjectProtocol] = []
        private var accessoryController: NSTitlebarAccessoryViewController?
        private var hostingView: NSHostingView<TitlebarInspectorToggleButton>?
        private var isPresented: Binding<Bool>?
        private var isAvailable = true

        func update(
            isPresented: Binding<Bool>,
            isAvailable: Bool
        ) {
            self.isPresented = isPresented
            self.isAvailable = isAvailable
            hostingView?.rootView = TitlebarInspectorToggleButton(
                isPresented: isPresented,
                isAvailable: isAvailable
            )
        }

        func observeWindow(in window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObservingWindow()
            observedWindow = window

            let notificationCenter = NotificationCenter.default
            windowObservers = [
                notificationCenter.addObserver(
                    forName: NSWindow.didEnterFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor in
                        guard let self, let window else { return }
                        await Task.yield()
                        self.reinstallAccessory(in: window)
                    }
                },
                notificationCenter.addObserver(
                    forName: NSWindow.didExitFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    Task { @MainActor in
                        guard let self, let window else { return }
                        await Task.yield()
                        self.reinstallAccessory(in: window)
                    }
                },
                notificationCenter.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.stopObservingWindow()
                    }
                }
            ]
        }

        func installIfNeeded(in window: NSWindow) {
            guard accessoryController == nil, let isPresented else { return }

            removeStaleAccessory(from: window)

            let button = TitlebarInspectorToggleButton(
                isPresented: isPresented,
                isAvailable: isAvailable
            )
            let hostingView = NSHostingView(rootView: button)
            hostingView.frame = NSRect(x: 0, y: 0, width: 36, height: 30)
            hostingView.identifier = Self.accessoryIdentifier

            let controller = NSTitlebarAccessoryViewController()
            controller.view = hostingView
            controller.layoutAttribute = .right

            window.addTitlebarAccessoryViewController(controller)

            self.hostingView = hostingView
            self.accessoryController = controller
        }

        func stopObservingWindow() {
            let notificationCenter = NotificationCenter.default
            windowObservers.forEach(notificationCenter.removeObserver)
            windowObservers.removeAll()
            observedWindow = nil
        }

        private func removeStaleAccessory(from window: NSWindow) {
            guard let index = window.titlebarAccessoryViewControllers.firstIndex(where: {
                $0.view.identifier == Self.accessoryIdentifier
            }) else {
                return
            }

            window.removeTitlebarAccessoryViewController(at: index)
        }

        private func reinstallAccessory(in window: NSWindow) {
            if let accessoryController,
               let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessoryController }) {
                window.removeTitlebarAccessoryViewController(at: index)
            } else {
                removeStaleAccessory(from: window)
            }

            accessoryController = nil
            hostingView = nil
            installIfNeeded(in: window)
        }
    }
}

private struct TitlebarInspectorToggleButton: View {
    @Binding var isPresented: Bool
    let isAvailable: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            LiquidGlassMotion.perform(
                reduceMotion: reduceMotion,
                animation: LiquidGlassMotion.panel
            ) {
                isPresented.toggle()
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(isAvailable ? 1 : 0)
        .allowsHitTesting(isAvailable)
        .accessibilityHidden(!isAvailable)
        .accessibilityLabel(isPresented ? "設定を隠す" : "設定を表示")
        .help("右側の設定パネルを表示または非表示にします")
    }
}

private struct ContentViewPreviewHost: View {
    @State private var processingActions = ProcessingActions(
        notificationReporter: NotificationService.shared
    )

    var body: some View {
        ContentView(
            processingActions: processingActions,
            shutsDownOnDisappear: true
        )
    }
}

#Preview {
    ContentViewPreviewHost()
}
