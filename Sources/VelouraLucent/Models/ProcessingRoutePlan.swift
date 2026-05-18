import Foundation

enum ProcessingRouteAction: String, Sendable, Equatable {
    case run
    case light
    case skip

    var logTitle: String {
        switch self {
        case .run: "実行"
        case .light: "軽量"
        case .skip: "スキップ"
        }
    }
}

enum ProcessingRouteRiskLevel: Sendable, Equatable {
    case low
    case medium
    case high
}

struct ProcessingRouteDecision: Sendable, Equatable {
    let action: ProcessingRouteAction
    let reason: String
    let riskLevel: ProcessingRouteRiskLevel
}

enum CorrectionRouteStep: CaseIterable, Sendable, Hashable {
    case lowNoiseCleanup
    case denoise
    case sibilanceShimmerGuard
    case harmonicRepair
    case repairShimmerGuard
    case lowMidResidueGuard
    case shimmerPeakLimit
    case peakSafety

    var logName: String {
        switch self {
        case .lowNoiseCleanup: "低域整理"
        case .denoise: "ノイズ除去"
        case .sibilanceShimmerGuard: "サ行保護"
        case .harmonicRepair: "高域修復"
        case .repairShimmerGuard: "修復後シマー保護"
        case .lowMidResidueGuard: "低中域整理"
        case .shimmerPeakLimit: "シマー制限"
        case .peakSafety: "ピーク保護"
        }
    }

    var processingStep: ProcessingStep {
        switch self {
        case .lowNoiseCleanup: .lowNoiseCleanup
        case .denoise: .denoise
        case .sibilanceShimmerGuard: .sibilanceShimmerGuard
        case .harmonicRepair: .harmonicRepair
        case .repairShimmerGuard: .repairShimmerGuard
        case .lowMidResidueGuard: .lowMidResidueGuard
        case .shimmerPeakLimit: .shimmerPeakLimit
        case .peakSafety: .peakSafety
        }
    }
}

struct CorrectionRoutePlan: Sendable, Equatable {
    let decisions: [CorrectionRouteStep: ProcessingRouteDecision]

    func decision(for step: CorrectionRouteStep) -> ProcessingRouteDecision {
        decisions[step] ?? ProcessingRouteDecision(
            action: .run,
            reason: "判定がないため安全側で実行",
            riskLevel: .medium
        )
    }

    var runLikeCount: Int {
        decisions.values.filter { $0.action != .skip }.count
    }

