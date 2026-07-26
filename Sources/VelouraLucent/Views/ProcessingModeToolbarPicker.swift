import SwiftUI

struct ProcessingModeToolbarPicker: View {
    @Binding var selection: ProcessingMode
    let isDisabled: Bool

    var body: some View {
        LiquidGlassSegmentedPicker(
            title: "処理モード",
            options: ProcessingMode.allCases,
            selection: $selection,
            label: \.title,
            maxWidth: 220,
            isDisabled: isDisabled
        )
        .frame(width: 220)
        .accessibilityLabel("処理モード")
        .accessibilityHint(
            isDisabled
                ? "現在の処理が完了してから切り替えられます"
                : "通常補正とStem Modeを切り替えます"
        )
    }
}
