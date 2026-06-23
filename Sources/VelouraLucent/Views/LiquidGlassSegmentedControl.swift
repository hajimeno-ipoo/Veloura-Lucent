import SwiftUI

struct LiquidGlassSegmentedControl<Selection: Hashable>: View {
    let title: String
    let options: [Selection]
    @Binding var selection: Selection
    let label: (Selection) -> String
    var maxWidth: CGFloat = 360
    var isDisabled = false

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
                segmentLabel(for: option)
            }
            .buttonStyle(.glassProminent)
            .frame(maxWidth: .infinity)
            .accessibilityValue("選択中")
            .accessibilityAddTraits(.isSelected)
        } else {
            Button {
                selection = option
            } label: {
                segmentLabel(for: option)
            }
            .buttonStyle(.glass)
            .frame(maxWidth: .infinity)
            .accessibilityValue("未選択")
        }
    }

    private func segmentLabel(for option: Selection) -> some View {
        Text(label(option))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(title)、\(label(option))")
    }
}
