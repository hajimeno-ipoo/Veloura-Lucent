import SwiftUI

struct LiquidGlassTabBar<Selection: Hashable>: View {
    let title: String
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String
    var maxWidth: CGFloat = 360
    var isDisabled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedOption: Selection?
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    tabButton(for: option)
                }
            }
            .padding(4)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .velouraAdaptiveGlass(in: .capsule, interactive: true)
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
    private func tabButton(for option: Selection) -> some View {
        let isSelected = option == selection

        if isSelected {
            Button {
                select(option)
            } label: {
                tabLabel(for: option, isSelected: true)
            }
            .buttonStyle(.plain)
            .focused($focusedOption, equals: option)
            .frame(maxWidth: .infinity)
            .accessibilityValue("選択中")
            .accessibilityAddTraits(.isSelected)
        } else {
            Button {
                select(option)
            } label: {
                tabLabel(for: option, isSelected: false)
            }
            .buttonStyle(.plain)
            .focused($focusedOption, equals: option)
            .frame(maxWidth: .infinity)
            .accessibilityValue("未選択")
        }
    }

    @ViewBuilder
    private func tabLabel(for option: Selection, isSelected: Bool) -> some View {
        Text(label(option))
            .font(.callout)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 12)
            .contentShape(Capsule())
            .modifier(
                SelectedGlassTabModifier(
                    isSelected: isSelected,
                    namespace: glassNamespace,
                    reduceMotion: reduceMotion
                )
            )
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
}

private struct SelectedGlassTabModifier: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content
                .velouraAdaptiveGlass(in: .capsule, interactive: true)
                .glassEffectID("selected-tab", in: namespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else {
            content
        }
    }
}
