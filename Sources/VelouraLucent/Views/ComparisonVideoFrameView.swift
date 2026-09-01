import SwiftUI

struct ComparisonVideoFrameView: View {
    let state: ComparisonVideoFrameState
    let orientation: ComparisonVideoOrientation
    var onPositionChange: ((ComparisonVideoEditableElement, CGPoint) -> Void)?
    var showsDynamicOverlays: Bool

    init(
        state: ComparisonVideoFrameState,
        orientation: ComparisonVideoOrientation,
        onPositionChange: ((ComparisonVideoEditableElement, CGPoint) -> Void)? = nil,
        showsDynamicOverlays: Bool = true
    ) {
        self.state = state
        self.orientation = orientation
        self.onPositionChange = onPositionChange
        self.showsDynamicOverlays = showsDynamicOverlays
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = orientation.pixelSize
            let scale = min(
                proxy.size.width / canvasSize.width,
                proxy.size.height / canvasSize.height
            )
            ZStack {
                ComparisonVideoBackgroundView(
                    settings: state.displaySettings,
                    canvasSize: canvasSize
                )

                ComparisonVideoPositionedElement(
                    position: state.displaySettings.position(for: .title),
                    canvasSize: canvasSize,
                    element: .title,
                    onPositionChange: onPositionChange
                ) {
                    Text(state.trackTitle)
                        .font(displayFont(
                            family: state.displaySettings.titleFontFamily,
                            size: CGFloat(state.displaySettings.titleFontSize)
                        ))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(state.displaySettings.titleColor.swiftUIColor)
                        .frame(maxWidth: canvasSize.width * (orientation == .portrait ? 0.84 : 0.78))
                        .contentShape(.rect)
                }

                ComparisonVideoPositionedElement(
                    position: state.displaySettings.position(for: .role),
                    canvasSize: canvasSize,
                    element: .role,
                    onPositionChange: onPositionChange
                ) {
                    Text(state.activeRoleTitle)
                        .font(displayFont(
                            family: state.displaySettings.roleFontFamily,
                            size: CGFloat(state.displaySettings.roleFontSize)
                        ))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(activeColor)
                        .frame(maxWidth: canvasSize.width * 0.82)
                        .shadow(color: activeColor.opacity(0.8), radius: 28)
                        .scaleEffect(CGFloat(0.97 + 0.03 * state.transitionProgress))
                        .opacity(0.62 + 0.38 * state.transitionProgress)
                        .contentShape(.rect)
                }

                ComparisonVideoPositionedElement(
                    position: state.displaySettings.position(for: .inspector),
                    canvasSize: canvasSize,
                    element: .inspector,
                    onPositionChange: onPositionChange
                ) {
                    ComparisonVideoInspectorPanel(
                        info: state.activeInspectorInfo,
                        size: state.displaySettings.inspectorSize(for: orientation),
                        contentScale: CGFloat(
                            state.displaySettings.inspectorContentScale(for: orientation)
                        ),
                        layout: state.displaySettings.inspectorLayout
                    )
                }

                if showsDynamicOverlays,
                   state.displaySettings.visualizerEnabled {
                    ComparisonVideoPositionedElement(
                        position: state.displaySettings.position(for: .visualizer),
                        canvasSize: canvasSize,
                        element: .visualizer,
                        onPositionChange: onPositionChange
                    ) {
                        ComparisonVideoSpectrumVisualizer(
                            spectrum: state.visualizerSpectrum,
                            gradientStops: state.displaySettings.visualizerGradientStops,
                            size: state.displaySettings.visualizerSize(for: orientation),
                            heightScale: state.displaySettings.visualizerHeightScale
                        )
                    }
                }

                if showsDynamicOverlays, state.videoFadeLevel < 1 {
                    Color.black
                        .opacity(1 - state.videoFadeLevel)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.trackTitle)、\(state.activeRoleTitle)を再生中")
    }

    private var activeColor: Color {
        let color = state.activeSourceIndex == 0
            ? state.displaySettings.firstRoleColor
            : state.displaySettings.secondRoleColor
        return color.swiftUIColor
    }

    private func displayFont(family: String?, size: CGFloat) -> Font {
        guard let family else {
            return .system(size: size, weight: .medium, design: .rounded)
        }
        return .custom(family, size: size).weight(.medium)
    }
}

private struct ComparisonVideoSpectrumVisualizer: View {
    let spectrum: ComparisonVideoSpectrumFrame
    let gradientStops: [ComparisonVideoVisualizerGradientStop]
    let size: CGSize
    let heightScale: Double

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, canvasSize in
            let dots = ComparisonVideoSpectrumGeometry.dots(
                for: spectrum,
                in: canvasSize,
                heightScale: heightScale
            )
            let start = CGPoint(x: 0, y: canvasSize.height / 2)
            let end = CGPoint(x: canvasSize.width, y: canvasSize.height / 2)
            let layers: [([CGRect], Double)] = [
                (dots.outerGlowDots, 0.08),
                (dots.innerGlowDots, 0.16),
                (dots.peakGlowDots, 0.24),
                (dots.inactiveDots, 0.10),
                (dots.lowDots, 0.68),
                (dots.middleDots, 0.84),
                (dots.highDots, 1),
                (dots.reflectionDots, 0.18),
                (dots.peakDots, 1)
            ]
            for (rects, opacity) in layers {
                fill(
                    rects,
                    in: &context,
                    opacity: opacity,
                    start: start,
                    end: end
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(.rect)
        .accessibilityHidden(true)
    }

    private func fill(
        _ rects: [CGRect],
        in context: inout GraphicsContext,
        opacity: Double,
        start: CGPoint,
        end: CGPoint
    ) {
        guard !rects.isEmpty else { return }
        var path = Path()
        for rect in rects {
            path.addEllipse(in: rect)
        }
        context.fill(
            path,
            with: .linearGradient(
                Gradient(stops: gradientStops.map { stop in
                    .init(
                        color: stop.color.swiftUIColor.opacity(opacity),
                        location: CGFloat(stop.location)
                    )
                }),
                startPoint: start,
                endPoint: end
            )
        )
    }
}

private struct ComparisonVideoBackgroundView: View {
    let settings: ComparisonVideoDisplaySettings
    let canvasSize: CGSize

