import AppKit
import SwiftUI

struct DAWKnobControl: View {
    let title: String
    let help: SettingHelp?
    let valueText: String
    let displayValueText: String?
    let unitText: String?
    let labels: [String]
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let dragValueScale: Float
    let isInteractionEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var dragStartValue: Float?
    @State private var isActivelyInteracting = false
    @State private var keyRepeatTask: Task<Void, Never>?
    @State private var activeStepRail: StepRail?

    var body: some View {
        ZStack(alignment: .topLeading) {
            knobSurface
            overlayLabels
            stepRails
        }
        .frame(width: DAWKnobMetrics.controlWidth, height: DAWKnobMetrics.controlHeight)
    }

    init(
        title: String,
        help: SettingHelp?,
        valueText: String,
        displayValueText: String? = nil,
        unitText: String? = nil,
        labels: [String],
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        dragValueScale: Float = 1,
        isInteractionEnabled: Bool = true
    ) {
        self.title = title
        self.help = help
        self.valueText = valueText
        self.displayValueText = displayValueText
        self.unitText = unitText
        self.labels = labels
        self._value = value
        self.range = range
        self.step = step
        self.dragValueScale = dragValueScale
        self.isInteractionEnabled = isInteractionEnabled
    }

    private var knobSurface: some View {
        ZStack(alignment: .topLeading) {
            DAWKnobValueRing(value: value, range: range, isEnabled: isInteractionEnabled)
                .frame(width: DAWKnobMetrics.ringDiameter, height: DAWKnobMetrics.ringDiameter)
                .position(DAWKnobMetrics.knobDisplayCenter)
                .accessibilityHidden(true)

            fullArtworkImage(DAWKnobMetrics.rotatingArtworkImage)
                .rotationEffect(
                    .degrees(DAWKnobMetrics.displayAngleDegrees(value: value, range: range)),
                    anchor: DAWKnobMetrics.rotationAnchor
                )
        }
        .frame(width: DAWKnobMetrics.controlWidth, height: DAWKnobMetrics.controlHeight)
        .contentShape(.interaction, Path(ellipseIn: DAWKnobMetrics.knobHitRect))
        .highPriorityGesture(dragGesture)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow], phases: .all) { keyPress in
            if keyPress.phase == .up {
                stopKeyRepeat()
                return .handled
            }

            if keyPress.phase == .down {
                switch keyPress.key {
                case .upArrow, .rightArrow:
                    beginKeyRepeat(delta: step)
                case .downArrow, .leftArrow:
                    beginKeyRepeat(delta: -step)
                default:
                    return .ignored
                }
            }

            // The repeat cadence is driven by NSEvent's system settings below.
            return .handled
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                stopKeyRepeat()
            }
        }
        .onDisappear(perform: stopKeyRepeat)
        .disabled(!isInteractionEnabled)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjust(by: step, animated: true)
            case .decrement:
                adjust(by: -step, animated: true)
            @unknown default:
                break
            }
        }
    }

    private var overlayLabels: some View {
        ZStack(alignment: .topLeading) {
            valueAndUnitLabel

            if labels.indices.contains(1) {
                overlayText(labels[1], font: .system(size: 10), at: DAWKnobMetrics.topLabelCenter, width: 120)
                    .foregroundStyle(.secondary)
            }
            if labels.indices.contains(0) {
                overlayText(labels[0], font: .system(size: 10), at: DAWKnobMetrics.leftLabelCenter, width: 120)
                    .foregroundStyle(.secondary)
            }
            if labels.indices.contains(2) {
                overlayText(labels[2], font: .system(size: 10), at: DAWKnobMetrics.rightLabelCenter, width: 140)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(isActivelyInteracting ? Color.green : Color.clear)
                    .stroke(Color.secondary, lineWidth: 1)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                if let help {
                    TermHelpButton(title: help.title, reading: help.reading, description: help.description)
                }
            }
            .frame(width: DAWKnobMetrics.controlWidth - 4)
            .position(DAWKnobMetrics.titleCenter)
        }
    }

    private var valueAndUnitLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: DAWKnobMetrics.valueUnitSpacing) {
            Text(displayValueText ?? valueText)
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)

            if let unitText {
                Text(unitText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.9)
        .frame(width: DAWKnobMetrics.valueTextWidth)
        .position(DAWKnobMetrics.valueCenter)
        .accessibilityHidden(true)
    }

    private var stepRails: some View {
        ZStack(alignment: .topLeading) {
            stepRailButton(
                rail: .decrement,
                label: "\(title)を下げる",
                center: DAWKnobMetrics.decrementRailCenter,
                delta: -step
            )
            stepRailButton(
                rail: .increment,
                label: "\(title)を上げる",
                center: DAWKnobMetrics.incrementRailCenter,
                delta: step
            )
        }
        .frame(width: DAWKnobMetrics.controlWidth, height: DAWKnobMetrics.controlHeight)
        .disabled(!isInteractionEnabled)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStartValue == nil {
                    dragStartValue = value
                }
                isActivelyInteracting = true
                let startValue = dragStartValue ?? value
                let nextValue = startValue + DAWKnobMetrics.dragValueDelta(
                    forTranslationHeight: gesture.translation.height,
                    valueScale: dragValueScale
                )
                value = DAWKnobMetrics.clamped(nextValue, to: range)
            }
            .onEnded { _ in
                dragStartValue = nil
                isActivelyInteracting = false
            }
    }

    private func fullArtworkImage(_ image: NSImage?) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: DAWKnobMetrics.artworkSize, height: DAWKnobMetrics.artworkSize)
        .position(
            x: DAWKnobMetrics.artworkOrigin.x + DAWKnobMetrics.artworkSize / 2,
            y: DAWKnobMetrics.artworkOrigin.y + DAWKnobMetrics.artworkSize / 2
        )
        .accessibilityHidden(true)
    }

    private func overlayText(_ text: String, font: Font, at point: CGPoint, width: CGFloat = 78) -> some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(width: width)
            .position(point)
            .accessibilityHidden(true)
    }

    private func stepRailButton(
        rail: StepRail,
        label: String,
        center: CGPoint,
        delta: Float
    ) -> some View {
        Button {
            adjust(by: delta, animated: true)
        } label: {
            ZStack {
                DAWKnobStepRail(
                    isActive: activeStepRail == rail && isActivelyInteracting,
                    isEnabled: isInteractionEnabled
                )
                    .frame(
                        width: DAWKnobMetrics.stepRailVisibleSize.width,
                        height: DAWKnobMetrics.stepRailVisibleSize.height
                    )
            }
            .frame(
                width: DAWKnobMetrics.stepRailHitSize.width,
                height: DAWKnobMetrics.stepRailHitSize.height
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(
            PressTrackingPlainButtonStyle { isPressed in
                activeStepRail = isPressed ? rail : nil
                isActivelyInteracting = isPressed
            }
        )
        .position(center)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private func beginKeyRepeat(delta: Float) {
        stopKeyRepeat()
        isActivelyInteracting = true
        adjust(by: delta, animated: true)

        keyRepeatTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(NSEvent.keyRepeatDelay))

            while !Task.isCancelled {
                adjust(by: delta, animated: true)
                try? await Task.sleep(for: .seconds(NSEvent.keyRepeatInterval))
            }
        }
    }

    private func stopKeyRepeat() {
        keyRepeatTask?.cancel()
        keyRepeatTask = nil
        activeStepRail = nil
        isActivelyInteracting = false
    }

    private func adjust(by delta: Float, animated: Bool) {
        let nextValue = DAWKnobMetrics.clamped(value + delta, to: range)
        guard animated, !reduceMotion else {
            value = nextValue
            return
        }
        withAnimation(.easeOut(duration: DAWKnobMetrics.stepAnimationDuration)) {
            value = nextValue
        }
    }
}

