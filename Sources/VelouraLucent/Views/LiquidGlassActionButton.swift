import SwiftUI

struct LiquidGlassActionButton: View {
    let title: String
    var systemImage: String?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .liquidGlassActionLabel()
        } else {
            Text(title)
                .liquidGlassActionLabel()
        }
    }
}

private extension View {
    func liquidGlassActionLabel() -> some View {
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
