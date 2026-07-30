import Foundation

enum StemSeparationSegmentLength: Equatable, Sendable {
    case modelContract
    case seconds(Double)

    var explicitSeconds: Double? {
        guard case let .seconds(value) = self else { return nil }
        return value
    }
}

struct StemSeparationSettings: Equatable, Sendable {
    static let verifiedModelContractSegmentSeconds = 7.8

    let shifts: Int
    let overlap: Float
    let split: Bool
    let segmentLength: StemSeparationSegmentLength
    let batchSize: Int
    let seed: Int?

    /// 承認済みの分離条件を、現在のStemセッションへ明示的に渡します。
    init(
        shifts: Int,
        overlap: Float,
        split: Bool,
        segmentLength: StemSeparationSegmentLength,
        batchSize: Int,
        seed: Int?
    ) {
        self.shifts = shifts
        self.overlap = overlap
        self.split = split
        self.segmentLength = segmentLength
        self.batchSize = batchSize
        self.seed = seed
    }

    /// The approved production baseline for the pinned Meta HTDemucs model.
    ///
    /// `seed`は同じ入力と設定で分離結果を再現するため、処理開始時に明示します。
    static func metaHTDemucsProduction(seed: Int) -> Self {
        StemSeparationSettings(
            shifts: 2,
            overlap: 0.25,
            split: true,
            segmentLength: .modelContract,
            batchSize: 1,
            seed: seed
        )
    }

    func validatedParameters() throws -> Self {
        guard shifts >= 0 else {
            throw StemSeparationSettingsError.invalidShifts(shifts)
        }
        guard overlap.isFinite, overlap >= 0, overlap < 1 else {
            throw StemSeparationSettingsError.invalidOverlap(overlap)
        }
        guard batchSize > 0 else {
            throw StemSeparationSettingsError.invalidBatchSize(batchSize)
        }
        if shifts > 0, seed == nil {
            throw StemSeparationSettingsError.fixedSeedRequired(shifts: shifts)
        }
        if case let .seconds(seconds) = segmentLength {
            guard seconds.isFinite, seconds > 0 else {
                throw StemSeparationSettingsError.invalidSegmentLength(seconds)
            }
        }
        return self
    }

    func validated(modelContract: StemModelContract) throws -> Self {
        _ = try validatedParameters()
        guard modelContract.defaultSegmentSeconds.isFinite,
              modelContract.defaultSegmentSeconds > 0 else {
            throw StemSeparationSettingsError.invalidModelContractSegmentLength(
                modelContract.defaultSegmentSeconds
            )
        }
        guard modelContract.defaultSegmentSeconds == Self.verifiedModelContractSegmentSeconds else {
            throw StemSeparationSettingsError.unverifiedModelContractSegmentLength(
                expected: Self.verifiedModelContractSegmentSeconds,
                actual: modelContract.defaultSegmentSeconds
            )
        }
        guard modelContract.sampleRate == 44_100,
              modelContract.channelCount == 2,
              modelContract.scalarType == .float32,
              modelContract.sourceOrder == [.drums, .bass, .other, .vocals] else {
            throw StemSeparationSettingsError.unsupportedModelContract
        }
        return self
    }
}

enum StemSeparationSettingsError: LocalizedError, Equatable, Sendable {
    case invalidShifts(Int)
    case invalidOverlap(Float)
    case invalidBatchSize(Int)
    case fixedSeedRequired(shifts: Int)
    case invalidSegmentLength(Double)
    case invalidModelContractSegmentLength(Double)
    case unverifiedModelContractSegmentLength(expected: Double, actual: Double)
    case unsupportedModelContract

    var errorDescription: String? {
        switch self {
        case let .invalidShifts(value):
            "Stem分離のshiftsは0以上で指定してください（実際: \(value)）。"
        case let .invalidOverlap(value):
            "Stem分離のoverlapは0以上1未満の有限値で指定してください（実際: \(value)）。"
        case let .invalidBatchSize(value):
            "Stem分離のbatch sizeは1以上で指定してください（実際: \(value)）。"
        case let .fixedSeedRequired(shifts):
            "shiftsを\(shifts)回使うStem分離では、同じ入力と設定で結果を再現する固定seedが必要です。"
        case let .invalidSegmentLength(value):
            "Stem分離のsegment秒数は0より大きい有限値で指定してください（実際: \(value)）。"
        case let .invalidModelContractSegmentLength(value):
            "検証済みモデル契約のsegment秒数が不正です（実際: \(value)）。"
        case let .unverifiedModelContractSegmentLength(expected, actual):
            "Stem分離のモデル契約segment秒数が検証済み値と一致しません（検証済み: \(expected)秒、実際: \(actual)秒）。"
        case .unsupportedModelContract:
            "検証済みモデル契約が44.1 kHz／stereo／Float32／4ステム順序の要件と一致しません。"
        }
    }
}