    var body: some View {
        Color(
            red: settings.backgroundColor.red,
            green: settings.backgroundColor.green,
            blue: settings.backgroundColor.blue,
            opacity: settings.backgroundColor.alpha
        )
        .frame(width: canvasSize.width, height: canvasSize.height)
        .overlay {
            if let backgroundImage = settings.backgroundImage {
                switch settings.backgroundImageLayout {
                case .fill:
                    Image(nsImage: backgroundImage.image)
                        .resizable()
                        .scaledToFill()
                case .fit:
                    Image(nsImage: backgroundImage.image)
                        .resizable()
                        .scaledToFit()
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ComparisonVideoPositionedElement<Content: View>: View {
    let position: CGPoint
    let canvasSize: CGSize
    let element: ComparisonVideoEditableElement
    let onPositionChange: ((ComparisonVideoEditableElement, CGPoint) -> Void)?
    let content: Content

    @GestureState private var dragTranslation = CGSize.zero

    init(
        position: CGPoint,
        canvasSize: CGSize,
        element: ComparisonVideoEditableElement,
        onPositionChange: ((ComparisonVideoEditableElement, CGPoint) -> Void)?,
        @ViewBuilder content: () -> Content
    ) {
        self.position = position
        self.canvasSize = canvasSize
        self.element = element
        self.onPositionChange = onPositionChange
        self.content = content()
    }

    var body: some View {
        content
            .position(
                x: canvasSize.width * position.x / 100,
                y: canvasSize.height * position.y / 100
            )
            .offset(clampedTranslation)
            .gesture(dragGesture)
            .allowsHitTesting(onPositionChange != nil)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragTranslation) { value, translation, _ in
                guard onPositionChange != nil else { return }
                translation = value.translation
            }
            .onEnded { value in
                guard let onPositionChange else { return }
                onPositionChange(
                    element,
                    translatedPosition(by: value.translation)
                )
            }
    }

    private var clampedTranslation: CGSize {
        let translated = translatedPosition(by: dragTranslation)
        return CGSize(
            width: (translated.x - position.x) / 100 * canvasSize.width,
            height: (translated.y - position.y) / 100 * canvasSize.height
        )
    }

    private func translatedPosition(by translation: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(position.x + translation.width / canvasSize.width * 100, 0), 100),
            y: min(max(position.y + translation.height / canvasSize.height * 100, 0), 100)
        )
    }
}

private struct ComparisonVideoInspectorPanel: View {
    let size: CGSize
    let contentScale: CGFloat
    let layout: ComparisonVideoInspectorLayout
    private let values: [ComparisonVideoInspectorValue]

    init(
        info: ComparisonVideoInspectorInfo?,
        size: CGSize,
        contentScale: CGFloat,
        layout: ComparisonVideoInspectorLayout
    ) {
        self.size = size
        self.contentScale = contentScale
        self.layout = layout
        values = ComparisonVideoInspectorValue.make(from: info)
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            let scale = contentScale
            let referenceSize = CGSize(
                width: size.width / scale,
                height: size.height / scale
            )
            context.scaleBy(x: scale, y: scale)
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: referenceSize), cornerRadius: 28),
                with: .color(.black.opacity(0.44))
            )

