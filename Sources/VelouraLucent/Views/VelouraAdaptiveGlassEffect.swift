import SwiftUI

private struct VelouraFullScreenEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var velouraIsFullScreen: Bool {
        get { self[VelouraFullScreenEnvironmentKey.self] }
        set { self[VelouraFullScreenEnvironmentKey.self] = newValue }
    }
}

private struct VelouraAdaptiveGlassEffectModifier<EffectShape: Shape>: ViewModifier {
    @Environment(\.velouraIsFullScreen) private var isFullScreen

    let shape: EffectShape
    let isInteractive: Bool
    let tint: Color?
    let requestedGlass: Glass?

    func body(content: Content) -> some View {
        let baseGlass: Glass = requestedGlass ?? (isFullScreen ? .regular : .clear)
        let tintedGlass = tint.map { baseGlass.tint($0) } ?? baseGlass
        let glass = isInteractive ? tintedGlass.interactive() : tintedGlass

        content.glassEffect(glass, in: shape)
    }
}

extension View {
    func velouraAdaptiveGlass<EffectShape: Shape>(
        in shape: EffectShape,
        interactive: Bool = false,
        tint: Color? = nil,
        glass: Glass? = nil
    ) -> some View {
        modifier(
            VelouraAdaptiveGlassEffectModifier(
                shape: shape,
                isInteractive: interactive,
                tint: tint,
                requestedGlass: glass
            )
        )
    }
}
