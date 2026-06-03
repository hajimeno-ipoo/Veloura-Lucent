import Foundation

enum AudioAnalysisMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case auto
    case cpu
    case experimentalMetal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "自動"
        case .cpu:
            return "安定CPU"
        case .experimentalMetal:
            return "実験Metal"
        }
    }

    var summary: String {
        switch self {
        case .auto:
            return MetalAudioAnalysisProcessor().isAvailable
                ? "このMacでは高速なMetal解析を使います"
                : "Metal解析を使えないためCPU解析を使います"
        case .cpu:
            return "安定した解析を使います"
        case .experimentalMetal:
            return MetalAudioAnalysisProcessor().isAvailable
                ? "解析の一部をMetalで高速化します"
                : "このMacではMetal解析を使えないためCPUへ戻ります"
        }
    }

    var resolvedMode: AudioAnalysisMode {
        switch self {
        case .auto:
            return MetalAudioAnalysisProcessor().isAvailable ? .experimentalMetal : .cpu
        case .experimentalMetal:
            return MetalAudioAnalysisProcessor().isAvailable ? .experimentalMetal : .cpu
        case .cpu:
            return .cpu
        }
    }

    var resolvedSummary: String {
        let resolved = resolvedMode
        if self == resolved {
            return "使用中: \(resolved.title)"
        }
        return "使用中: \(resolved.title)（\(title)から自動切替）"
    }

    var logDescription: String {
        let resolved = resolvedMode
        if self == resolved {
            return "解析モード: \(resolved.title)"
        }
        return "解析モード: \(title) -> \(resolved.title)"
    }
}
