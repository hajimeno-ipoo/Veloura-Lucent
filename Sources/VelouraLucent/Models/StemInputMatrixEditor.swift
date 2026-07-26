import Foundation
import Observation

@MainActor
@Observable
final class StemInputMatrixEditor {
    @MainActor
    @Observable
    final class CoefficientRow: Identifiable {
        nonisolated let inputChannelIndex: Int
        var leftText: String
        var rightText: String

        nonisolated var id: Int { inputChannelIndex }

        init(inputChannelIndex: Int, leftText: String, rightText: String) {
            self.inputChannelIndex = inputChannelIndex
            self.leftText = leftText
            self.rightText = rightText
        }
    }

    let inputLayout: StemInputLayoutIdentity
    let rows: [CoefficientRow]

    @ObservationIgnored
    private let now: @Sendable () -> Date

    init(
        inputLayout: StemInputLayoutIdentity,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.inputLayout = inputLayout
        self.now = now
        rows = (0..<max(inputLayout.channelCount, 0)).map { channelIndex in
            CoefficientRow(
                inputChannelIndex: channelIndex,
                leftText: "",
                rightText: ""
            )
        }
    }

    var requiredCoefficientCount: Int {
        guard inputLayout.channelCount > 0 else { return 0 }
        return inputLayout.channelCount * StemInputChannelMatrix.outputChannelCount
    }

    var missingCoefficientCount: Int {
        coefficientTexts.count(where: { normalized($0).isEmpty })
    }

    var invalidCoefficientCount: Int {
        coefficientTexts.count { text in
            let normalizedText = normalized(text)
            return !normalizedText.isEmpty && parseCoefficient(normalizedText) == nil
        }
    }

    var canConfirm: Bool {
        parsedCoefficients != nil
    }

    var validationSummary: String {
        guard inputLayout.channelCount > 0,
              rows.count == inputLayout.channelCount,
              requiredCoefficientCount == coefficientTexts.count else {
            return "入力レイアウトのチャンネル数が正しくないため、確定できません。"
        }

        let missingCount = missingCoefficientCount
        let invalidCount = invalidCoefficientCount
        if missingCount > 0 && invalidCount > 0 {
            return "未入力が\(missingCount)個、有限の数値として使えない入力が\(invalidCount)個あります。すべての欄を確認してください。"
        }
        if missingCount > 0 {
            return "未入力の係数が\(missingCount)個あります。LeftとRightの全欄へ数値を入力してください。"
        }
        if invalidCount > 0 {
            return "有限の数値として使えない入力が\(invalidCount)個あります。NaNやInfinityは使用できません。"
        }
        return "すべての係数が入力されました。内容を確認して確定できます。"
    }

    func makeConfirmation() -> StemUserConfirmedMixMatrix? {
        guard let coefficients = parsedCoefficients else { return nil }
        return StemUserConfirmedMixMatrix(
            inputLayout: inputLayout,
            coefficients: coefficients,
            confirmedAt: now()
        )
    }

    private var coefficientTexts: [String] {
        rows.flatMap { [$0.leftText, $0.rightText] }
    }

    private var parsedCoefficients: [Float]? {
        guard inputLayout.channelCount > 0,
              rows.count == inputLayout.channelCount,
              coefficientTexts.count == requiredCoefficientCount else {
            return nil
        }

        var coefficients: [Float] = []
        coefficients.reserveCapacity(requiredCoefficientCount)
        for text in coefficientTexts {
            guard let coefficient = parseCoefficient(normalized(text)) else {
                return nil
            }
            coefficients.append(coefficient)
        }
        return coefficients
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseCoefficient(_ text: String) -> Float? {
        guard !text.isEmpty,
              let doubleValue = Double(text),
              doubleValue.isFinite else {
            return nil
        }

        let floatValue = Float(doubleValue)
        guard floatValue.isFinite else { return nil }
        return floatValue
    }
}
