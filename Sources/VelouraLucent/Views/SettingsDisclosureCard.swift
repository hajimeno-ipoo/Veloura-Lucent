import SwiftUI

struct SettingsDisclosureCard<Content: View>: View {
    let title: String
    let summary: String
    let help: SettingHelp?
    @State private var isExpanded: Bool
    @ViewBuilder let content: Content

    init(
        title: String,
        summary: String,
        help: SettingHelp?,
        initiallyExpanded: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.help = help
        self._isExpanded = State(initialValue: initiallyExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    content
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.clear)
                .glassEffect(.clear, in: .rect(cornerRadius: 14))
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            disclosureButton

            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)

            if let help {
                TermHelpButton(title: help.title, reading: help.reading, description: help.description)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, isExpanded ? 0 : 12)
    }

    private var disclosureButton: some View {
        Button(action: toggleExpanded) {
            Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "開いています" : "閉じています")
        .accessibilityHint("設定項目を開閉します")
    }

    private func toggleExpanded() {
        isExpanded.toggle()
    }
}
