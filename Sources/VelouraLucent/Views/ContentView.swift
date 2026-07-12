import AppKit
import SwiftUI

struct ContentView: View {
    static let inspectorVisibleMinimumWindowWidth: CGFloat = 1_380
    static let inspectorHiddenMinimumWindowWidth: CGFloat = 960
    static let minimumWindowHeight: CGFloat = 720

    @State private var processingActions = ProcessingActions(notificationReporter: NotificationService.shared)
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorPresented = true
    @State private var isWindowFullScreen = false
    @State private var inputAudioDropVisualState: InputAudioDropVisualState = .inactive
    @State private var windowBackgroundMaterialAmount = AppAppearanceSettings.storedWindowBackgroundMaterialAmount()
    @State private var highlightedToolbarTarget: LiquidGlassToolbarTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var toolbarGlassNamespace
    @Namespace private var inspectorGlassNamespace

    private var job: ProcessingJob {
        processingActions.job
    }

    private var preview: AudioPreviewController {
        processingActions.preview
    }

    var body: some View {
        @Bindable var actions = processingActions

        mainContent
            .environment(\.velouraIsFullScreen, isWindowFullScreen)
            .frame(minWidth: minimumWindowWidth, minHeight: Self.minimumWindowHeight)
            .velouraWindowBackground(
                amount: windowBackgroundMaterialAmount,
                isFullScreen: isWindowFullScreen
            )
            .background(
                WindowChromeConfigurator(
                    minSize: NSSize(width: minimumWindowWidth, height: Self.minimumWindowHeight),
                    isFullScreen: $isWindowFullScreen
                )
            )
            .background(TitlebarSidebarToggleConfigurator(visibility: $sidebarVisibility))
            .background(TitlebarInspectorToggleConfigurator(isPresented: $isInspectorPresented))
            .background(WindowScrollbarAppearanceConfigurator())
            .focusedSceneValue(\.velouraCommandActions, commandActions)
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
                processingActions.shutdown()
            }
    }

    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            VelouraSidebarView(job: job)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            HStack(spacing: 0) {
                ZStack {
                    VelouraMainWorkspaceView(
                        job: job,
                        preview: preview
                    )
                    .frame(minWidth: 620, maxWidth: .infinity)

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
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)

                if isInspectorPresented {
                    Divider()
                    VelouraInspectorView(
                        job: job,
                        completionReport: completionReport,
                        windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                        isWindowFullScreen: isWindowFullScreen
                    )
                    .frame(width: 440)
                    .glassEffectID("right-inspector-panel", in: inspectorGlassNamespace)
                    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                    .transition(inspectorTransition)
                }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar(removing: .sidebarToggle)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarActionGroup
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .principal)

            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(AudioExportFormat.allCases) { format in
                        Menu(format.menuTitle) {
                            Button("補正後を書き出し") {
                                processingActions.exportCorrectedAudio(as: format)
                            }
                            .disabled(!job.hasExistingOutput || job.isProcessing)

                            Button("最終版を書き出し") {
                                processingActions.exportMasteredAudio(as: format)
                            }
                            .disabled(!job.hasExistingMasteredOutput || job.isMastering)
                        }
                    }
                } label: {
                    toolbarExportLabel("書き出し", systemImage: "square.and.arrow.down")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .padding(4)
                .velouraAdaptiveGlass(in: .capsule, interactive: true)
                .onHover { updateToolbarHighlight(.export, isHovering: $0) }
                .accessibilityLabel("書き出し")
                .help("補正後または最終版を書き出します")
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var toolbarActionGroup: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: processingActions.chooseInputAudio) {
                    toolbarActionLabel("音声を選ぶ", systemImage: "waveform.badge.plus", target: .chooseInput)
                }
                .buttonStyle(.plain)
                .onHover { updateToolbarHighlight(.chooseInput, isHovering: $0) }
                .help("入力音声を選びます")
                .disabled(job.isProcessing || job.isMastering)

                Button(action: processingActions.performCorrectionAction) {
                    toolbarActionLabel(
                        correctionToolbarTitle,
                        systemImage: job.isProcessing ? "xmark.circle.fill" : "wand.and.sparkles",
                        target: .runCorrection
                    )
                }
                .buttonStyle(.plain)
                .onHover { updateToolbarHighlight(.runCorrection, isHovering: $0) }
                .help(job.isProcessing ? "補正処理をキャンセルします" : "入力音声に補正処理をかけます")
                .disabled(isCorrectionToolbarActionDisabled)

                Button(action: processingActions.performMasteringAction) {
                    toolbarActionLabel(
                        masteringToolbarTitle,
                        systemImage: job.isMastering ? "xmark.circle.fill" : "slider.horizontal.3",
                        target: .runMastering
                    )
                }
                .buttonStyle(.plain)
                .onHover { updateToolbarHighlight(.runMastering, isHovering: $0) }
                .help(job.isMastering ? "マスタリングをキャンセルします" : "補正後音声を最終版へ仕上げます")
                .disabled(isMasteringToolbarActionDisabled)
            }
            .padding(4)
            .velouraAdaptiveGlass(in: .capsule, interactive: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var inspectorTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .trailing).combined(with: .opacity)
    }

    private func toolbarActionLabel(
        _ title: String,
        systemImage: String,
        target: LiquidGlassToolbarTarget
    ) -> some View {
        toolbarLabel(title, systemImage: systemImage)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassCapsuleMorphSurface(
                isActive: highlightedToolbarTarget == target,
                effectID: "toolbar-action-highlight",
                namespace: toolbarGlassNamespace,
                reduceMotion: reduceMotion
            )
    }

    private func toolbarExportLabel(_ title: String, systemImage: String) -> some View {
        toolbarLabel(title, systemImage: systemImage)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassCapsuleMorphSurface(
                isActive: highlightedToolbarTarget == .export,
                effectID: "toolbar-action-highlight",
                namespace: toolbarGlassNamespace,
                reduceMotion: reduceMotion
            )
    }

    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
        .font(.callout)
        .fixedSize()
    }

    @MainActor
    private func updateToolbarHighlight(_ target: LiquidGlassToolbarTarget, isHovering: Bool) {
        let nextTarget = isHovering ? target : (highlightedToolbarTarget == target ? nil : highlightedToolbarTarget)
        guard nextTarget != highlightedToolbarTarget else { return }
        LiquidGlassMotion.perform(
            reduceMotion: reduceMotion,
            animation: LiquidGlassMotion.selection
        ) {
            highlightedToolbarTarget = nextTarget
        }
    }

    private var completionReport: CompletionReport? {
        CompletionReportService.makeReport(
            input: job.inputMetrics,
            corrected: job.outputMetrics,
            mastered: job.masteredMetrics,
            inputNoise: job.inputNoiseMeasurements,
            correctedNoise: job.outputNoiseMeasurements,
            masteredNoise: job.masteredNoiseMeasurements,
            correctionSettings: job.appliedCorrectionSettings ?? job.editableCorrectionSettings,
            masteringSettings: job.appliedMasteringSettings ?? job.editableMasteringSettings
        )
    }

    private var minimumWindowWidth: CGFloat {
        isInspectorPresented ? Self.inspectorVisibleMinimumWindowWidth : Self.inspectorHiddenMinimumWindowWidth
    }

    private var commandActions: VelouraCommandActions {
        VelouraCommandActions(
            canChooseInput: !job.isProcessing && !job.isMastering,
            canRunCorrection: job.inputFile != nil && !job.isProcessing && !job.isMastering,
            canRunMastering: processingActions.canStartMastering,
            isCorrectionRunning: job.isProcessing,
            isMasteringRunning: job.isMastering,
            canCancelCorrection: job.isProcessing && !job.isCancellingProcessing,
            canCancelMastering: job.isMastering && !job.isCancellingMastering,
            canExportCorrected: job.hasExistingOutput && !job.isProcessing,
            canExportMastered: job.hasExistingMasteredOutput && !job.isMastering,
            canTogglePlayback: preview.canToggleComparisonPlayback,
            canStopPlayback: preview.activeTarget != nil,
            canToggleComparisonSide: preview.canToggleComparisonSide,
            isPlaybackRunning: preview.isComparisonPlaybackRunning,
            isInspectorPresented: isInspectorPresented,
            chooseInputAudio: processingActions.chooseInputAudio,
            runCorrection: processingActions.startCorrectionProcessing,
            runMastering: processingActions.startMasteringProcessing,
            cancelCorrection: processingActions.cancelCorrectionProcessing,
            cancelMastering: processingActions.cancelMasteringProcessing,
            exportCorrected: processingActions.exportCorrectedAudio,
            exportMastered: processingActions.exportMasteredAudio,
            togglePlayback: preview.toggleComparisonPlayback,
            stopPlayback: { preview.stopPlayback() },
            toggleComparisonSide: preview.toggleComparisonSide,
            toggleInspector: toggleInspector
        )
    }

    private var correctionToolbarTitle: String {
        if job.isCancellingProcessing {
            return "キャンセル中..."
        }
        return job.isProcessing ? "補正をキャンセル" : "補正を実行"
    }

    private var masteringToolbarTitle: String {
        if job.isCancellingMastering {
            return "キャンセル中..."
        }
        return job.isMastering ? "マスタリングをキャンセル" : "マスタリングを実行"
    }

    private var isCorrectionToolbarActionDisabled: Bool {
        if job.isProcessing {
            return job.isCancellingProcessing
        }
        return job.inputFile == nil || job.isMastering
    }

    private var isMasteringToolbarActionDisabled: Bool {
        if job.isMastering {
            return job.isCancellingMastering
        }
        return !processingActions.canStartMastering
    }

    private func toggleInspector() {
        LiquidGlassMotion.perform(
            reduceMotion: reduceMotion,
            animation: LiquidGlassMotion.panel
        ) {
            isInspectorPresented.toggle()
        }
    }
}

