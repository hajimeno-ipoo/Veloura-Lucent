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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var dragStartValue: Float?
    @State private var isActivelyInteracting = false
    @State private var keyRepeatTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            knobSurface
            overlayLabels
            stepButtons
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
        dragValueScale: Float = 1
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
    }

    private var knobSurface: some View {
        ZStack(alignment: .topLeading) {
            fullArtworkImage(DAWKnobMetrics.fixedArtworkImage)
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
            overlayText(
                displayValueText ?? valueText,
                font: .system(size: 15, weight: .semibold, design: .rounded).monospacedDigit(),
                at: DAWKnobMetrics.valueCenter,
                width: DAWKnobMetrics.valueTextWidth
            )
                .foregroundStyle(.primary)

            if let unitText {
                overlayText(
                    unitText,
                    font: .system(size: 11, weight: .semibold, design: .rounded),
                    at: DAWKnobMetrics.unitCenter,
                    width: DAWKnobMetrics.unitTextWidth(for: unitText)
                )
                    .foregroundStyle(.secondary)
            }

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
            .position(scaled(DAWKnobMetrics.titleCenter))
        }
    }

    private var stepButtons: some View {
        ZStack(alignment: .topLeading) {
            transparentStepButton(
                label: "\(title)を下げる",
                center: DAWKnobMetrics.minusButtonCenter,
                size: DAWKnobMetrics.stepButtonSize,
                delta: -step
            )
            transparentStepButton(
                label: "\(title)を上げる",
                center: DAWKnobMetrics.plusButtonCenter,
                size: DAWKnobMetrics.stepButtonSize,
                delta: step
            )
        }
        .frame(width: DAWKnobMetrics.controlWidth, height: DAWKnobMetrics.controlHeight)
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
            .frame(width: width * DAWKnobMetrics.artworkScale)
            .position(scaled(point))
            .accessibilityHidden(true)
    }

    private func transparentStepButton(
        label: String,
        center: CGPoint,
        size: CGSize,
        delta: Float
    ) -> some View {
        Button {
            adjust(by: delta, animated: true)
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(
            PressTrackingPlainButtonStyle { isPressed in
                isActivelyInteracting = isPressed
            }
        )
        .frame(
            width: DAWKnobMetrics.stepButtonHitSize.width,
            height: DAWKnobMetrics.stepButtonHitSize.height
        )
        .position(scaled(center))
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

    private func scaled(_ point: CGPoint) -> CGPoint {
        DAWKnobMetrics.scaledPoint(point)
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
