import AppKit
import Foundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fallbackMainWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            applyDockIcon()
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            showMainWindowIfSwiftUIWindowIsMissing()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                showMainWindowIfSwiftUIWindowIsMissing(delay: 0)
            }
        }
        return true
    }

    @MainActor
    private func showMainWindowIfSwiftUIWindowIsMissing(delay: TimeInterval = 0.8) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let hasVisibleMainWindow = NSApp.windows.contains { window in
                window.isVisible &&
                    !window.isMiniaturized &&
                    window.frame.width >= ContentView.inspectorVisibleMinimumWindowWidth &&
                    window.frame.height >= ContentView.minimumWindowHeight
            }
            guard !hasVisibleMainWindow else { return }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_380, height: 860),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "試聴と解析"
            window.minSize = NSSize(
                width: ContentView.inspectorVisibleMinimumWindowWidth,
                height: ContentView.minimumWindowHeight
            )
            self.configureLiquidGlassWindow(window)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView())
            window.center()

            let controller = NSWindowController(window: window)
            self.fallbackMainWindowController = controller
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    @MainActor
    private func applyDockIcon() {
        let bundles = [Bundle.main, Bundle.module]

        for bundle in bundles {
            guard let url = bundle.url(forResource: "AppIcon-1024", withExtension: "png"),
                  let image = NSImage(contentsOf: url) else {
                continue
            }

            NSApp.applicationIconImage = image
            NSApp.dockTile.display()
            return
        }
    }

    @MainActor
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
            ContentView()
        }
        .defaultSize(width: 1_380, height: 860)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            VelouraCommands()
        }
    }
}
