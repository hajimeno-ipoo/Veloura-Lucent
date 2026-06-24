import AppKit
import SwiftUI

struct WindowScrollbarAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureScrollbars(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureScrollbars(from: nsView)
        }
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
