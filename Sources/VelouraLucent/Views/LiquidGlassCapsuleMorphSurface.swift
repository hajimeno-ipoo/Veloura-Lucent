import SwiftUI

struct LiquidGlassCapsuleMorphSurface: ViewModifier {
    let isActive: Bool
    let effectID: String
    let namespace: Namespace.ID
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .glassEffect(.clear.interactive(), in: .capsule)
                .glassEffectID(effectID, in: namespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else {
            content
        }
    }
}

extension View {
    func liquidGlassCapsuleMorphSurface(
        isActive: Bool,
        effectID: String,
        namespace: Namespace.ID,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            LiquidGlassCapsuleMorphSurface(
                isActive: isActive,
                effectID: effectID,
                namespace: namespace,
                reduceMotion: reduceMotion
            )
        )
    }
}
