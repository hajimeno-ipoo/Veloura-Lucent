import AppKit
import SwiftUI
import Testing
@testable import VelouraLucent

@MainActor
struct VelouraScrollIndicatorTests {
    @Test
    func contentAnchorConfiguresTheEnclosingScrollView() async throws {
        let content = VStack {
            ForEach(0..<100) { index in
                Text("Row \(index)")
            }
        }
        .frame(width: 300)
        .velouraTransientOverlayScrollIndicators()

        let hostingView = NSHostingView(rootView: ScrollView { content })
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 300)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.close() }

        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        hostingView.layoutSubtreeIfNeeded()

        let scrollView = try #require(firstScrollView(in: hostingView))
        let scroller = try #require(scrollView.verticalScroller)
        let expectedAlpha: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0.55

        scrollView.tile()
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(scrollView.scrollerStyle == .overlay)
        #expect(!scrollView.autohidesScrollers)
        #expect(scroller.controlSize == .small)
        #expect(scroller.frame.width == 15)
        #expect(scroller.rect(for: .knob).width == 4)
        #expect(abs(scroller.alphaValue - expectedAlpha) < 0.001)
    }
}

@MainActor
private func firstScrollView(in root: NSView) -> NSScrollView? {
    if let scrollView = root as? NSScrollView {
        return scrollView
    }

    for subview in root.subviews {
        if let scrollView = firstScrollView(in: subview) {
            return scrollView
        }
    }

    return nil
}
