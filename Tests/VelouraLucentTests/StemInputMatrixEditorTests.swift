import AudioToolbox
import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct StemInputMatrixEditorTests {
    @Test
    func unknownAndDiscreteOneAndTwoChannelLayoutsHaveNoSuggestedValues() {
        let cases: [(Int, UInt32)] = [
            (1, kAudioChannelLayoutTag_Unknown | 1),
            (2, kAudioChannelLayoutTag_Unknown | 2),
            (1, kAudioChannelLayoutTag_DiscreteInOrder | 1),
            (2, kAudioChannelLayoutTag_DiscreteInOrder | 2),
        ]

        for (channelCount, layoutTag) in cases {
            let layout = StemInputLayoutIdentity(
                channelCount: channelCount,
                layoutTag: layoutTag,
                channelBitmap: 0,
                channelDescriptions: []
            )
            let editor = StemInputMatrixEditor(inputLayout: layout)

            #expect(editor.rows.count == channelCount)
            #expect(editor.rows.allSatisfy { $0.leftText.isEmpty && $0.rightText.isEmpty })
            #expect(editor.missingCoefficientCount == channelCount * 2)
            #expect(!editor.canConfirm)
        }
    }

    @Test
    func everyCoefficientStartsEmptyAndIsRequired() throws {
        let editor = StemInputMatrixEditor(inputLayout: makeLayout(channelCount: 3))

        #expect(editor.rows.count == 3)
        #expect(editor.rows.allSatisfy { $0.leftText.isEmpty && $0.rightText.isEmpty })
        #expect(editor.requiredCoefficientCount == 6)
        #expect(editor.missingCoefficientCount == 6)
        #expect(editor.invalidCoefficientCount == 0)
        #expect(!editor.canConfirm)
        #expect(editor.makeConfirmation() == nil)

        fill(editor, with: ["1", "0", "0", "1", "0.5", ""])
        #expect(editor.missingCoefficientCount == 1)
        #expect(!editor.canConfirm)
        #expect(editor.makeConfirmation() == nil)

        editor.rows[2].rightText = "0.5"
        #expect(editor.missingCoefficientCount == 0)
        #expect(editor.canConfirm)
    }

    @Test
    func confirmationKeepsExactLayoutCoefficientOrderAndInjectedTime() throws {
        let confirmedAt = Date(timeIntervalSince1970: 1_234_567)
        let layout = StemInputLayoutIdentity(
            channelCount: 2,
            layoutTag: 0x1234,
            channelBitmap: 0xABCD,
            channelDescriptions: [
                StemInputChannelDescriptionIdentity(
                    label: 41,
                    flags: 7,
                    coordinates: [0.1, -0.2, 0.3]
                )
            ]
        )
        let editor = StemInputMatrixEditor(
            inputLayout: layout,
            now: { confirmedAt }
        )
        fill(editor, with: ["1", "0.25", "-0.5", "2"])

        let confirmation = try #require(editor.makeConfirmation())

        #expect(confirmation.inputLayout == layout)
        #expect(confirmation.coefficients == [1, 0.25, -0.5, 2])
        #expect(confirmation.confirmedAt == confirmedAt)
    }

    @Test
    func confirmationIsAcceptedByTheExistingInputConversionContract() throws {
        let layout = makeLayout(channelCount: 2)
        let editor = StemInputMatrixEditor(inputLayout: layout)
        fill(editor, with: ["1", "-0.25", "0.5", "2"])
        let confirmation = try #require(editor.makeConfirmation())

        let selectedMatrix = try StemInputConversionService.selectChannelMatrix(
            resolution: .userConfirmationRequired(layout),
            userConfirmedMatrix: confirmation
        )

        #expect(selectedMatrix.source == .userConfirmed)
        #expect(selectedMatrix.inputLayout == layout)
        #expect(selectedMatrix.coefficients == [1, -0.25, 0.5, 2])
    }

    @Test
    func finiteNegativeAndGreaterThanOneCoefficientsAreAccepted() throws {
        let editor = StemInputMatrixEditor(inputLayout: makeLayout(channelCount: 1))
        fill(editor, with: ["-12.5", "3.75"])

        let confirmation = try #require(editor.makeConfirmation())

        #expect(editor.canConfirm)
        #expect(confirmation.coefficients == [-12.5, 3.75])
    }

    @Test(arguments: ["NaN", "nan", "Infinity", "-Infinity", "inf", "1e100", "abc", "1.0x"])
    func nonFiniteOverflowAndMalformedValuesAreRejected(invalidText: String) {
        let editor = StemInputMatrixEditor(inputLayout: makeLayout(channelCount: 1))
        fill(editor, with: ["1", invalidText])

        #expect(editor.missingCoefficientCount == 0)
        #expect(editor.invalidCoefficientCount == 1)
        #expect(!editor.canConfirm)
        #expect(editor.makeConfirmation() == nil)
    }

    @Test
    func whitespaceOnlyTextIsStillMissing() {
        let editor = StemInputMatrixEditor(inputLayout: makeLayout(channelCount: 1))
        fill(editor, with: ["  \n", "1"])

        #expect(editor.missingCoefficientCount == 1)
        #expect(editor.invalidCoefficientCount == 0)
        #expect(!editor.canConfirm)
    }

    @Test
    func validationUpdatesAfterEditingACompleteMatrix() {
        let editor = StemInputMatrixEditor(inputLayout: makeLayout(channelCount: 2))
        fill(editor, with: ["1", "0", "0", "1"])

        #expect(editor.canConfirm)
        #expect(editor.validationSummary.contains("確定できます"))

        editor.rows[0].leftText = "NaN"
        #expect(!editor.canConfirm)
        #expect(editor.invalidCoefficientCount == 1)
        #expect(editor.validationSummary.contains("使えない入力が1個"))

        editor.rows[0].leftText = "-0.25"
        #expect(editor.canConfirm)
        #expect(editor.invalidCoefficientCount == 0)
    }

    @Test
    func invalidChannelCountCannotProduceAConfirmation() {
        let editor = StemInputMatrixEditor(inputLayout: makeLayout(channelCount: 0))

        #expect(editor.rows.isEmpty)
        #expect(!editor.canConfirm)
        #expect(editor.makeConfirmation() == nil)
        #expect(editor.validationSummary.contains("チャンネル数が正しくない"))
    }

    private func makeLayout(channelCount: Int) -> StemInputLayoutIdentity {
        StemInputLayoutIdentity(
            channelCount: channelCount,
            layoutTag: 0xFFFF_0000 | UInt32(max(channelCount, 0)),
            channelBitmap: 0,
            channelDescriptions: []
        )
    }

    private func fill(_ editor: StemInputMatrixEditor, with texts: [String]) {
        #expect(texts.count == editor.rows.count * 2)
        for rowIndex in editor.rows.indices {
            editor.rows[rowIndex].leftText = texts[rowIndex * 2]
            editor.rows[rowIndex].rightText = texts[(rowIndex * 2) + 1]
        }
    }
}
