import SwiftUI

struct LiquidGlassSegmentedControl<Selection: Hashable>: View {
    let title: String
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String
    var maxWidth: CGFloat = 360
    var isDisabled = false
    @FocusState private var focusedOption: Selection?

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    segmentButton(for: option)
                }
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
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
                selection = option
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
                selection = option
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
            .glassEffect(.clear.interactive(), in: .capsule)
            .accessibilityLabel("\(title)、\(label(option))")
    }
}
