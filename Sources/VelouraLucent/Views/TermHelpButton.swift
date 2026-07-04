import SwiftUI

struct TermHelpButton: View {
    let title: String
    let reading: String
    let description: String
    @State private var isPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        Button {
            LiquidGlassMotion.perform(
                reduceMotion: reduceMotion,
                animation: LiquidGlassMotion.panel
            ) {
                isPresented.toggle()
            }
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .glassEffect(.clear.interactive(), in: Circle())
                .liquidGlassEffectID("term-help", in: glassNamespace, isActive: !isPresented)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)の説明")
        .help("\(title)の説明を表示します")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(reading)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(description)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 360, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .glassEffectID("term-help", in: glassNamespace)
            .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        }
    }
}
