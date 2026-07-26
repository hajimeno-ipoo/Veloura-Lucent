import SwiftUI

struct LiquidGlassToolbarLabel: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let effectID: String
    let namespace: Namespace.ID
    let reduceMotion: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.callout)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassCapsuleMorphSurface(
                isActive: isActive,
                effectID: effectID,
                namespace: namespace,
                reduceMotion: reduceMotion
            )
    }
}