            let contentWidth = referenceSize.width - layout.panelPadding * 2
                - CGFloat(layout.columnCount - 1) * layout.horizontalSpacing
            let contentHeight = referenceSize.height - layout.panelPadding * 2
                - CGFloat(layout.rowCount - 1) * layout.verticalSpacing
            let cellSize = CGSize(
                width: max(contentWidth / CGFloat(layout.columnCount), 1),
                height: max(contentHeight / CGFloat(layout.rowCount), 1)
            )

            for index in values.indices {
                let row = index / layout.columnCount
                let column = index % layout.columnCount
                let center = CGPoint(
                    x: layout.panelPadding
                        + CGFloat(column) * (cellSize.width + layout.horizontalSpacing)
                        + cellSize.width / 2,
                    y: layout.panelPadding
                        + CGFloat(row) * (cellSize.height + layout.verticalSpacing)
                        + cellSize.height / 2
                )
                draw(values[index], at: center, in: &context)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(.rect(cornerRadius: 28 * contentScale))
    }

    private func draw(
        _ item: ComparisonVideoInspectorValue,
        at center: CGPoint,
        in context: inout GraphicsContext
    ) {
        let labelSize = layout.labelFontSize
        let valueSize = layout.valueFontSize
        context.draw(
            Text(item.label)
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.68)),
            at: CGPoint(x: center.x, y: center.y - valueSize * 0.55),
            anchor: .center
        )
        context.draw(
            Text(item.value)
                .font(.system(size: valueSize, weight: .semibold))
                .foregroundStyle(.white),
            at: CGPoint(x: center.x, y: center.y + labelSize * 0.55),
            anchor: .center
        )
    }
}

private struct ComparisonVideoInspectorValue: Equatable {
    let label: String
    let value: String

    static func make(from info: ComparisonVideoInspectorInfo?) -> [Self] {
        let metrics = info?.metrics
        let fileInfo = info?.fileInfo
        return [
            Self(label: "音量", value: measurement(metrics?.integratedLoudnessLUFS, decimals: 1, unit: "LUFS")),
            Self(label: "ピーク", value: measurement(metrics?.truePeakDBFS, decimals: 1, unit: "dBTP")),
            Self(label: "強弱", value: measurement(metrics?.crestFactorDB, decimals: 1, unit: "dB")),
            Self(label: "ステレオ幅", value: measurement(metrics?.stereoWidth, decimals: 2, unit: "")),
            Self(label: "形式", value: fileInfo?.formatName ?? "未取得"),
            Self(label: "サンプルレート", value: fileInfo?.sampleRateText ?? "未取得"),
            Self(label: "ビット深度", value: bitDepthText(fileInfo)),
            Self(label: "チャンネル", value: fileInfo?.channelText ?? "未取得"),
        ]
    }

    private static func measurement(_ value: Double?, decimals: Int, unit: String) -> String {
        guard let value, value.isFinite else { return "未測定" }
        let number = String(format: "%.*f", decimals, value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private static func bitDepthText(_ fileInfo: AudioFileInfo?) -> String {
        guard let fileInfo, let bitDepth = fileInfo.bitDepth else { return "未取得" }
        return fileInfo.isFloatingPoint ? "\(bitDepth)-bit float" : "\(bitDepth) bit"
    }
}

private extension ComparisonVideoRGBAColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
