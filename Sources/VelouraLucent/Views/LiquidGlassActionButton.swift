import SwiftUI

struct LiquidGlassActionButton: View {
    enum Layout {
        case compact
        case inspectorWide
    }

    let title: String
    var systemImage: String?
    var isDisabled = false
    var layout: Layout = .compact
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @Namespace private var glassNamespace

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover(perform: updateHover)
    }

    @ViewBuilder
    private var label: some View {
        switch layout {
        case .compact:
            labelContent
                .liquidGlassCompactActionLabel()
        case .inspectorWide:
            GlassEffectContainer(spacing: 0) {
                labelContent
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
                    .liquidGlassCapsuleMorphSurface(
                        isActive: isHovering && isEnabled && !isDisabled,
                        effectID: "hover-liquid-glass-inspector-action",
                        namespace: glassNamespace,
                        reduceMotion: reduceMotion
                    )
                    .contentShape(Capsule())
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .velouraAdaptiveGlass(in: .capsule, interactive: true)
            .contentShape(Capsule())
        }
    }

    @ViewBuilder
    private var labelContent: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        } else {
            Text(title)
        }
    }

    @MainActor
    private func updateHover(_ hovering: Bool) {
        let nextValue = layout == .inspectorWide && isEnabled && !isDisabled && hovering
        guard isHovering != nextValue else { return }

        LiquidGlassMotion.perform(
            reduceMotion: reduceMotion,
            animation: LiquidGlassMotion.selection
        ) {
            isHovering = nextValue
        }
    }
}

private extension View {
    func liquidGlassCompactActionLabel() -> some View {
        self
            .font(.callout)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .velouraAdaptiveGlass(in: .capsule, interactive: true)
            .contentShape(Capsule())
    }
}