private extension View {
    @ViewBuilder
    func velouraWindowBackground(amount: Double, isFullScreen: Bool) -> some View {
        if isFullScreen {
            self
        } else {
            let clampedAmount = AppAppearanceSettings.clampedWindowBackgroundMaterialAmount(amount)
            containerBackground(
                .thinMaterial.materialActiveAppearance(.active).opacity(clampedAmount),
                for: .window
            )
        }
    }

}

private struct WindowChromeConfigurator: NSViewRepresentable {
    let minSize: NSSize
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(isFullScreen: $isFullScreen)
        updateWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isFullScreen: $isFullScreen)
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
        window.titleVisibility = .hidden
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var observedWindow: NSWindow?
        private weak var previousWindowDelegate: NSWindowDelegate?
        private var isFullScreen: Binding<Bool>?
        private var restoresFullSizeContentView = false

        func update(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
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
            if isFullScreen {
                prepareWindowForFullScreenTransition(window)
            } else {
                if restoresFullSizeContentView {
                    window.styleMask.insert(.fullSizeContentView)
                }
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            if self.isFullScreen?.wrappedValue != isFullScreen {
                self.isFullScreen?.wrappedValue = isFullScreen
            }
        }

        private func prepareWindowForFullScreenTransition(_ window: NSWindow) {
            window.styleMask.remove(.fullSizeContentView)
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.contentView?.needsDisplay = true
            window.displayIfNeeded()
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

private struct TitlebarSidebarToggleConfigurator: NSViewRepresentable {
    @Binding var visibility: NavigationSplitViewVisibility

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(visibility: $visibility)
        updateWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(visibility: $visibility)
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
        // SwiftUI NavigationSplitView uses this runtime toolbar item for its default sidebar toggle.
        private static let swiftUISidebarToggleIdentifier = NSToolbarItem.Identifier(
            "com.apple.SwiftUI.navigationSplitView.toggleSidebar"
        )

        private weak var observedToolbar: NSToolbar?
        private var toolbarWillAddObserver: NSObjectProtocol?
        private var accessoryController: NSTitlebarAccessoryViewController?
        private var hostingView: NSHostingView<TitlebarSidebarToggleButton>?
        private var visibility: Binding<NavigationSplitViewVisibility>?

        func update(visibility: Binding<NavigationSplitViewVisibility>) {
            self.visibility = visibility
            hostingView?.rootView = TitlebarSidebarToggleButton(visibility: visibility)
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

            let button = TitlebarSidebarToggleButton(visibility: visibility)
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

    var body: some View {
        Button {
            visibility = isSidebarVisible ? .detailOnly : .all
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
        .accessibilityLabel(isSidebarVisible ? "サイドバーを隠す" : "サイドバーを表示")
        .help("左側のサイドバーを表示または非表示にします")
    }

    private var isSidebarVisible: Bool {
        visibility != .detailOnly
    }
}

private struct TitlebarInspectorToggleConfigurator: NSViewRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(isPresented: $isPresented)
        updateWindow(for: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isPresented: $isPresented)
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

        func update(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
            hostingView?.rootView = TitlebarInspectorToggleButton(isPresented: isPresented)
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

            let button = TitlebarInspectorToggleButton(isPresented: isPresented)
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
        .accessibilityLabel(isPresented ? "設定を隠す" : "設定を表示")
        .help("右側の設定パネルを表示または非表示にします")
    }
}

#Preview {
    ContentView()
}
