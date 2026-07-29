import SwiftUI

struct ProcessingLogSection: Identifiable {
    let id: String
    let title: String
    let lines: [String]
    let placeholder: String
}

struct ProcessingLogView: View {
    let sections: [ProcessingLogSection]

    init(
        correctionLines: [String],
        remixLines: [String]? = nil,
        masteringLines: [String]
    ) {
        var sections = [
            ProcessingLogSection(
                id: "correction",
                title: "補正ログ",
                lines: correctionLines,
                placeholder: "ここに補正ログが表示されます。"
            ),
        ]
        if let remixLines {
            sections.append(ProcessingLogSection(
                id: "remix",
                title: "再ミックスログ",
                lines: remixLines,
                placeholder: "ここに再ミックスログが表示されます。"
            ))
        }
        sections.append(ProcessingLogSection(
            id: "mastering",
            title: "マスタリングログ",
            lines: masteringLines,
            placeholder: "ここにマスタリングログが表示されます。"
        ))
        self.sections = sections
    }

    init(sections: [ProcessingLogSection]) {
        self.sections = sections
    }

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top),
                count: sections.count
            ),
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(sections) { section in
                logCard(
                    title: section.title,
                    lines: section.lines,
                    placeholder: section.placeholder
                )
            }
        }
    }

    private func logCard(title: String, lines: [String], placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Group {
                if lines.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.callout.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

}
