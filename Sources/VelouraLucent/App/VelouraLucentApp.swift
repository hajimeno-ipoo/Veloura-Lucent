import AppKit
import Foundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockIcon()
        NotificationService.shared.requestAuthorization()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
        .defaultSize(width: 760, height: 520)
    }
}
