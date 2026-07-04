import SwiftUI

struct LiquidGlassSegmentedPicker<Selection: Hashable>: View {
    let title: String
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String
    var maxWidth: CGFloat = 360
    var isDisabled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredOption: Selection?
    @FocusState private var focusedOption: Selection?
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    optionButton(for: option)
                }
            }
            .padding(4)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .glassEffect(.clear.interactive(), in: .capsule)
        }
        .disabled(isDisabled)
        .defaultFocus($focusedOption, nil)
        .task {
            await Task.yield()
            focusedOption = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func optionButton(for option: Selection) -> some View {
        let isSelected = option == selection

        Button {
            select(option)
        } label: {
            optionLabel(for: option, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { updateHover(option, isHovering: $0) }
        .focused($focusedOption, equals: option)
        .frame(maxWidth: .infinity)
        .accessibilityValue(isSelected ? "選択中" : "未選択")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func optionLabel(for option: Selection, isSelected: Bool) -> some View {
        Text(label(option))
            .font(.callout)
            .foregroundStyle(isSelected ? LiquidGlassSegmentedPickerStyle.selectedText : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 32)
            .modifier(
                SelectedLiquidGlassSegmentModifier(
                    isSelected: isSelected,
                    namespace: glassNamespace,
                    reduceMotion: reduceMotion
                )
            )
            .liquidGlassCapsuleMorphSurface(
                isActive: hoveredOption == option && !isSelected,
                effectID: "hover-liquid-glass-segment",
                namespace: glassNamespace,
                reduceMotion: reduceMotion
            )
            .contentShape(Capsule())
            .accessibilityLabel("\(title)、\(label(option))")
    }

    @MainActor
    private func select(_ option: Selection) {
        guard option != selection else { return }
        LiquidGlassMotion.perform(
            reduceMotion: reduceMotion,
            animation: LiquidGlassMotion.selection
        ) {
            selection = option
        }
    }

    @MainActor
    private func updateHover(_ option: Selection, isHovering: Bool) {
        let nextOption: Selection?
        if isDisabled {
            nextOption = nil
        } else if isHovering {
            nextOption = option
        } else {
            nextOption = hoveredOption == option ? nil : hoveredOption
        }

        guard hoveredOption != nextOption else { return }
        LiquidGlassMotion.perform(
            reduceMotion: reduceMotion,
            animation: LiquidGlassMotion.selection
        ) {
            hoveredOption = nextOption
        }
    }
}

enum LiquidGlassSegmentedPickerStyle {
    static let selectedTint = Color(red: 222 / 255, green: 209 / 255, blue: 254 / 255)
    static let sliderTint = selectedTint.opacity(0.65)
    static let switchTint = Color(red: 236 / 255, green: 229 / 255, blue: 251 / 255)
    static let selectedText = Color(red: 111 / 255, green: 85 / 255, blue: 200 / 255)
}

private struct SelectedLiquidGlassSegmentModifier: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content
                .glassEffect(.clear.tint(LiquidGlassSegmentedPickerStyle.selectedTint.opacity(0.30)).interactive(), in: .capsule)
                .glassEffectID("selected-liquid-glass-segment", in: namespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else {
            content
        }
    }
}
