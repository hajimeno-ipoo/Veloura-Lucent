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
        case .correctedPureSum48000: "補正済み純粋加算"
        case .remixed48000: "Stem再ミックス"
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
        case .correctedPureSum48000: "waveform"
        case .remixed48000: "slider.horizontal.3"
        case .finalMaster: "checkmark.seal"
        }
    }

    var isStemModeUserExportable: Bool {
        switch self {
        case .correctedStem,
             .correctedPureSum48000,
             .remixed48000,
             .finalMaster:
            true
        case .input44100,
             .rawStem:
            false
        }
    }

    /// 通常モードの入力・処理後・最終版に、純粋加算／再ミックスA/B用の
    /// 2つの処理後成果物を追加します。個別Stemは混在させません。
    var isStemModePreviewable: Bool {
        switch self {
        case .input44100,
             .correctedPureSum48000,
             .remixed48000,
             .finalMaster:
            true
        case .rawStem,
             .correctedStem:
            false
        }
    }

    var stemModeExportSortRank: Int {
        switch self {
        case .correctedPureSum48000: 0
        case .remixed48000: 1
        case .correctedStem(.drums): 10
        case .correctedStem(.bass): 11
        case .correctedStem(.other): 12
        case .correctedStem(.vocals): 13
        case .finalMaster: 20
        case .input44100: 100
        case .rawStem: 110
        }
    }

    /// 入力・純粋加算・再ミックス・最終版の順序です。
    var stemModePreviewSortRank: Int {
        switch self {
        case .input44100: 0
        case .correctedPureSum48000: 10
        case .remixed48000: 15
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
        case .readyForRemix: "補正完了・再ミックス待ち"
        case .readyForMastering: "再ミックス完了・マスタリング待ち"
        case .running(let step): "\(step.title)を実行中"
        case .completed: "完了"
        case .failed: "停止"
        }
    }

    var stemModeSystemImage: String {
        switch self {
        case .idle: "circle"
        case .ready: "checkmark.circle"
        case .readyForRemix: "slider.horizontal.3"
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
        case .correctedPureSum: "補正済み純粋加算"
        case .remix: "Stem再ミックス"
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

extension StemRemixRenderStage {
    var stemModeProcessStep: StemModeProcessStep {
        switch self {
        case .gain: .remixGain
        case .masking: .remixMasking
        case .pan: .remixPan
        case .reverbSend: .remixReverbSend
        case .sharedReverb: .remixSharedReverb
        case .dryReturnMix: .remixDryReturnMix
        }
    }

    var stemModeRunningDetail: String {
        switch self {
        case .gain: "補正後の相対変化を基準にStem別gainを適用します"
        case .masking: "実測衝突区間だけdynamic EQ／duckingを適用します"
        case .pan: "rawから変化した左右バランスだけを補正します"
        case .reverbSend: "pan後の各Stemから共通reverbへのsendを生成します"
        case .sharedReverb: "一つの共通reverb returnを生成します"
        case .dryReturnMix: "dry Stem合計へ共通reverb returnを加算します"
        }
    }

    var stemModeCompletedDetail: String {
        switch self {
        case .gain: "Stem別gainを適用しました"
        case .masking: "条件付き帯域制御を完了しました"
        case .pan: "Stem別panを適用しました"
        case .reverbSend: "Stem別reverb sendを生成しました"
        case .sharedReverb: "共通reverb returnを生成しました"
        case .dryReturnMix: "dry／reverb加算を完了しました"
        }
    }
}

extension StemMasteringSource {
    var stemModeDisplayTitle: String {
        switch self {
        case .remix: "Stem再ミックス"
        }
    }
}
