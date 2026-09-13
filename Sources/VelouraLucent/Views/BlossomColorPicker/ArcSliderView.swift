import SwiftUI

enum BlossomBrightnessCurve {
    static func lightness(for progress: Double) -> Double {
        let clampedProgress = max(0, min(1, progress))
        let easedProgress = clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
        return (1 - easedProgress) * 100
    }

    static func progress(for lightness: Double) -> Double {
        let normalizedLightness = max(0, min(100, lightness)) / 100
        let easedProgress = 1 - normalizedLightness
        return 0.5 - sin(asin(1 - 2 * easedProgress) / 3)
    }
}

struct ArcSliderView: View {
    @Bindable var model: BlossomColorPickerModel
    let radius: CGFloat

    @Environment(\.blossomStyle) private var style

    @State private var isDragging = false

    private var startAngle: Double {
        BlossomConstants.arcStartAngle
    }

    private var endAngle: Double {
        BlossomConstants.arcEndAngle
    }

    private var arcSpan: Double {
        endAngle - startAngle
    }

    var body: some View {
        let thumbAngle = startAngle
            + BlossomBrightnessCurve.progress(for: model.lightness) * arcSpan

        ZStack {
            ArcShape(startAngle: .degrees(startAngle), endAngle: .degrees(endAngle))
                .stroke(
                    .secondary.opacity(0.18),
                    style: StrokeStyle(lineWidth: style.sliderWidth, lineCap: .round)
                )
                .frame(width: radius * 2, height: radius * 2)

            // Arc track with gradient
            ArcShape(startAngle: .degrees(startAngle), endAngle: .degrees(endAngle))
                .stroke(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(endAngle)
                    ),
                    style: StrokeStyle(lineWidth: style.sliderWidth, lineCap: .round)
                )
                .frame(width: radius * 2, height: radius * 2)

            // Thumb
            Circle()
                .fill(model.selectedColor)
                .frame(
                    width: style.sliderWidth + BlossomConstants.arcThumbSizeOffset,
                    height: style.sliderWidth + BlossomConstants.arcThumbSizeOffset
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.5), lineWidth: BlossomConstants.borderWidth)
                )
                .scaleEffect(isDragging ? BlossomConstants.arcThumbDragScale : 1.0)
                .offset(
                    x: cos(thumbAngle * .pi / 180) * radius,
                    y: sin(thumbAngle * .pi / 180) * radius
                )
                .animation(.blossom, value: isDragging)
                .animation(isDragging ? nil : .blossom, value: model.lightness)
        }
        .animation(isDragging ? nil : .blossom, value: model.hue)
        .animation(isDragging ? nil : .blossom, value: model.saturation)
        .scaleEffect(model.isExpanded ? 1.0 : 0.0)
        .opacity(model.isExpanded ? 1.0 : 0.0)
        .animation(.blossom(delay: BlossomConstants.arcSliderAnimationDelay), value: model.isExpanded)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    updateLightness(from: value.location, center: CGPoint(x: radius, y: radius))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }

    private var gradientColors: [Color] {
        // Match the selected color's full 0...100 brightness range.
        (0 ..< BlossomConstants.arcGradientSteps).map { i in
            let t = Double(i) / Double(BlossomConstants.arcGradientSteps - 1)
            return Color(
                hue: model.hue / 360.0,
                saturation: model.saturation,
                brightness: BlossomBrightnessCurve.lightness(for: t) / 100,
                opacity: model.opacity
            )
        }
    }

    private func updateLightness(from location: CGPoint, center: CGPoint) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dy, dx) * 180 / .pi

        // Clamp angle to arc range
        angle = max(startAngle, min(endAngle, angle))

        // Convert angle to lightness using the same smooth curve as the thumb and gradient.
        let normalizedAngle = (angle - startAngle) / arcSpan
        let lightness = BlossomBrightnessCurve.lightness(for: normalizedAngle)
        model.updateLightness(lightness)
    }
}

struct OpacityArcSliderView: View {
    @Bindable var model: BlossomColorPickerModel
    let radius: CGFloat

    @Environment(\.blossomStyle) private var style
    @State private var isDragging = false

    private let startAngle = BlossomConstants.opacityArcStartAngle
    private let endAngle = BlossomConstants.opacityArcEndAngle

    var body: some View {
        let thumbAngle = startAngle + model.opacity * (endAngle - startAngle)

        ZStack {
            ArcShape(startAngle: .degrees(startAngle), endAngle: .degrees(endAngle))
                .stroke(
                    .secondary.opacity(0.18),
                    style: StrokeStyle(lineWidth: style.sliderWidth, lineCap: .round)
                )
                .frame(width: radius * 2, height: radius * 2)

            ArcShape(startAngle: .degrees(startAngle), endAngle: .degrees(endAngle))
                .stroke(
                    AngularGradient(
                        colors: [opaqueSelectedColor.opacity(0), opaqueSelectedColor],
                        center: .center,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(endAngle)
                    ),
                    style: StrokeStyle(lineWidth: style.sliderWidth, lineCap: .round)
                )
                .frame(width: radius * 2, height: radius * 2)

            Circle()
                .fill(opaqueSelectedColor.opacity(model.opacity))
                .frame(
                    width: style.sliderWidth + BlossomConstants.arcThumbSizeOffset,
                    height: style.sliderWidth + BlossomConstants.arcThumbSizeOffset
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.5), lineWidth: BlossomConstants.borderWidth)
                )
                .scaleEffect(isDragging ? BlossomConstants.arcThumbDragScale : 1.0)
                .offset(
                    x: cos(thumbAngle * .pi / 180) * radius,
                    y: sin(thumbAngle * .pi / 180) * radius
                )
                .animation(.blossom, value: isDragging)
                .animation(isDragging ? nil : .blossom, value: model.opacity)
        }
        .scaleEffect(model.isExpanded ? 1.0 : 0.0)
        .opacity(model.isExpanded ? 1.0 : 0.0)
        .animation(.blossom(delay: BlossomConstants.arcSliderAnimationDelay), value: model.isExpanded)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    updateOpacity(from: value.location, center: CGPoint(x: radius, y: radius))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("透明度")
        .accessibilityValue("\(Int((model.opacity * 100).rounded()))%")
    }

    private var opaqueSelectedColor: Color {
        Color(
            hue: model.hue / 360.0,
            saturation: model.saturation,
            brightness: model.lightness / 100.0
        )
    }

    private func updateOpacity(from location: CGPoint, center: CGPoint) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 {
            angle += 360
        }
        angle = max(startAngle, min(endAngle, angle))
        model.updateOpacity((angle - startAngle) / (endAngle - startAngle))
    }
}

struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

#Preview {
    @Previewable @State var model = BlossomColorPickerModel(initialColor: .green, supportsOpacity: true)

    ZStack {
        ArcSliderView(model: model, radius: BlossomConstants.arcSliderRadius)
        OpacityArcSliderView(model: model, radius: BlossomConstants.arcSliderRadius)
    }
    .frame(width: 250, height: 250)
    .onAppear {
        model.expand()
    }
    .padding(40)
}
