import SwiftUI

struct DisclosureToggleButton: View {
    let title: String
    let isExpanded: Bool
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentShape(.circle)
                .glassEffect(.clear.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "開いています" : "閉じています")
        .accessibilityHint(accessibilityHint)
    }
}
