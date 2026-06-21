import AppKit
import Foundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fallbackMainWindowController: NSWindowController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockIcon()
        NotificationService.shared.requestAuthorization()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showMainWindowIfSwiftUIWindowIsMissing()
    }

    @MainActor
    private func showMainWindowIfSwiftUIWindowIsMissing() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard NSApp.windows.allSatisfy({ !$0.isVisible }) else { return }

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
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView())
            window.center()

            let controller = NSWindowController(window: window)
            self?.fallbackMainWindowController = controller
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
}

@main
struct VelouraLucentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Veloura Lucent") {
            ContentView()
        }
        .defaultSize(width: 1_380, height: 860)
        .windowResizability(.contentMinSize)
    }
}