    static func make(
        analysis: AnalysisData,
        noiseMeasurements: NoiseMeasurementSnapshot?
    ) -> CorrectionRoutePlan {
        let rumble = noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.rumble)
        let hum = noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.hum)
        let hiss = noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.hiss)
        let shimmer = noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.shimmer)
        let mud = noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.mud)
        let sibilance = noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.sibilance)

        let lowNoiseIsQuiet = rumble.map { $0 < InternalAudioJudgementPolicy.routeLowNoiseQuietRumbleDB } == true
            && hum.map { $0 < InternalAudioJudgementPolicy.routeLowNoiseQuietHumDB } == true
        let highNoiseIsQuiet = hiss.map { $0 < InternalAudioJudgementPolicy.routeHighNoiseQuietHissDB } == true
            && shimmer.map { $0 < InternalAudioJudgementPolicy.routeHighNoiseQuietShimmerDB } == true
            && !analysis.hasShimmer
        let highNoiseNeedsCare = (hiss.map { $0 > InternalAudioJudgementPolicy.routeHighNoiseCareHissDB } ?? true)
            || (shimmer.map { $0 > InternalAudioJudgementPolicy.routeHighNoiseCareShimmerDB } ?? true)
            || analysis.hasShimmer
        let lowMidIsClean = mud.map { $0 < InternalAudioJudgementPolicy.routeLowMidCleanMudDB } == true
        let sibilanceIsLow = sibilance.map { $0 < InternalAudioJudgementPolicy.routeSibilanceLowDB } == true
            && analysis.shimmerRatio < InternalAudioJudgementPolicy.routeShimmerRatioLow
        let repairRiskIsLow = analysis.shimmerRatio < InternalAudioJudgementPolicy.routeRepairShimmerRatioLow
            && analysis.artifactBandRatio < InternalAudioJudgementPolicy.routeRepairArtifactRatioLow

        var decisions: [CorrectionRouteStep: ProcessingRouteDecision] = [
            .lowNoiseCleanup: lowNoiseIsQuiet
                ? ProcessingRouteDecision(action: .skip, reason: "低域ノイズとハムが少ない", riskLevel: .low)
                : ProcessingRouteDecision(action: .run, reason: "低域ノイズまたはハムの確認が必要", riskLevel: .medium),
            .denoise: ProcessingRouteDecision(action: .run, reason: "ノイズ除去本体は音質の土台になる", riskLevel: .high),
            .sibilanceShimmerGuard: sibilanceIsLow
                ? ProcessingRouteDecision(action: .light, reason: "サ行とシマーが少ないため保護を軽くする", riskLevel: .medium)
                : ProcessingRouteDecision(action: .run, reason: "サ行またはシマーの保護が必要", riskLevel: .medium),
            .harmonicRepair: ProcessingRouteDecision(action: .run, reason: "高域補修は仕上がり差が大きい", riskLevel: .high),
            .repairShimmerGuard: repairRiskIsLow
                ? ProcessingRouteDecision(action: .skip, reason: "高域補修後のシマー危険が低い", riskLevel: .low)
                : ProcessingRouteDecision(action: .run, reason: "高域補修後のシマー確認が必要", riskLevel: .medium),
            .lowMidResidueGuard: lowMidIsClean
                ? ProcessingRouteDecision(action: .skip, reason: "低中域の残りノイズが少ない", riskLevel: .low)
                : ProcessingRouteDecision(action: .run, reason: "低中域の残りノイズを整える必要がある", riskLevel: .medium),
            .shimmerPeakLimit: highNoiseIsQuiet
                ? ProcessingRouteDecision(action: .skip, reason: "ヒスとシマーが少ない", riskLevel: .low)
                : ProcessingRouteDecision(
                    action: highNoiseNeedsCare ? .run : .light,
                    reason: highNoiseNeedsCare ? "高域ノイズの戻りを抑える必要がある" : "高域ノイズは注意域のため軽く抑える",
                    riskLevel: .medium
                ),
            .peakSafety: ProcessingRouteDecision(action: .run, reason: "ピーク保護は安全工程", riskLevel: .high)
        ]

        for step in CorrectionRouteStep.allCases where decisions[step] == nil {
            decisions[step] = ProcessingRouteDecision(action: .run, reason: "未分類を避けるため実行", riskLevel: .medium)
        }
        return CorrectionRoutePlan(decisions: decisions)
    }
}

enum MasteringRouteStep: CaseIterable, Sendable, Hashable {
    case tone
    case deEss
    case dynamics
    case saturate
    case air
    case stereo
    case loudness
    case highReturnGuard
    case noiseReturnGuard

    var logName: String {
        switch self {
        case .tone: "音色"
        case .deEss: "ディエッサー"
        case .dynamics: "ダイナミクス"
        case .saturate: "倍音"
        case .air: "空気感"
        case .stereo: "ステレオ幅"
        case .loudness: "ラウドネス"
        case .highReturnGuard: "高域戻りガード"
        case .noiseReturnGuard: "ノイズ戻りガード"
        }
    }

    var masteringStep: MasteringStep {
        switch self {
        case .tone: .tone
        case .deEss: .deEss
        case .dynamics: .dynamics
        case .saturate: .saturate
        case .air: .air
        case .stereo: .stereo
        case .loudness: .loudness
        case .highReturnGuard: .highReturnGuard
        case .noiseReturnGuard: .noiseReturnGuard
        }
    }
}

struct MasteringRoutePlan: Sendable, Equatable {
    let decisions: [MasteringRouteStep: ProcessingRouteDecision]

    func decision(for step: MasteringRouteStep) -> ProcessingRouteDecision {
        decisions[step] ?? ProcessingRouteDecision(
            action: .run,
            reason: "判定がないため安全側で実行",
            riskLevel: .medium
        )
    }

    var runLikeCount: Int {
        decisions.values.filter { $0.action != .skip }.count
    }

