import Foundation

enum AudioQualityAssessmentSeverity: Int, Sendable, Comparable {
    case normal
    case caution
    case warning

    static func < (lhs: AudioQualityAssessmentSeverity, rhs: AudioQualityAssessmentSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AudioQualityChangeDirection: Sendable {
    case both
    case increaseOnly
}

struct AudioQualityBandRule: Sendable {
    let id: String
    let label: String
    let range: String
    let cautionDB: Double
    let warningDB: Double
    let direction: AudioQualityChangeDirection
}

/// 詳細解析、右側の品質確認、完了後レポートで共有する帯域差と判定境界です。
enum AudioQualityAssessmentService {
    static let reportBandRules: [AudioQualityBandRule] = [
        AudioQualityBandRule(
            id: "sparkle",
            label: "煌びやかさ",
            range: "8〜12kHz",
            cautionDB: 2.0,
            warningDB: 4.0,
            direction: .both
        ),
        AudioQualityBandRule(
            id: "air",
            label: "空気感",
            range: "12〜16kHz",
            cautionDB: 2.0,
            warningDB: 4.0,
            direction: .both
        ),
        AudioQualityBandRule(
            id: "ultraAir",
            label: "超高域",
            range: "16〜20kHz",
            cautionDB: 2.5,
            warningDB: 5.0,
            direction: .both
        ),
        AudioQualityBandRule(
            id: "generatedUltraHigh",
            label: "生成超高域",
            range: "21〜24kHz",
            cautionDB: 1.0,
            warningDB: 2.0,
            direction: .increaseOnly
        )
    ]

    static let mudRule = AudioQualityBandRule(
        id: "mud",
        label: "こもり",
        range: "300Hz〜1kHz",
        cautionDB: 1.5,
        warningDB: 3.0,
        direction: .increaseOnly
    )

    static let lowBalanceRules: [AudioQualityBandRule] = [
        AudioQualityBandRule(
            id: "low",
            label: "低域",
            range: "20-180Hz",
            cautionDB: 1.5,
            warningDB: 3.0,
            direction: .both
        ),
        AudioQualityBandRule(
            id: "lowMid",
            label: "中低域",
            range: "180-500Hz",
            cautionDB: 1.5,
            warningDB: 3.0,
            direction: .both
        ),
    ]

    static func normalizedBandLevel(id: String, in metrics: AudioMetricSnapshot) -> Double? {
        guard let level = metrics.bandEnergies.first(where: { $0.id == id })?.levelDB else {
            return nil
        }
        return level - metrics.rmsDBFS
    }

    static func normalizedBandDelta(
        id: String,
        reference: AudioMetricSnapshot,
        target: AudioMetricSnapshot
    ) -> Double? {
        guard
            let referenceLevel = normalizedBandLevel(id: id, in: reference),
            let targetLevel = normalizedBandLevel(id: id, in: target)
        else {
            return nil
        }
        return targetLevel - referenceLevel
    }

    static func severity(
        for delta: Double,
        rule: AudioQualityBandRule
    ) -> AudioQualityAssessmentSeverity {
        let measuredChange: Double
        switch rule.direction {
        case .both:
            measuredChange = abs(delta)
        case .increaseOnly:
            measuredChange = delta
        }

        if measuredChange >= rule.warningDB {
            return .warning
        }
        if measuredChange >= rule.cautionDB {
            return .caution
        }
        return .normal
    }
}