private enum StepRail {
    case decrement
    case increment
}

private struct DAWKnobValueRing: View {
    let value: Float
    let range: ClosedRange<Float>
    let isEnabled: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2 - 2
            let innerRadius = outerRadius - 7

            for index in 0 ..< DAWKnobMetrics.ringTickCount {
                let progress = DAWKnobMetrics.ringTickProgress(at: index)
                let angle = DAWKnobMetrics.ringTickAngleDegrees(at: index) * .pi / 180
                let start = CGPoint(
                    x: center.x + cos(angle) * innerRadius,
                    y: center.y + sin(angle) * innerRadius
                )
                let end = CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                )
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)

                let isActive = DAWKnobMetrics.ringTickIsActive(
                    at: index,
                    value: value,
                    range: range
                )
                let activeColor = Color(
                    hue: 0.72 - progress * 0.18,
                    saturation: 0.78,
                    brightness: 0.98
                )
                let color = isActive ? activeColor : Color.secondary.opacity(0.22)

                context.stroke(
                    path,
                    with: .color(color.opacity(isEnabled ? 1 : 0.45)),
                    style: StrokeStyle(
                        lineWidth: isActive ? 2.1 : 1.25,
                        lineCap: .round
                    )
                )
            }
        }
    }
}

private struct DAWKnobStepRail: View {
    let isActive: Bool
    let isEnabled: Bool

    var body: some View {
        let color = isActive ? Color.cyan : Color.secondary.opacity(0.55)

        ZStack {
            Capsule()
                .fill(color)
                .frame(width: isActive ? 2 : 1.25)
                .padding(.vertical, 4)

            VStack(spacing: 0) {
                Circle()
                    .fill(isActive ? color : Color.clear)
                    .stroke(color, lineWidth: 1.25)
                    .frame(width: 6, height: 6)
                Spacer(minLength: 0)
                Circle()
                    .fill(isActive ? color : Color.clear)
                    .stroke(color, lineWidth: 1.25)
                    .frame(width: 6, height: 6)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct PressTrackingPlainButtonStyle: ButtonStyle {
    let onPressingChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressingChanged(isPressed)
            }
    }
}
