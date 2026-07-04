import SwiftUI

struct LiquidGlassSegmentedControl<Selection: Hashable>: View {
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
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    segmentButton(for: option)
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
    private func segmentButton(for option: Selection) -> some View {
        let isSelected = option == selection

        if isSelected {
            Button {
                select(option)
            } label: {
                segmentLabel(for: option, isSelected: true)
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
                segmentLabel(for: option, isSelected: false)
            }
            .buttonStyle(.plain)
            .focused($focusedOption, equals: option)
            .frame(maxWidth: .infinity)
            .accessibilityValue("未選択")
        }
    }

    private func segmentLabel(for option: Selection, isSelected: Bool) -> some View {
        Text(label(option))
            .font(.callout)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Capsule())
            .modifier(
                SelectedGlassSegmentModifier(
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

private struct SelectedGlassSegmentModifier: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content
                .glassEffect(.clear.interactive(), in: .capsule)
                .glassEffectID("selected-segment", in: namespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else {
            content
        }
    }
}
