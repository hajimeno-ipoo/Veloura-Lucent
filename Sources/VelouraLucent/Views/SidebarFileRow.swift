import SwiftUI

struct SidebarFileRow: View {
    let title: String
    let systemImage: String
    let fileURL: URL?
    let fileInfo: AudioFileInfo?
    let placeholder: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(fileURL == nil ? Color.secondary : tint)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.bold())
                Text(fileURL?.lastPathComponent ?? placeholder)
                    .font(.callout)
                    .foregroundStyle(fileURL == nil ? .secondary : .primary)
                    .lineLimit(fileURL == nil ? 2 : 1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: fileURL == nil)

                if let fileURL {
                    Text(fileURL.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                if let fileInfo {
                    HStack(spacing: 4) {
                        Text(fileInfo.technicalSummary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("/")
                            .foregroundStyle(.tertiary)
                        Text(fileInfo.durationText)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .help(helpText)
        .accessibilityElement(children: .combine)
    }

    private var helpText: String {
        guard let fileURL else {
            return placeholder
        }
        if let fileInfo {
            return "\(fileURL.path(percentEncoded: false))\n\(fileInfo.technicalSummary) / \(fileInfo.durationText)"
        }
        return fileURL.path(percentEncoded: false)
    }
}
