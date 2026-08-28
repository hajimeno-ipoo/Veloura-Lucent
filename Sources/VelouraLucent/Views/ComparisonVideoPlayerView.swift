import AVKit
import SwiftUI

struct ComparisonVideoPlayerView: View {
    @Bindable var model: ComparisonVideoWindowModel

    var body: some View {
        ZStack {
            Color.clear

            if let player = model.previewPlayer,
               let state = model.frameState {
                ComparisonVideoNativePlayerView(
                    player: player,
                    state: state,
                    orientation: model.orientation
                )
                .aspectRatio(
                    model.orientation.pixelSize.width / model.orientation.pixelSize.height,
                    contentMode: .fit
                )
                .padding(8)
                .velouraAdaptiveGlass(in: .rect(cornerRadius: 18))
                .padding(24)
            } else if model.isPreparingPreview {
                ProgressView("プレイヤーを準備しています")
                    .controlSize(.small)
                    .padding(24)
                    .velouraAdaptiveGlass(in: .rect(cornerRadius: 18))
            } else {
                Text("比較する2つの音源を選択してください")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .velouraAdaptiveGlass(in: .rect(cornerRadius: 18))
            }
        }
    }
}

private struct ComparisonVideoNativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    let state: ComparisonVideoFrameState
    let orientation: ComparisonVideoOrientation

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = ComparisonVideoAVPlayerView()
        playerView.player = player
        playerView.videoGravity = .resizeAspect
        playerView.updatesNowPlayingInfoCenter = false
        updateOverlay(in: playerView, coordinator: context.coordinator)
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
        updateOverlay(in: playerView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Coordinator) {
        playerView.player = nil
        coordinator.hostingView?.removeFromSuperview()
        coordinator.hostingView = nil
    }

    private func updateOverlay(in playerView: AVPlayerView, coordinator: Coordinator) {
        guard let overlayContainer = playerView.contentOverlayView else { return }
        let content = AnyView(
            ComparisonVideoFrameView(state: state, orientation: orientation)
                .allowsHitTesting(false)
        )

        if let hostingView = coordinator.hostingView {
            hostingView.rootView = content
            return
        }

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: overlayContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: overlayContainer.bottomAnchor),
        ])
        coordinator.hostingView = hostingView
    }

    final class Coordinator {
        var hostingView: NSHostingView<AnyView>?
    }
}

private final class ComparisonVideoAVPlayerView: AVPlayerView {
    private var pointerTrackingArea: NSTrackingArea?
    private var isPointerInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResignKeyNotification,
            object: nil
        )

        guard let window else {
            isPointerInside = false
            updateControlsVisibility()
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowKeyStateChanged),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowKeyStateChanged),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        updatePointerLocation()
        updateControlsVisibility()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        updateControlsVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        updateControlsVisibility()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowKeyStateChanged(_ notification: Notification) {
        updatePointerLocation()
        updateControlsVisibility()
    }

    private func updatePointerLocation() {
        guard let window else {
            isPointerInside = false
            return
        }
        let pointerLocation = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        isPointerInside = bounds.contains(pointerLocation)
    }

    private func updateControlsVisibility() {
        controlsStyle = isPointerInside && window?.isKeyWindow == true
            ? .inline
            : .none
    }
}