    static func make(
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        noiseMeasurements: NoiseMeasurementSnapshot?
    ) -> MasteringRoutePlan {
        let hiss = noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.hiss)
        let sibilance = noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.sibilance)
        let shimmer = noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.shimmer)
        let deEssIsUnneeded = analysis.harshnessScore < InternalAudioJudgementPolicy.masteringDeEssHarshnessLow
            && sibilance.map { $0 < InternalAudioJudgementPolicy.masteringSibilanceLowDB } == true
        let saturationIsOff = settings.saturationAmount < InternalAudioJudgementPolicy.masteringSaturationOffAmount
        let airIsEnough = analysis.highBandLevelDB >= analysis.midBandLevelDB + InternalAudioJudgementPolicy.masteringAirEnoughHighToMidGapDB
            && settings.highShelfGain < InternalAudioJudgementPolicy.masteringAirLowShelfGain
        let stereoIsClose = abs(settings.stereoWidth - analysis.stereoWidth) < InternalAudioJudgementPolicy.masteringStereoCloseTolerance
        let highReturnNeedsGuard = analysis.harshnessScore >= 0.62
            && (
                settings.highShelfGain >= 0.56
                    || shimmer.map { $0 >= InternalAudioJudgementPolicy.masteringHighReturnShimmerLowDB } == true
            )
        let noiseReturnLooksClean = hiss.map { $0 < InternalAudioJudgementPolicy.masteringNoiseCleanHissDB } == true
            && sibilance.map { $0 < InternalAudioJudgementPolicy.masteringSibilanceLowDB } == true
            && shimmer.map { $0 < InternalAudioJudgementPolicy.masteringNoiseCleanShimmerDB } == true

        var decisions: [MasteringRouteStep: ProcessingRouteDecision] = [
            .tone: ProcessingRouteDecision(action: .run, reason: "帯域バランスは仕上げの土台", riskLevel: .high),
            .deEss: deEssIsUnneeded
                ? ProcessingRouteDecision(action: .skip, reason: "刺さりとサ行ノイズが低い", riskLevel: .low)
                : ProcessingRouteDecision(action: .run, reason: "刺さりまたはサ行ノイズを抑える必要がある", riskLevel: .medium),
            .dynamics: ProcessingRouteDecision(action: .run, reason: "音圧と密度に直結する", riskLevel: .high),
            .saturate: saturationIsOff
                ? ProcessingRouteDecision(action: .skip, reason: "倍音設定がほぼゼロ", riskLevel: .low)
                : ProcessingRouteDecision(action: .run, reason: "倍音設定が有効", riskLevel: .medium),
            .air: airIsEnough
                ? ProcessingRouteDecision(action: .skip, reason: "高域が十分あり、持ち上げ設定も弱い", riskLevel: .low)
                : ProcessingRouteDecision(action: .run, reason: "空気感の補正が必要", riskLevel: .medium),
            .stereo: stereoIsClose
                ? ProcessingRouteDecision(action: .skip, reason: "現在の広がりが目標に近い", riskLevel: .low)
                : ProcessingRouteDecision(action: .run, reason: "ステレオ幅を目標へ近づける", riskLevel: .medium),
            .loudness: ProcessingRouteDecision(action: .run, reason: "最終音量は必須工程", riskLevel: .high),
            .highReturnGuard: highReturnNeedsGuard
                ? ProcessingRouteDecision(action: .run, reason: "刺さりと高域戻りが同時に強い", riskLevel: .medium)
                : ProcessingRouteDecision(action: .skip, reason: "高域戻りガードを通常マスタリングでは使わない", riskLevel: .low),
            .noiseReturnGuard: noiseReturnLooksClean
                ? ProcessingRouteDecision(action: .light, reason: "入口測定で問題なければ早期終了する", riskLevel: .medium)
                : ProcessingRouteDecision(action: .run, reason: "ノイズ戻りを通常確認する", riskLevel: .medium)
        ]

        for step in MasteringRouteStep.allCases where decisions[step] == nil {
            decisions[step] = ProcessingRouteDecision(action: .run, reason: "未分類を避けるため実行", riskLevel: .medium)
        }
        return MasteringRoutePlan(decisions: decisions)
    }
}
