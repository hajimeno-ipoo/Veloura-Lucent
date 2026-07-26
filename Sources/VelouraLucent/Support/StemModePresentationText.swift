import Foundation

extension StemModelAssetKind {
    var stemModeDisplayTitle: String {
        switch self {
        case .modelWeights: "モデルweights"
        case .modelConfiguration: "モデル設定"
        case .metalLibrary: "MLX実行資産"
        }
    }
}

extension StemRole {
    var stemModeDisplayTitle: String {
        switch self {
        case .drums: "ドラム"
        case .bass: "ベース"
        case .other: "その他"
        case .vocals: "ボーカル"
        }
    }
}

extension StemArtifactKind {
    var stemModeDisplayTitle: String {
        switch self {
        case .input44100: "変換済み入力"
        case .rawStem(let role): "\(role.stemModeDisplayTitle)（raw）"
        case .correctedStem(let role): "\(role.stemModeDisplayTitle)（補正済み）"
        case .correctedRemix48000: "補正後再ミックス"
        case .finalMaster: "最終マスター"
        }
    }

    var stemModeSystemImage: String {
        switch self {
        case .input44100: "waveform"
        case .rawStem(.vocals), .correctedStem(.vocals): "music.mic"
        case .rawStem(.drums), .correctedStem(.drums): "metronome"
        case .rawStem(.bass), .correctedStem(.bass): "guitars"
        case .rawStem(.other), .correctedStem(.other): "waveform.path"
        case .correctedRemix48000: "waveform"
        case .finalMaster: "checkmark.seal"
        }
    }

    var isStemModeUserExportable: Bool {
        switch self {
        case .correctedStem,
             .correctedRemix48000,
             .finalMaster:
            true
        case .input44100,
             .rawStem:
            false
        }
    }

    /// 通常モードと同じA/B試聴の3段階だけを候補にします。
    /// 個別Stemや内部診断成果物は、品質選択へ転用しません。
    var isStemModePreviewable: Bool {
        switch self {
        case .input44100,
             .correctedRemix48000,
             .finalMaster:
            true
        case .rawStem,
             .correctedStem:
            false
        }
    }

    var stemModeExportSortRank: Int {
        switch self {
        case .correctedRemix48000: 0
        case .correctedStem(.drums): 10
        case .correctedStem(.bass): 11
        case .correctedStem(.other): 12
        case .correctedStem(.vocals): 13
        case .finalMaster: 20
        case .input44100: 100
        case .rawStem: 110
        }
    }

    /// 通常モードと同じ「入力・補正後・最終版」の順序です。
    var stemModePreviewSortRank: Int {
        switch self {
        case .input44100: 0
        case .correctedRemix48000: 10
        case .finalMaster: 20
        case .rawStem: 100
        case .correctedStem: 110
        }
    }
}

extension StemWorkflowState {
    var stemModeDisplayTitle: String {
        switch self {
        case .idle: "入力待ち"
        case .ready: "実行準備完了"
        case .readyForMastering: "補正完了・マスタリング待ち"
        case .running(let step): "\(step.title)を実行中"
        case .completed: "完了"
        case .failed: "停止"
        }
    }

    var stemModeSystemImage: String {
        switch self {
        case .idle: "circle"
        case .ready: "checkmark.circle"
        case .readyForMastering: "waveform.badge.checkmark"
        case .running: "gearshape.2"
        case .completed: "checkmark.seal"
        case .failed: "xmark.octagon"
        }
    }
}

extension StemWorkflowValidationSubject {
    var stemModeDisplayTitle: String {
        switch self {
        case .input: "入力音源"
        case .separatedStems: "分離Stem一式"
        case .stem(let name): "Stem: \(name)"
        case .rawRemix: "raw再ミックス"
        case .correctedRemix: "補正後再ミックス"
        case .finalMaster: "最終マスター"
        }
    }
}

extension StemCorrectionStage {
    var stemModeDisplayTitle: String {
        switch self {
        case .lowNoiseCleanup: "低域ノイズ整理"
        case .denoise: "ノイズ除去"
        case .sibilanceShimmerProtection: "サ行・シマー保護"
        case .harmonicRepair: "高域倍音修復"
        case .repairShimmerProtection: "修復後シマー保護"
        case .lowMidResidueControl: "低中域残り整理"
        case .shimmerPeakControl: "短いシマーピーク制御"
        case .highFloorPreservation: "補正後高域保持"
        case .mudIncreaseControl: "補正後mud guard"
        }
    }
}

extension StemCorrectionStageAction {
    var stemModeDisplayTitle: String {
        switch self {
        case .run: "設定上限で実行"
        case .light: "弱めて実行"
        case .skip: "省略"
        }
    }
}

extension StemCorrectionStageGuardOutcome {
    var stemModeDisplayTitle: String {
        switch self {
        case .completed: "工程内guardを含めて完了"
        case .unchanged: "工程内判断により音声を維持"
        case .weakenedByStemProtection: "Stem役割保護によりDSP差分を弱化"
        case .restoredStageInputByStemProtection: "Stem役割保護により処理直前音を維持"
        case .restoredStageInputAfterDSPFailure: "DSP単位の失敗により処理直前音を維持"
        case .restoredStageInputAfterGuardFailure: "guard不確実のため処理直前音を維持"
        case .notEvaluatedForSkippedStage: "工程省略・guard未評価"
        }
    }
}

extension StemMasteringSource {
    var stemModeDisplayTitle: String {
        switch self {
        case .correctedRemix: "補正後再ミックス"
        }
    }
}
