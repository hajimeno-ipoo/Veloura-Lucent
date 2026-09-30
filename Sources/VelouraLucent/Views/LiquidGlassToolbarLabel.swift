import SwiftUI

struct LiquidGlassToolbarLabel: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var isCancellation = false
    let effectID: String
    let namespace: Namespace.ID
    let reduceMotion: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        if isCancellation {
            toolbarLabel
                .foregroundStyle(.red)
        } else {
            toolbarLabel
        }
    }

    private var toolbarLabel: some View {
        Label(AppLanguageSettings.string(title), systemImage: systemImage)
            .environment(\.locale, locale)
            .labelStyle(.titleAndIcon)
            .font(.body)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .liquidGlassCapsuleMorphSurface(
                isActive: isActive,
                effectID: effectID,
                namespace: namespace,
                reduceMotion: reduceMotion
            )
    }
}
