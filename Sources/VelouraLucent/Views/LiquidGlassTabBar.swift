import SwiftUI

struct LiquidGlassTabBar<Selection: Hashable>: View {
    let title: String
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String
    var maxWidth: CGFloat = 360
    var isDisabled = false

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
    private func tabButton(for option: Selection) -> some View {
        let isSelected = option == selection

        if isSelected {
            Button {
                selection = option
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
                selection = option
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
            .modifier(SelectedGlassTabModifier(isSelected: isSelected, namespace: glassNamespace))
            .accessibilityLabel("\(title)、\(label(option))")
    }
}

private struct SelectedGlassTabModifier: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if isSelected {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("selected-tab", in: namespace)
        } else {
            content
        }
    }
}
