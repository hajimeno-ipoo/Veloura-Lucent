import AppKit
import Foundation
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var runtimeStartTask: Task<Void, Never>?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        runtimeStartTask = Task { @MainActor in
            await VelouraAppRuntime.shared.startIfNeeded()
        }
        Task { @MainActor in
            applyDockIcon()
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            MainWorkspaceWindowPresenter.shared.showMainWindowIfSwiftUIWindowIsMissing()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            MainWorkspaceWindowPresenter.shared.showMainWindowIfSwiftUIWindowIsMissing(delay: 0)
        }
        return false
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }

        Task { @MainActor in
            MainWorkspaceWindowPresenter.shared.showMainWindowIfSwiftUIWindowIsMissing(delay: 0)
            completionHandler()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtimeStartTask?.cancel()
        runtimeStartTask = nil
        MainActor.assumeIsolated {
            VelouraAppRuntime.shared.shutdown()
        }
    }

    @MainActor
    private func applyDockIcon() {
        if Bundle.main.url(forResource: "VelouraLucent", withExtension: "icon") != nil {
            return
        }

        let candidateURLs = [
            Bundle.main.url(forResource: "AppIcon-1024", withExtension: "png"),
            AppResourceBundle.url(forResource: "AppIcon-1024", withExtension: "png"),
        ]
        for url in candidateURLs.compactMap({ $0 }) {
            guard let image = NSImage(contentsOf: url) else { continue }
            NSApp.applicationIconImage = image
            NSApp.dockTile.display()
            return
        }
    }
}

@MainActor
private final class MainWorkspaceWindowPresenter {
    static let shared = MainWorkspaceWindowPresenter()

    private var fallbackMainWindowController: NSWindowController?

    func showMainWindowIfSwiftUIWindowIsMissing(delay: TimeInterval = 0.8) {
        guard delay > 0 else {
            showMainWindowIfSwiftUIWindowIsMissingNow()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.showMainWindowIfSwiftUIWindowIsMissingNow()
        }
    }

    private func showMainWindowIfSwiftUIWindowIsMissingNow() {
        if let existingMainWindow = NSApp.windows.first(where: isMainWorkspaceWindow) {
            presentMainWorkspaceWindow(existingMainWindow)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_380, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "試聴と解析"
        window.minSize = NSSize(
            width: WorkspaceLayoutMetrics.inspectorVisibleMinimumWindowWidth,
            height: WorkspaceLayoutMetrics.minimumWindowHeight
        )
        configureLiquidGlassWindow(window)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: VelouraRootView())
        window.center()

        let controller = NSWindowController(window: window)
        fallbackMainWindowController = controller
        controller.showWindow(nil)
        presentMainWorkspaceWindow(window)
    }

    private func isMainWorkspaceWindow(_ window: NSWindow) -> Bool {
        guard window.title != "Veloura Lucentについて",
              window.title != "比較動画" else {
            return false
        }
        return window.frame.width >= WorkspaceLayoutMetrics.inspectorVisibleMinimumWindowWidth &&
            window.frame.height >= WorkspaceLayoutMetrics.minimumWindowHeight
    }

    private func presentMainWorkspaceWindow(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func configureLiquidGlassWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }
}

@main
struct VelouraLucentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Veloura Lucent") {
            VelouraRootView()
        }
        .defaultSize(width: 1_380, height: 860)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
        .commands {
            VelouraCommands()
        }

        Window("Veloura Lucentについて", id: "about") {
            VelouraAboutView()
        }
        .defaultSize(width: 760, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Window("比較動画", id: "comparison-video") {
            ComparisonVideoWindowView(launchStore: .shared)
        }
        .defaultSize(width: 1_220, height: 780)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
    }
}
