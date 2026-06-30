import SwiftUI

enum InputAudioDropOverlayKind {
    case accepted
    case rejected

    var systemImage: String {
        switch self {
        case .accepted:
            "waveform.badge.plus"
        case .rejected:
            "exclamationmark.triangle"
        }
    }

    var title: String {
        switch self {
        case .accepted:
            "音声ファイルをドロップ"
        case .rejected:
            "音声ファイルではありません"
        }
    }

    var message: String {
        switch self {
        case .accepted:
            "中央画面に入力音声を読み込みます"
        case .rejected:
            "WAV、MP3、M4Aなどの音声ファイルをドロップしてください"
        }
    }

    var tint: Color {
        switch self {
        case .accepted:
            .accentColor
        case .rejected:
            .orange
        }
    }

    var borderOpacity: Double {
        switch self {
        case .accepted:
            0.16
        case .rejected:
            0.24
        }
    }
}

struct InputAudioDropOverlay: View {
    let kind: InputAudioDropOverlayKind

    init(kind: InputAudioDropOverlayKind = .accepted) {
        self.kind = kind
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
                .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 24))

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(kind.tint.opacity(kind.borderOpacity), lineWidth: 1.2)

            VStack(spacing: 14) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 52, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(kind.tint)

                Text(kind.title)
                    .font(.title2.weight(.semibold))

                Text(kind.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.title)
    }
}
