import AppKit
import AVFoundation
import Foundation
import SwiftUI
import Testing
@testable import VelouraLucent

struct ComparisonVideoTests {
    @Test
    func standardPlanUsesContinuationOrder() throws {
        let plan = try #require(ComparisonVideoPlan.make(
            sourceDuration: 85,
            requestedStartTime: 20
        ))

        #expect(plan.sourceStartTime == 20)
        #expect(plan.sourceDuration == 60)
        #expect(plan.outputDuration == 60)
        #expect(plan.segments == [
            .init(sourceIndex: 0, sourceStartTime: 20, duration: 15),
            .init(sourceIndex: 1, sourceStartTime: 35, duration: 15),
            .init(sourceIndex: 0, sourceStartTime: 50, duration: 15),
            .init(sourceIndex: 1, sourceStartTime: 65, duration: 15),
        ])
    }

    @Test
    func previewFrameTimeStopsUpdatingAfterEachRoleTransition() throws {
        let plan = try #require(ComparisonVideoPlan.make(
            sourceDuration: 60,
            requestedStartTime: 0
        ))

        #expect(plan.previewFrameTime(at: 0.1) == 0.1)
        #expect(plan.previewFrameTime(at: 10) == 0.3)
        #expect(plan.previewFrameTime(at: 15.1) == 15.1)
        #expect(plan.previewFrameTime(at: 20) == 15.3)
    }

    @Test
    func shortSourceUsesWholeRangeAndShortensOutput() throws {
        let plan = try #require(ComparisonVideoPlan.make(
            sourceDuration: 20,
            requestedStartTime: 8
        ))

        #expect(plan.sourceStartTime == 0)
        #expect(plan.sourceDuration == 20)
        #expect(plan.outputDuration == 20)
        #expect(plan.segments == [
            .init(sourceIndex: 0, sourceStartTime: 0, duration: 15),
            .init(sourceIndex: 1, sourceStartTime: 15, duration: 5),
        ])
    }

    @Test
    func rangeStartIsClampedToLastSixtySeconds() throws {
        let plan = try #require(ComparisonVideoPlan.make(
            sourceDuration: 75,
            requestedStartTime: 99
        ))

        #expect(plan.sourceStartTime == 15)
        #expect(plan.sourceDuration == 60)
    }

    @Test
    func frameStateSwitchesRolesAtFifteenSecondBoundaries() throws {
        let plan = try #require(ComparisonVideoPlan.make(
            sourceDuration: 60,
            requestedStartTime: 0
        ))

        func role(at time: TimeInterval) -> String {
            ComparisonVideoFrameState(
                trackTitle: "Test Song",
                firstRoleTitle: "入力",
                secondRoleTitle: "補正後",
                plan: plan,
                outputTime: time
            ).activeRoleTitle
        }

        #expect(role(at: 0) == "入力")
        #expect(role(at: 14.999) == "入力")
        #expect(role(at: 15) == "補正後")
        #expect(role(at: 30) == "入力")
        #expect(role(at: 45) == "補正後")
    }

    @Test
    func frameStateSwitchesExistingInspectorInformationWithTheActiveSource() throws {
        let plan = try #require(ComparisonVideoPlan.make(
            sourceDuration: 60,
            requestedStartTime: 0
        ))
        let firstInfo = ComparisonVideoInspectorInfo(
            metrics: metrics(integratedLoudness: -18, truePeak: -2),
            fileInfo: AudioFileInfo(
                formatName: "WAV",
                sampleRate: 48_000,
                channelCount: 2,
                duration: 60,
                bitDepth: 24,
                isFloatingPoint: false
            )
        )
        let secondInfo = ComparisonVideoInspectorInfo(
            metrics: metrics(integratedLoudness: -14, truePeak: -1),
            fileInfo: AudioFileInfo(
                formatName: "AIFF",
                sampleRate: 44_100,
                channelCount: 1,
                duration: 60,
                bitDepth: 16,
                isFloatingPoint: false
            )
        )
        let settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test Song",
            firstRoleTitle: "入力",
            secondRoleTitle: "補正後"
        )

        let firstState = ComparisonVideoFrameState(
            displaySettings: settings,
            firstInspectorInfo: firstInfo,
            secondInspectorInfo: secondInfo,
            plan: plan,
            outputTime: 14.999
        )
        let secondState = ComparisonVideoFrameState(
            displaySettings: settings,
            firstInspectorInfo: firstInfo,
            secondInspectorInfo: secondInfo,
            plan: plan,
            outputTime: 15
        )

        #expect(firstState.activeInspectorInfo?.metrics?.integratedLoudnessLUFS == -18)
        #expect(firstState.activeInspectorInfo?.fileInfo?.formatName == "WAV")
        #expect(secondState.activeInspectorInfo?.metrics?.integratedLoudnessLUFS == -14)
        #expect(secondState.activeInspectorInfo?.fileInfo?.formatName == "AIFF")
    }

    @Test
    func displaySettingsClampFontSizeAndPositionAdjustments() {
        let defaults = ComparisonVideoDisplaySettings(
            trackTitle: "Default",
            firstRoleTitle: "先",
            secondRoleTitle: "次"
        )
        #expect(defaults.titleFontSize == 82)
        #expect(defaults.roleFontSize == 64)
        #expect(defaults.titleFontFamily == nil)
        #expect(defaults.roleFontFamily == nil)
        #expect(defaults.position(for: .title) == CGPoint(x: 50, y: 45))
        #expect(defaults.position(for: .role) == CGPoint(x: 50, y: 55))
        #expect(defaults.position(for: .inspector) == CGPoint(x: 50, y: 84))
        #expect(defaults.position(for: .visualizer) == CGPoint(x: 50, y: 70))
        #expect(defaults.titleColor == .defaultTitle)
        #expect(defaults.firstRoleColor == .defaultFirstRole)
        #expect(defaults.secondRoleColor == .defaultSecondRole)
        #expect(defaults.fadeInDuration == 1)
        #expect(defaults.fadeOutDuration == 1)
        #expect(defaults.videoFadeInEnabled)
        #expect(defaults.videoFadeOutEnabled)
        #expect(defaults.audioFadeInEnabled)
        #expect(defaults.audioFadeOutEnabled)
        #expect(defaults.visualizerEnabled)
        #expect(defaults.visualizerPaletteMode == .standard)
        #expect(defaults.visualizerLeadingColor == .defaultVisualizerLeading)
        #expect(defaults.visualizerCenterColor == .defaultVisualizerCenter)
        #expect(defaults.visualizerTrailingColor == .defaultVisualizerTrailing)
        #expect(defaults.visualizerWidth == 1)
        #expect(defaults.visualizerHeight == 0.65)
        #expect(defaults.visualizerScale == 1)
        #expect(defaults.visualizerResponse == 0.8)
        #expect(defaults.visualizerHeightScale == 1)

        let titleColor = ComparisonVideoRGBAColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1)
        let firstRoleColor = ComparisonVideoRGBAColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1)
        let secondRoleColor = ComparisonVideoRGBAColor(red: 0.2, green: 0.1, blue: 0.9, alpha: 1)
        var settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test Song",
            firstRoleTitle: "入力",
            secondRoleTitle: "補正後",
            titleFontFamily: "Arial",
            roleFontFamily: "Helvetica",
            titleFontSize: 20,
            roleFontSize: 350,
            titlePositionX: -10,
            titlePositionY: 110,
            rolePositionX: 25,
            rolePositionY: 75,
            inspectorPositionX: 120,
            inspectorPositionY: -20,
            visualizerPositionX: -30,
            visualizerPositionY: 130,
            titleColor: titleColor,
            firstRoleColor: firstRoleColor,
            secondRoleColor: secondRoleColor,
            fadeInDuration: -2,
            fadeOutDuration: 8,
            videoFadeInEnabled: false,
            videoFadeOutEnabled: false,
            audioFadeInEnabled: false,
            audioFadeOutEnabled: false,
            visualizerEnabled: false,
            visualizerPaletteMode: .custom,
            visualizerLeadingColor: firstRoleColor,
            visualizerCenterColor: secondRoleColor,
            visualizerTrailingColor: titleColor,
            visualizerWidth: 2,
            visualizerHeight: 0,
            visualizerScale: 3,
            visualizerResponse: -1,
            visualizerHeightScale: 4
        )

        #expect(settings.titleFontSize == 24)
        #expect(settings.roleFontSize == 300)
        #expect(settings.titleFontFamily == "Arial")
        #expect(settings.roleFontFamily == "Helvetica")
        #expect(settings.position(for: .title) == CGPoint(x: 0, y: 100))
        #expect(settings.position(for: .role) == CGPoint(x: 25, y: 75))
        #expect(settings.position(for: .inspector) == CGPoint(x: 100, y: 0))
        #expect(settings.position(for: .visualizer) == CGPoint(x: 0, y: 100))
        #expect(settings.titleColor == titleColor)
        #expect(settings.firstRoleColor == firstRoleColor)
        #expect(settings.secondRoleColor == secondRoleColor)
        #expect(settings.fadeInDuration == 0)
        #expect(settings.fadeOutDuration == 5)
        #expect(!settings.videoFadeInEnabled)
        #expect(!settings.videoFadeOutEnabled)
        #expect(!settings.audioFadeInEnabled)
        #expect(!settings.audioFadeOutEnabled)
        #expect(!settings.visualizerEnabled)
        #expect(settings.visualizerPaletteMode == .custom)
        #expect(settings.visualizerLeadingColor == firstRoleColor)
        #expect(settings.visualizerCenterColor == secondRoleColor)
        #expect(settings.visualizerTrailingColor == titleColor)
        #expect(settings.visualizerWidth == 1)
        #expect(settings.visualizerHeight == 0.25)
        #expect(settings.visualizerScale == 2)
        #expect(settings.visualizerResponse == 0)
        #expect(settings.visualizerHeightScale == 3)

        settings.setPosition(CGPoint(x: 80, y: 35), for: .title)
        settings.setPosition(CGPoint(x: 45, y: 60), for: .inspector)
        settings.setPosition(CGPoint(x: 55, y: 72), for: .visualizer)
        #expect(settings.position(for: .title) == CGPoint(x: 80, y: 35))
        #expect(settings.position(for: .role) == CGPoint(x: 25, y: 75))
        #expect(settings.position(for: .inspector) == CGPoint(x: 45, y: 60))
        #expect(settings.position(for: .visualizer) == CGPoint(x: 55, y: 72))
    }

    @Test
    func visualizerPaletteSwitchesBetweenStandardSevenColorsAndCustomThreeColors() {
        let leading = ComparisonVideoRGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
        let center = ComparisonVideoRGBAColor(red: 0, green: 1, blue: 0, alpha: 1)
        let trailing = ComparisonVideoRGBAColor(red: 0, green: 0, blue: 1, alpha: 1)
        var settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test Song",
            firstRoleTitle: "入力",
            secondRoleTitle: "補正後",
            visualizerLeadingColor: leading,
            visualizerCenterColor: center,
            visualizerTrailingColor: trailing
        )

        #expect(settings.visualizerGradientStops.count == 7)
        let standardLocations = settings.visualizerGradientStops.map(\.location)
        let expectedStandardLocations: [Double] = [
            0,
            1.0 / 6,
            2.0 / 6,
            3.0 / 6,
            4.0 / 6,
            5.0 / 6,
            1
        ]
        #expect(standardLocations == expectedStandardLocations)
        let standardColors = settings.visualizerGradientStops.map(\.color)
        let expectedStandardColors = [
            ComparisonVideoRGBAColor(red: 166.0 / 255, green: 140.0 / 255, blue: 249.0 / 255, alpha: 1),
            ComparisonVideoRGBAColor(red: 90.0 / 255, green: 165.0 / 255, blue: 246.0 / 255, alpha: 1),
            ComparisonVideoRGBAColor(red: 89.0 / 255, green: 193.0 / 255, blue: 227.0 / 255, alpha: 1),
            ComparisonVideoRGBAColor(red: 107.0 / 255, green: 223.0 / 255, blue: 99.0 / 255, alpha: 1),
            ComparisonVideoRGBAColor(red: 216.0 / 255, green: 240.0 / 255, blue: 101.0 / 255, alpha: 1),
            ComparisonVideoRGBAColor(red: 236.0 / 255, green: 167.0 / 255, blue: 91.0 / 255, alpha: 1),
            ComparisonVideoRGBAColor(red: 227.0 / 255, green: 80.0 / 255, blue: 188.0 / 255, alpha: 1)
        ]
        #expect(standardColors == expectedStandardColors)

        settings.visualizerPaletteMode = .custom

        #expect(settings.visualizerGradientStops == [
            ComparisonVideoVisualizerGradientStop(color: leading, location: 0),
            ComparisonVideoVisualizerGradientStop(color: center, location: 0.5),
            ComparisonVideoVisualizerGradientStop(color: trailing, location: 1)
        ])

        settings.visualizerPaletteMode = .standard
        #expect(settings.visualizerGradientStops.count == 7)
        #expect(settings.visualizerLeadingColor == leading)
        #expect(settings.visualizerCenterColor == center)
        #expect(settings.visualizerTrailingColor == trailing)
    }

    @Test
    func fadeEnvelopeUsesSeparateStartAndEndDurations() {
        #expect(ComparisonVideoFadeEnvelope.level(
            at: 0,
            duration: 10,
            fadeInDuration: 2,
            fadeOutDuration: 1
        ) == 0)
        #expect(ComparisonVideoFadeEnvelope.level(
            at: 1,
            duration: 10,
            fadeInDuration: 2,
            fadeOutDuration: 1
        ) == 0.5)
        #expect(ComparisonVideoFadeEnvelope.level(
            at: 5,
            duration: 10,
            fadeInDuration: 2,
            fadeOutDuration: 1
        ) == 1)
        #expect(abs(ComparisonVideoFadeEnvelope.level(
            at: 9.5,
            duration: 10,
            fadeInDuration: 2,
            fadeOutDuration: 1
        ) - 0.5) < 0.000_001)
        #expect(ComparisonVideoFadeEnvelope.level(
            at: 10,
            duration: 10,
            fadeInDuration: 2,
            fadeOutDuration: 1
        ) == 0)
    }

    @Test
    func videoAndAudioFadeSwitchesAreIndependent() throws {
        var settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test",
            firstRoleTitle: "先",
            secondRoleTitle: "次",
            fadeInDuration: 2,
            fadeOutDuration: 3
        )

        #expect(settings.effectiveVideoFadeInDuration == 2)
        #expect(settings.effectiveVideoFadeOutDuration == 3)
        #expect(settings.effectiveAudioFadeInDuration == 2)
        #expect(settings.effectiveAudioFadeOutDuration == 3)

        settings.videoFadeInEnabled = false
        #expect(settings.effectiveVideoFadeInDuration == 0)
        #expect(settings.effectiveVideoFadeOutDuration == 3)
        #expect(settings.effectiveAudioFadeInDuration == 2)
        #expect(settings.effectiveAudioFadeOutDuration == 3)

        settings.videoFadeOutEnabled = false
        settings.audioFadeInEnabled = false
        settings.audioFadeOutEnabled = false
        #expect(settings.effectiveVideoFadeOutDuration == 0)
        #expect(settings.effectiveAudioFadeInDuration == 0)
        #expect(settings.effectiveAudioFadeOutDuration == 0)

        let plan = try #require(ComparisonVideoPlan.make(sourceDuration: 10, requestedStartTime: 0))
        settings.videoFadeInEnabled = false
        settings.videoFadeOutEnabled = true
        let startWithoutVideoFadeIn = ComparisonVideoFrameState(
            displaySettings: settings,
            firstInspectorInfo: nil,
            secondInspectorInfo: nil,
            plan: plan,
            outputTime: 0
        )
        let endWithVideoFadeOut = ComparisonVideoFrameState(
            displaySettings: settings,
            firstInspectorInfo: nil,
            secondInspectorInfo: nil,
            plan: plan,
            outputTime: plan.outputDuration
        )
        #expect(startWithoutVideoFadeIn.videoFadeLevel == 1)
        #expect(endWithVideoFadeOut.videoFadeLevel == 0)

        settings.videoFadeInEnabled = true
        settings.videoFadeOutEnabled = false
        let startWithVideoFadeIn = ComparisonVideoFrameState(
            displaySettings: settings,
            firstInspectorInfo: nil,
            secondInspectorInfo: nil,
            plan: plan,
            outputTime: 0
        )
        let endWithoutVideoFadeOut = ComparisonVideoFrameState(
            displaySettings: settings,
            firstInspectorInfo: nil,
            secondInspectorInfo: nil,
            plan: plan,
            outputTime: plan.outputDuration
        )
        #expect(startWithVideoFadeIn.videoFadeLevel == 0)
        #expect(endWithoutVideoFadeOut.videoFadeLevel == 1)
    }

    @Test
    func visualizerStartsAtFullWidthAndAppliesUniformPercentageScale() {
        var settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test",
            firstRoleTitle: "先",
            secondRoleTitle: "次"
        )
        let fullSize = settings.visualizerSize(for: .landscape)
        #expect(fullSize.width == ComparisonVideoOrientation.landscape.pixelSize.width)
        #expect(fullSize.height == ComparisonVideoOrientation.landscape.pixelSize.height * 0.14 * 0.65)

        settings.visualizerWidth = 0.5
        settings.visualizerHeight = 1
        settings.visualizerScale = 0.5
        let adjustedSize = settings.visualizerSize(for: .landscape)
        #expect(adjustedSize.width == ComparisonVideoOrientation.landscape.pixelSize.width * 0.25)
        #expect(adjustedSize.height == ComparisonVideoOrientation.landscape.pixelSize.height * 0.14 * 0.5)

        settings.visualizerScale = 0
        #expect(settings.visualizerScale == 0.25)
    }

    @MainActor
    @Test
    func orientationUsesItsInspectorDefaultWithoutReplacingAUserPosition() {
        let model = ComparisonVideoWindowModel()

        #expect(model.displaySettings.position(for: .inspector) == CGPoint(x: 50, y: 84))
        #expect(model.displaySettings.inspectorAspectRatio == .custom)
        #expect(model.displaySettings.inspectorLayout == .wide)

        model.orientation = .portrait
        #expect(model.displaySettings.position(for: .inspector) == CGPoint(x: 50, y: 80))
        #expect(model.displaySettings.inspectorAspectRatio == .portrait)
        #expect(model.displaySettings.inspectorLayout == .square)
        #expect(abs(model.inspectorSize.width - 521.78) < 0.01)
        #expect(abs(model.inspectorSize.height - 695.70) < 0.01)

        model.setDisplayPosition(CGPoint(x: 63, y: 72), for: .inspector)
        model.orientation = .landscape
        #expect(model.displaySettings.position(for: .inspector) == CGPoint(x: 63, y: 72))
        #expect(model.displaySettings.inspectorAspectRatio == .custom)
    }

    @MainActor
    @Test
    func inspectorSizeChangeKeepsAutomaticRatioButManualRatioChangesArePreserved() {
        let automaticModel = ComparisonVideoWindowModel()
        automaticModel.setInspectorScale(400)
        automaticModel.orientation = .portrait
        #expect(automaticModel.displaySettings.inspectorAspectRatio == .portrait)

        let presetModel = ComparisonVideoWindowModel()
        presetModel.setInspectorAspectRatio(.square)
        presetModel.orientation = .portrait
        #expect(presetModel.displaySettings.inspectorAspectRatio == .square)
        presetModel.orientation = .landscape
        #expect(presetModel.displaySettings.inspectorAspectRatio == .square)

        let customModel = ComparisonVideoWindowModel()
        customModel.setCustomInspectorAspectWidth(12)
        customModel.orientation = .portrait
        #expect(customModel.displaySettings.inspectorAspectRatio == .custom)
        #expect(customModel.displaySettings.customAspectWidth == 12)
        #expect(customModel.displaySettings.customAspectHeight == 2)
    }

    @Test
    func inspectorDefaultsToTheExistingCustomRatioAndFitsTheCurrentCanvas() {
        var settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test Song",
            firstRoleTitle: "入力",
            secondRoleTitle: "補正後"
        )

        #expect(settings.inspectorAspectRatio == .custom)
        #expect(settings.customAspectWidth == 15)
        #expect(settings.customAspectHeight == 2)
        #expect(settings.inspectorSize(for: .landscape) == CGSize(width: 1_650, height: 220))
        let portraitSize = settings.inspectorSize(for: .portrait)
        #expect(abs(portraitSize.width - 950.4) < 0.001)
        #expect(abs(portraitSize.width / portraitSize.height - 7.5) < 0.001)

        settings.setInspectorScale(1, for: .landscape)
        #expect(settings.inspectorScale(for: .landscape) == settings.inspectorScaleRange(for: .landscape).lowerBound)
        let minimumSize = settings.inspectorSize(for: .landscape)
        #expect(abs(minimumSize.width / minimumSize.height - 7.5) < 0.001)
        #expect(abs(minimumSize.width - 412.5) < 0.001)
        #expect(abs(minimumSize.height - 55) < 0.001)
    }

    @Test
    func portraitInspectorUsesItsFittedDefaultAsTheContentScaleBaseline() {
        var settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test Song",
            firstRoleTitle: "入力",
            secondRoleTitle: "補正後"
        )

        #expect(abs(settings.inspectorContentScale(for: .landscape) - 1) < 0.001)
        #expect(abs(settings.inspectorContentScale(for: .portrait) - 1) < 0.001)

        settings.setInspectorScale(
            settings.inspectorScaleRange(for: .portrait).lowerBound,
            for: .portrait
        )
        #expect(settings.inspectorContentScale(for: .portrait) < 1)
    }

    @Test
    func inspectorPresetMinimumSizesScaleTheWholePanelToOneQuarter() {
        var settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test Song",
            firstRoleTitle: "入力",
            secondRoleTitle: "補正後"
        )
        let expectedArea = ComparisonVideoDisplaySettings.defaultInspectorSize.width
            * ComparisonVideoDisplaySettings.defaultInspectorSize.height
            * ComparisonVideoDisplaySettings.minimumInspectorLinearScale
            * ComparisonVideoDisplaySettings.minimumInspectorLinearScale

        for aspectRatio in ComparisonVideoInspectorAspectRatio.allCases where aspectRatio != .custom {
            settings.setInspectorAspectRatio(aspectRatio, for: .landscape)
            settings.setInspectorScale(1, for: .landscape)
            let size = settings.inspectorSize(for: .landscape)
            #expect(abs(size.width * size.height - expectedArea) < 0.001)
            #expect(abs(size.width / size.height - settings.inspectorAspectValue) < 0.001)
        }
    }

    @Test
    func inspectorLayoutUsesTheSelectedAspectRatio() {
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 16.0 / 9.0) == .wide)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 4.0 / 3.0) == .square)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 1) == .square)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 3.0 / 4.0) == .square)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 9.0 / 16.0) == .tall)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 2).columnCount == 4)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 1).columnCount == 2)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 0.5).columnCount == 1)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 2).rowCount == 2)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 1).rowCount == 4)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 0.5).rowCount == 8)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 2).labelFontSize == 22)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 2).valueFontSize == 27)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 1).labelFontSize == 28)
        #expect(ComparisonVideoInspectorLayout(aspectRatio: 1).valueFontSize == 32)
    }

    @MainActor
    @Test
    func changingInspectorRatioAndSizeKeepsItsCenterPosition() {
        let model = ComparisonVideoWindowModel()
        model.setDisplayPosition(CGPoint(x: 63, y: 72), for: .inspector)
        let originalArea = model.inspectorSize.width * model.inspectorSize.height

        model.setInspectorAspectRatio(.widescreen)

        #expect(model.displaySettings.position(for: .inspector) == CGPoint(x: 63, y: 72))
        #expect(abs(model.inspectorSize.width / model.inspectorSize.height - 16.0 / 9.0) < 0.001)
        let scaleRange = model.displaySettings.inspectorScaleRange(for: model.orientation)
        let minimumArea = scaleRange.lowerBound * scaleRange.lowerBound
        #expect(
            abs(
                model.inspectorSize.width * model.inspectorSize.height
                    - max(originalArea, minimumArea)
            ) < 0.001
        )

        model.setInspectorScale(400)
        let expectedScale = min(max(400, scaleRange.lowerBound), scaleRange.upperBound)
        #expect(
            abs(
                model.inspectorSize.width * model.inspectorSize.height
                    - expectedScale * expectedScale
            ) < 0.001
        )
        #expect(model.displaySettings.position(for: .inspector) == CGPoint(x: 63, y: 72))
    }

    @Test
    func customInspectorRatioRejectsInvalidComponents() {
        var settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test Song",
            firstRoleTitle: "入力",
            secondRoleTitle: "補正後"
        )

        settings.setCustomAspectWidth(12, for: .landscape)
        settings.setCustomAspectHeight(5, for: .landscape)
        #expect(settings.customAspectWidth == 12)
        #expect(settings.customAspectHeight == 5)
        #expect(abs(settings.inspectorAspectValue - 2.4) < 0.001)

        settings.setCustomAspectWidth(0, for: .landscape)
        settings.setCustomAspectHeight(-1, for: .landscape)
        #expect(settings.customAspectWidth == 12)
        #expect(settings.customAspectHeight == 5)

        settings.setCustomAspectWidth(10_000, for: .landscape)
        settings.setCustomAspectHeight(1, for: .landscape)
        let fittedSize = settings.inspectorSize(for: .landscape)
        #expect(fittedSize.width <= ComparisonVideoOrientation.landscape.pixelSize.width * 0.88)
        #expect(fittedSize.height <= ComparisonVideoOrientation.landscape.pixelSize.height * 0.88)
    }

    @MainActor
    @Test
    func previewVolumeIsClampedToThePlayerRange() {
        let model = ComparisonVideoWindowModel()

        model.setPreviewVolume(2)
        #expect(model.previewVolume == 1)

        model.setPreviewVolume(-1)
        #expect(model.previewVolume == 0)
    }

    @Test
    func fileNameContainsOnlyTrackTitleAndRoles() {
        let first = ComparisonVideoSource(
            fileURL: URL(fileURLWithPath: "/tmp/first.wav"),
            trackTitle: "My/Song",
            roleTitle: "補正:後"
        )
        let second = ComparisonVideoSource(
            fileURL: URL(fileURLWithPath: "/tmp/second.wav"),
            trackTitle: "My/Song",
            roleTitle: "最終版"
        )

        #expect(
            ComparisonVideoSourceCatalog.suggestedFileName(
                first: first,
                second: second,
                format: .mov
            ) == "My_Song_補正_後-最終版.mov"
        )
    }

    @MainActor
    @Test
    func standardCatalogIncludesInputAndCurrentRegisteredPreviewFiles() throws {
        try FileManager.default.createDirectory(
            at: PreviewFileStore.directory,
            withIntermediateDirectories: true
        )
        let corrected = PreviewFileStore.directory.appending(
            path: "comparison-corrected-\(UUID().uuidString).wav"
        )
        let mastered = PreviewFileStore.directory.appending(
            path: "comparison-mastered-\(UUID().uuidString).wav"
        )
        let unregistered = PreviewFileStore.directory.appending(
            path: "comparison-unregistered-\(UUID().uuidString).wav"
        )
        let inputRoot = FileManager.default.temporaryDirectory.appending(
            path: "ComparisonVideoStandardInputTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: inputRoot, withIntermediateDirectories: true)
        let input = inputRoot.appending(path: "Test Song.wav")
        defer {
            try? FileManager.default.removeItem(at: inputRoot)
            try? FileManager.default.removeItem(at: corrected)
            try? FileManager.default.removeItem(at: mastered)
            try? FileManager.default.removeItem(at: unregistered)
        }
        try Data([0]).write(to: input)
        try Data([0]).write(to: corrected)
        try Data([0]).write(to: mastered)
        try Data([0]).write(to: unregistered)

        let job = ProcessingJob()
        job.inputFile = input
        job.outputFile = corrected
        job.masteredOutputFile = mastered
        job.hasExistingOutput = true
        job.hasExistingMasteredOutput = true
        job.inputMetrics = metrics(integratedLoudness: -18, truePeak: -2)
        job.outputMetrics = metrics(integratedLoudness: -16, truePeak: -1.5)
        job.masteredMetrics = metrics(integratedLoudness: -14, truePeak: -1)
        job.inputSpectrogram = spectrogram(levelDB: -30)
        job.outputSpectrogram = spectrogram(levelDB: -24)
        job.masteredSpectrogram = spectrogram(levelDB: -18)

        let sources = ComparisonVideoSourceCatalog.standard(job: job)

        #expect(sources.map(\.fileURL) == [
            input.standardizedFileURL,
            corrected.standardizedFileURL,
            mastered.standardizedFileURL,
        ])
        #expect(sources.map(\.trackTitle) == ["Test Song", "Test Song", "Test Song"])
        #expect(sources.map(\.roleTitle) == ["入力", "補正後", "最終版"])
        #expect(sources.map { $0.inspectorMetrics?.integratedLoudnessLUFS } == [-18, -16, -14])
        #expect(sources.map { $0.spectrogram?.cells.first?.levelDB } == [-30, -24, -18])
        #expect(!sources.contains { $0.fileURL == unregistered })
    }

    @Test
    func stemCatalogExcludesConvertedInputAndKeepsVisibleComparisonSources() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ComparisonVideoStemCatalogTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let validURL = root.appending(path: "vocals.wav")
        let convertedInputURL = root.appending(path: "input-44100.wav")
        let inputURL = root.appending(path: "Stem Song.wav")
        let invalidURL = root.appending(path: "bass.wav")
        try Data([0]).write(to: inputURL)
        try Data([0]).write(to: validURL)
        try Data([0]).write(to: convertedInputURL)
        try Data([0]).write(to: invalidURL)
        let runID = UUID()
        let valid = StemAudioArtifact(
            id: "valid-vocals",
            kind: .correctedStem(.vocals),
            fileURL: validURL,
            sampleRate: 48_000,
            channelCount: 2,
            frameCount: 48_000
        )
        let convertedInput = StemAudioArtifact(
            id: "input-44100",
            kind: .input44100,
            fileURL: convertedInputURL,
            sampleRate: 44_100,
            channelCount: 2,
            frameCount: 44_100
        )
        let invalid = StemAudioArtifact(
            id: "invalid-bass",
            kind: .rawStem(.bass),
            fileURL: invalidURL,
            sampleRate: 44_100,
            channelCount: 2,
            frameCount: 44_100
        )
        let missing = StemAudioArtifact(
            id: "missing-final",
            kind: .finalMaster,
            fileURL: root.appending(path: "missing.wav"),
            sampleRate: 48_000,
            channelCount: 2,
            frameCount: 48_000
        )

        let sources = ComparisonVideoSourceCatalog.stem(
            selectedInputURL: inputURL,
            artifactStates: [
                .init(id: valid.id, runID: runID, kind: valid.kind, artifact: valid, status: .valid),
                .init(
                    id: convertedInput.id,
                    runID: runID,
                    kind: convertedInput.kind,
                    artifact: convertedInput,
                    status: .valid
                ),
                .init(id: invalid.id, runID: runID, kind: invalid.kind, artifact: invalid, status: .invalid(message: "invalid")),
                .init(id: missing.id, runID: runID, kind: missing.kind, artifact: missing, status: .valid),
            ],
            spectrogramsBySourceID: [
                validURL.standardizedFileURL.path(percentEncoded: false): spectrogram(levelDB: -22),
            ]
        )

        #expect(sources.map(\.fileURL) == [inputURL.standardizedFileURL, validURL.standardizedFileURL])
        #expect(sources.map(\.trackTitle) == ["Stem Song", "Stem Song"])
        #expect(sources.map(\.roleTitle) == ["入力", "ボーカル（補正済み）"])
        #expect(sources[0].spectrogram == nil)
        #expect(sources[1].spectrogram?.cells.first?.levelDB == -22)
        #expect(!sources.contains { $0.roleTitle == "変換済み入力" })
    }

    @Test
    func comparisonLaunchWaitsForEverySourceSpectrumTimeline() {
        let firstURL = URL(fileURLWithPath: "/tmp/comparison-ready-first.wav")
        let secondURL = URL(fileURLWithPath: "/tmp/comparison-ready-second.wav")
        let readySource = source(
            firstURL,
            role: "入力",
            spectrogram: spectrogram(levelDB: -30)
        )
        let waitingSource = source(secondURL, role: "補正後")

        #expect(!ComparisonVideoLaunch(
            mode: .standard,
            sources: [readySource, waitingSource]
        ).isReady)
        #expect(ComparisonVideoLaunch(
            mode: .standard,
            sources: [
                readySource,
                source(
                    secondURL,
                    role: "補正後",
                    spectrogram: spectrogram(levelDB: -24)
                ),
            ]
        ).isReady)
    }

    @Test
    func preparedAudioPreservesSamplesAndUsesContinuationOrder() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ComparisonVideoAudioTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appending(path: "first.wav")
        let secondURL = root.appending(path: "second.wav")
        let sampleRate = 8_000.0
        let sourceFrameCount = 600_000
        let outputFrameCount = 480_000
        let firstSamples = (0..<sourceFrameCount).map { Float($0) / Float(sourceFrameCount) }
        let secondSamples = (0..<sourceFrameCount).map { -Float($0) / Float(sourceFrameCount) }
        try AudioFileService.saveAudio(
            AudioSignal(channels: [firstSamples], sampleRate: sampleRate),
            to: firstURL
        )
        try AudioFileService.saveAudio(
            AudioSignal(channels: [secondSamples, secondSamples], sampleRate: sampleRate),
            to: secondURL
        )

        let prepared = try ComparisonVideoExportService().prepareAudio(
            first: source(firstURL, role: "補正後"),
            second: source(secondURL, role: "最終版"),
            startTime: 15
        )

        #expect(prepared.plan.outputDuration == 60)
        #expect(prepared.plan.sourceStartTime == 15)
        #expect(prepared.signal.frameCount == outputFrameCount)
        #expect(prepared.signal.channels.count == 2)
        #expect(prepared.signal.channels[0][0] == firstSamples[120_000])
        #expect(prepared.signal.channels[0][119_999] == firstSamples[239_999])
        #expect(prepared.signal.channels[0][120_000] == secondSamples[240_000])
        #expect(prepared.signal.channels[0][239_999] == secondSamples[359_999])
        #expect(prepared.signal.channels[0][240_000] == firstSamples[360_000])
        #expect(prepared.signal.channels[0][359_999] == firstSamples[479_999])
        #expect(prepared.signal.channels[0][360_000] == secondSamples[480_000])
        #expect(prepared.signal.channels[0][479_999] == secondSamples[599_999])
    }

    @Test
    func audioFadeAppliesTheSameEnvelopeToEveryChannel() {
        let signal = AudioSignal(
            channels: [
                Array(repeating: Float(1), count: 9),
                Array(repeating: Float(-1), count: 9),
            ],
            sampleRate: 4
        )

        let faded = ComparisonVideoExportService.applyingFade(
            to: signal,
            fadeInDuration: 1,
            fadeOutDuration: 1
        )

        #expect(faded.channels[0] == [0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.25, 0])
        #expect(faded.channels[1] == [0, -0.25, -0.5, -0.75, -1, -0.75, -0.5, -0.25, 0])
    }

    @Test
    func spectrumTimelineInterpolatesBetweenPrecomputedFrames() {
        let first = RealtimeSpectrumPoint(id: "100", frequencyHz: 100, levelDB: -80)
        let second = RealtimeSpectrumPoint(id: "100", frequencyHz: 100, levelDB: -40)
        let frame = ComparisonVideoPreparedAudio.spectrumFrame(
            in: [
                ComparisonVideoSpectrumFrame(points: [first], peakLevelsDB: [-60]),
                ComparisonVideoSpectrumFrame(points: [second], peakLevelsDB: [-20]),
            ],
            at: RealtimeSpectrumAnalyzer.timelineInterval / 2
        )

        #expect(frame.points.count == 1)
        #expect(frame.points[0].id == "100")
        #expect(frame.points[0].frequencyHz == 100)
        #expect(frame.points[0].levelDB == -60)
        #expect(frame.peakLevelsDB == [-40])
    }

    @Test
    func studioSpectrumUsesFiftySixBandsSmoothDecayPeakHoldAndFullGeometry() {
        let frequencies = spectrogram(levelDB: -20).cells
            .filter { $0.timeIndex == 0 }
            .sorted { $0.bandIndex < $1.bandIndex }
            .map { sqrt($0.frequencyStart * $0.frequencyEnd) }
        let rawTimeline = (0..<6).map { frameIndex in
            frequencies.enumerated().map { index, frequency in
                RealtimeSpectrumPoint(
                    id: "raw-\(index)",
                    frequencyHz: frequency,
                    levelDB: frameIndex == 0 ? -20 : -80
                )
            }
        }
        let frames = ComparisonVideoSpectrumProcessor.frames(
            from: rawTimeline,
            interval: 0.1
        )

        #expect(ComparisonVideoSpectrumProcessor.frequencyCount == 56)
        #expect(frequencies.count == 56)
        #expect(frames.count == 6)
        #expect(frames.allSatisfy { $0.points.count == 56 && $0.peakLevelsDB.count == 56 })
        #expect(frames[1].points[0].levelDB > -80)
        #expect(frames[1].points[0].levelDB < -20)
        #expect(frames[4].peakLevelsDB[0] == frames[0].peakLevelsDB[0])
        #expect(frames[5].peakLevelsDB[0] < frames[4].peakLevelsDB[0])

        let geometryFrame = ComparisonVideoSpectrumFrame(
            points: rawTimeline[0],
            peakLevelsDB: Array(repeating: -20, count: frequencies.count)
        )
        let dots = ComparisonVideoSpectrumGeometry.dots(
            for: geometryFrame,
            in: CGSize(width: 1_920, height: 100)
        )
        let bodyDots = dots.inactiveDots + dots.lowDots + dots.middleDots + dots.highDots
        #expect(bodyDots.count == 56 * ComparisonVideoSpectrumGeometry.dotRowCount)
        #expect(!dots.lowDots.isEmpty)
        #expect(!dots.middleDots.isEmpty)
        #expect(!dots.highDots.isEmpty)
        #expect(dots.peakDots.count == 56)
        #expect(!dots.innerGlowDots.isEmpty)
        #expect(!dots.outerGlowDots.isEmpty)
        #expect(!dots.peakGlowDots.isEmpty)
        #expect(!dots.reflectionDots.isEmpty)
        #expect((bodyDots.map(\.minX).min() ?? 0) >= 0)
        #expect((bodyDots.map(\.maxX).max() ?? 0) <= 1_920)
    }

    @Test
    func spectrumResponseUsesMagnitudeSmoothingAndZeroRespondsImmediately() throws {
        let frequencies = spectrogram(levelDB: -20).realtimeSpectrumTimeline[0]
        let quiet = frequencies.map { point in
            RealtimeSpectrumPoint(
                id: point.id,
                frequencyHz: point.frequencyHz,
                levelDB: -100
            )
        }
        let loud = frequencies.map { point in
            RealtimeSpectrumPoint(
                id: point.id,
                frequencyHz: point.frequencyHz,
                levelDB: -20
            )
        }

        let immediate = ComparisonVideoSpectrumProcessor.frames(
            from: [quiet, loud],
            interval: 0.1,
            response: 0
        )
        let smooth = ComparisonVideoSpectrumProcessor.frames(
            from: [quiet, loud],
            interval: 0.1,
            response: 0.8
        )
        let expectedMagnitude = 0.8 * pow(10, -100.0 / 20)
            + 0.2 * pow(10, -20.0 / 20)
        let expectedDB = 20 * log10(expectedMagnitude)
        let immediateLevel = try #require(immediate.last?.points.first).levelDB
        let smoothLevel = try #require(smooth.last?.points.first).levelDB

        #expect(abs(immediateLevel - (-20)) < 0.000_001)
        #expect(abs(smoothLevel - expectedDB) < 0.000_001)
        #expect(smoothLevel < immediateLevel)
    }

    @Test
    func spectrumHeightScaleChangesDotCountAndClampsAtTenRows() {
        let points = spectrogram(levelDB: -40).realtimeSpectrumTimeline[0]
        let frame = ComparisonVideoSpectrumFrame(
            points: points,
            peakLevelsDB: Array(repeating: -40, count: points.count)
        )
        let baseline = ComparisonVideoSpectrumGeometry.dots(
            for: frame,
            in: CGSize(width: 1_920, height: 100),
            heightScale: 1
        )
        let doubled = ComparisonVideoSpectrumGeometry.dots(
            for: frame,
            in: CGSize(width: 1_920, height: 100),
            heightScale: 2
        )
        let clamped = ComparisonVideoSpectrumGeometry.dots(
            for: frame,
            in: CGSize(width: 1_920, height: 100),
            heightScale: 3
        )
        let activeCount: (ComparisonVideoSpectrumDotGeometry) -> Int = {
            $0.lowDots.count + $0.middleDots.count + $0.highDots.count
        }

        #expect(activeCount(baseline) == 56 * 5)
        #expect(activeCount(doubled) == 56 * 10)
        #expect(activeCount(clamped) == 56 * 10)
    }

    @Test
    func preparationConvertsOnlyTheSecondSampleRateToTheFirstSourceRate() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ComparisonVideoSampleRateTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appending(path: "first.wav")
        let secondURL = root.appending(path: "second.wav")
        try AudioFileService.saveAudio(
            AudioSignal(channels: [Array(repeating: 0.1, count: 4_410)], sampleRate: 44_100),
            to: firstURL
        )
        try AudioFileService.saveAudio(
            AudioSignal(channels: [Array(repeating: 0.2, count: 4_800)], sampleRate: 48_000),
            to: secondURL
        )

        let prepared = try ComparisonVideoExportService().prepareAudio(
            first: source(firstURL, role: "入力"),
            second: source(secondURL, role: "補正後"),
            startTime: 0
        )

        #expect(prepared.signal.sampleRate == 44_100)
        #expect(prepared.signal.channels.count == 2)
        #expect(abs(prepared.plan.outputDuration - 0.1) < 0.000_001)
    }

    @Test
    func preparedPreviewAndExportAudioIncludesFadeAndOneSpectrumTimeline() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ComparisonVideoEffectsTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appending(path: "first.wav")
        let secondURL = root.appending(path: "second.wav")
        let sampleRate = 8_000.0
        let samples = Array(repeating: Float(0.5), count: Int(sampleRate * 16))
        try AudioFileService.saveAudio(
            AudioSignal(channels: [samples, samples], sampleRate: sampleRate),
            to: firstURL
        )
        try AudioFileService.saveAudio(
            AudioSignal(channels: [samples, samples], sampleRate: sampleRate),
            to: secondURL
        )
        let settings = ComparisonVideoDisplaySettings(
            trackTitle: "Test Song",
            firstRoleTitle: "入力",
            secondRoleTitle: "補正後",
            fadeInDuration: 0.1,
            fadeOutDuration: 0.1
        )

        let prepared = try ComparisonVideoExportService().prepareAudio(
            first: source(firstURL, role: "入力", spectrogram: spectrogram(levelDB: -30)),
            second: source(secondURL, role: "補正後", spectrogram: spectrogram(levelDB: -18)),
            startTime: 0,
            displaySettings: settings
        )

        #expect(prepared.signal.channels[0].first == 0)
        #expect(prepared.signal.channels[0].last == 0)
        #expect(prepared.signal.channels[0].contains { abs($0) > 0.4 })
        #expect(!prepared.spectrumTimeline.isEmpty)
        #expect(prepared.spectrumTimeline.count > 1)
        #expect(prepared.spectrumTimeline.allSatisfy {
            $0.points.count == 56 && $0.peakLevelsDB.count == 56
        })
        let beforeSwitch = prepared.spectrumFrame(at: 14.9).points[0].levelDB
        let afterSwitch = prepared.spectrumFrame(at: 15.1).points[0].levelDB
        #expect(beforeSwitch < -29)
        #expect(afterSwitch > beforeSwitch + 4)

        var audioFadeDisabled = settings
        audioFadeDisabled.audioFadeInEnabled = false
        audioFadeDisabled.audioFadeOutEnabled = false
        let changingSpectrum = spectrogram(
            levelDB: -30,
            realtimeLevelsDB: [-40, -10, -40, -10]
        )
        let unfaded = try ComparisonVideoExportService().prepareAudio(
            first: source(firstURL, role: "入力", spectrogram: changingSpectrum),
            second: source(secondURL, role: "補正後", spectrogram: spectrogram(levelDB: -18)),
            startTime: 0,
            displaySettings: audioFadeDisabled
        )
        #expect(unfaded.signal.channels[0].first == 0.5)
        #expect(unfaded.signal.channels[0].last == 0.5)
        #expect(
            unfaded.spectrumFrame(at: 0.1).points[0].levelDB
                - unfaded.spectrumFrame(at: 0).points[0].levelDB > 20
        )
    }

    @Test
    func selectedAudioLoadsOnlyTheRequestedNonzeroRange() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ComparisonVideoSelectedRangeTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "source.wav")
        let sampleRate = 8_000.0
        let frameCount = Int(sampleRate * 75)
        let samples = (0..<frameCount).map { index in
            Float(index) / Float(frameCount)
        }
        try AudioFileService.saveAudio(
            AudioSignal(channels: [samples], sampleRate: sampleRate),
            to: url
        )

        let selected = try ComparisonVideoExportService().loadSelectedStereoAudio(
            from: url,
            startTime: 15,
            duration: 60
        )

        #expect(selected.frameCount == Int(sampleRate * 60))
        #expect(selected.channels.count == 2)
        #expect(abs(selected.channels[0][0] - samples[Int(sampleRate * 15)]) < 0.000_001)
        #expect(abs(selected.channels[0].last! - samples.last!) < 0.000_001)
    }

    @Test
    func selectionWaveformStreamsTheWholeSourceIntoFiveHundredTwelveBuckets() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ComparisonVideoWaveformTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "source.wav")
        let samples = (0..<65_536).map { index in
            Float(sin(2 * Double.pi * Double(index) / 256)) * 0.5
        }
        try AudioFileService.saveAudio(
            AudioSignal(channels: [samples], sampleRate: 8_000),
            to: url
        )

        let waveform = try ComparisonVideoExportService().makeSelectionWaveform(
            for: source(url, role: "入力"),
            bucketCount: 512
        )

        #expect(waveform.count == 512)
        #expect(waveform.allSatisfy { $0.minimum >= -1 && $0.maximum <= 1 })
        #expect(waveform.contains { $0.rms > 0 })
    }

    @Test
    func standardVideoNeedsAtMostThirtyEightMainActorRenders() throws {
        let plan = try #require(ComparisonVideoPlan.make(
            sourceDuration: 60,
            requestedStartTime: 0
        ))
        let totalFrames = Int(plan.outputDuration * Double(ComparisonVideoExportService.frameRate))
        var cachedSourceIndices = Set<Int>()
        var renderCount = 0

        for frameIndex in 0..<totalFrames {
            let state = ComparisonVideoFrameState(
                trackTitle: "Test Song",
                firstRoleTitle: "入力",
                secondRoleTitle: "補正後",
                plan: plan,
                outputTime: Double(frameIndex) / Double(ComparisonVideoExportService.frameRate)
            )
            if let sourceIndex = ComparisonVideoExportService.cachedStaticFrameSourceIndex(for: state) {
                if cachedSourceIndices.insert(sourceIndex).inserted {
                    renderCount += 1
                }
            } else {
                renderCount += 1
            }
        }

        #expect(renderCount == 38)
        #expect(cachedSourceIndices == Set([0, 1]))
    }

    @Test
    func replacedTemporarySourceIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ComparisonVideoReplacementTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "source.wav")
        try Data([0, 1, 2]).write(to: url)
        let selectedSource = source(url, role: "補正後")
        try FileManager.default.removeItem(at: url)
        try Data([0, 1, 2, 3]).write(to: url)

        #expect(!selectedSource.matchesCurrentFile)
    }

    @MainActor
    @Test
    func exportsPlayableMP4AndPCMQuickTimeMovies() async throws {
        let preservedOutputPath = ProcessInfo.processInfo.environment[
            "VELOURA_COMPARISON_VIDEO_TEST_OUTPUT"
        ]
        let root = preservedOutputPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appending(
                path: "ComparisonVideoMovieTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if preservedOutputPath == nil {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let firstURL = root.appending(path: "first.wav")
        let secondURL = root.appending(path: "second.wav")
        let sampleRate = 48_000.0
        let frames = 12_000
        let verificationFrequencies = [90.0, 180, 360, 720, 1_440, 2_880, 5_760, 11_520]
        let firstSamples = (0..<frames).map { index in
            verificationFrequencies.reduce(0) { sample, frequency in
                sample + Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate)) * 0.025
            }
        }
        let secondSamples = (0..<frames).map { index in
            verificationFrequencies.reduce(0) { sample, frequency in
                sample + Float(cos(2 * Double.pi * frequency * Double(index) / sampleRate)) * 0.025
            }
        }
        try AudioFileService.saveAudio(
            AudioSignal(channels: [firstSamples, firstSamples], sampleRate: sampleRate),
            to: firstURL
        )
        try AudioFileService.saveAudio(
            AudioSignal(channels: [secondSamples, secondSamples], sampleRate: sampleRate),
            to: secondURL
        )
        let backgroundImage = try #require(
            NSImage(systemSymbolName: "photo.fill", accessibilityDescription: nil)
        )
        for orientation in ComparisonVideoOrientation.allCases {
            for format in ComparisonVideoFormat.allCases {
                let destination = root.appending(
                    path: "output-\(orientation.rawValue).\(format.fileExtension)"
                )
                try await ComparisonVideoExportService().export(.init(
                    first: source(
                        firstURL,
                        role: "補正後",
                        spectrogram: spectrogram(levelDB: -30)
                    ),
                    second: source(
                        secondURL,
                        role: "最終版",
                        spectrogram: spectrogram(levelDB: -18)
                    ),
                    startTime: 0,
                    orientation: orientation,
                    format: format,
                    displaySettings: ComparisonVideoDisplaySettings(
                        trackTitle: "変更したタイトル",
                        firstRoleTitle: "変更した役割A",
                        secondRoleTitle: "変更した役割B",
                        titleFontSize: 125,
                        roleFontSize: 80,
                        titlePositionX: 35,
                        titlePositionY: 40,
                        rolePositionX: 65,
                        rolePositionY: 58,
                        inspectorPositionX: 52,
                        inspectorPositionY: 76,
                        titleColor: ComparisonVideoRGBAColor(
                            red: 0.9,
                            green: 0.8,
                            blue: 0.7,
                            alpha: 1
                        ),
                        firstRoleColor: ComparisonVideoRGBAColor(
                            red: 0.6,
                            green: 0.8,
                            blue: 1,
                            alpha: 1
                        ),
                        secondRoleColor: ComparisonVideoRGBAColor(
                            red: 1,
                            green: 0.7,
                            blue: 0.8,
                            alpha: 1
                        ),
                        videoFadeInEnabled: false,
                        videoFadeOutEnabled: false,
                        backgroundColor: ComparisonVideoRGBAColor(
                            red: 0.2,
                            green: 0.1,
                            blue: 0.3,
                            alpha: 1
                        ),
                        backgroundImage: ComparisonVideoBackgroundImage(
                            image: backgroundImage,
                            fileName: "background.png"
                        ),
                        backgroundImageLayout: orientation == .landscape ? .fill : .fit
                    ),
                    firstInspectorInfo: ComparisonVideoInspectorInfo(
                        metrics: metrics(integratedLoudness: -16, truePeak: -1.5),
                        fileInfo: AudioFileInfo(
                            formatName: "WAV",
                            sampleRate: sampleRate,
                            channelCount: 2,
                            duration: 0.25,
                            bitDepth: 32,
                            isFloatingPoint: true
                        )
                    ),
                    secondInspectorInfo: ComparisonVideoInspectorInfo(
                        metrics: metrics(integratedLoudness: -14, truePeak: -1),
                        fileInfo: AudioFileInfo(
                            formatName: "WAV",
                            sampleRate: sampleRate,
                            channelCount: 2,
                            duration: 0.25,
                            bitDepth: 32,
                            isFloatingPoint: true
                        )
                    ),
                    destinationURL: destination
                ))

                let asset = AVURLAsset(url: destination)
                let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
                let audioTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
                let size = try await videoTrack.load(.naturalSize)
                let duration = try await asset.load(.duration).seconds
                #expect(size == orientation.pixelSize)
                #expect(abs(duration - 0.25) < 0.05)

                let descriptions = try await audioTrack.load(.formatDescriptions)
                let audioDescription = try #require(descriptions.first)
                let streamDescription = try #require(
                    CMAudioFormatDescriptionGetStreamBasicDescription(audioDescription)?.pointee
                )
                #expect(streamDescription.mSampleRate == sampleRate)
                #expect(streamDescription.mChannelsPerFrame == 2)
                if format == .mov {
                    #expect(streamDescription.mFormatID == kAudioFormatLinearPCM)
                } else {
                    #expect(streamDescription.mFormatID == kAudioFormatMPEG4AAC)
                }
            }
        }
    }

    @Test
    func comparisonWindowObservesSharedAppearanceSettings() throws {
        let source = try viewSource("ComparisonVideoWindowView.swift")

        #expect(source.contains(
            "@AppStorage(AppAppearanceSettings.windowBackgroundMaterialAmountKey)"
        ))
        #expect(source.contains(
            "@AppStorage(AppAppearanceSettings.windowBackgroundBlurEnabledKey)"
        ))
        #expect(source.contains(
            "@AppStorage(AppAppearanceSettings.windowBackgroundBlurLevelKey)"
        ))
        #expect(!source.contains("@State private var windowBackgroundMaterialAmount"))
        #expect(!source.contains("@State private var isWindowBackgroundBlurEnabled"))
        #expect(!source.contains("@State private var windowBackgroundBlurLevel"))
    }

    @Test
    func comparisonRangeUsesMeasuredIconPurpleAndOneLabeledTimeRange() throws {
        let source = try viewSource("ComparisonVideoRangeView.swift")

        #expect(source.contains("red: 213 / 255"))
        #expect(source.contains("green: 203 / 255"))
        #expect(source.contains("blue: 250 / 255"))
        #expect(source.contains(".stroke(waveformColor, lineWidth: 1)"))
        #expect(source.contains("選択範囲 \\(timeText(startTime))〜"))
        #expect(!source.contains(".stroke(.secondary.opacity(0.68), lineWidth: 1)"))
    }

    @Test
    func comparisonStatusIsShownAfterTheExportButtonInTheToolbar() throws {
        let source = try viewSource("ComparisonVideoWindowView.swift")
        let toolbarStart = try #require(source.range(of: ".toolbar {"))
        let statusStart = try #require(
            source.range(of: "private func exportStatus(model: ComparisonVideoWindowModel)")
        )
        let settingsSource = source[..<toolbarStart.lowerBound]
        let toolbarSource = source[toolbarStart.lowerBound..<statusStart.lowerBound]
        let statusSource = source[statusStart.lowerBound...]

        #expect(!settingsSource.contains("Text(\"動画を書き出しています…\")"))
        #expect(!settingsSource.contains("if let message = model.message"))
        #expect(toolbarSource.contains("exportStatus(model: model)"))
        #expect(toolbarSource.contains("ToolbarSpacer(.fixed, placement: .primaryAction)"))
        #expect(toolbarSource.contains(".sharedBackgroundVisibility(.hidden)"))
        #expect(statusSource.contains("Text(\"動画を書き出しています…\")"))
        #expect(statusSource.contains("if let message = model.message"))
        #expect(statusSource.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(!statusSource.contains(".lineLimit(1)"))
        #expect(!statusSource.contains(".help(message)"))
    }

    @Test
    func comparisonTitleAndRoleUseSeparateInstalledFontMenus() throws {
        let settingsSource = try viewSource("ComparisonVideoDisplaySettingsView.swift")
        let frameSource = try viewSource("ComparisonVideoFrameView.swift")

        #expect(settingsSource.contains("$model.displaySettings.titleFontFamily"))
        #expect(settingsSource.contains("$model.displaySettings.roleFontFamily"))
        #expect(settingsSource.contains("NSFontManager.shared.availableFontFamilies"))
        #expect(frameSource.contains("family: state.displaySettings.titleFontFamily"))
        #expect(frameSource.contains("family: state.displaySettings.roleFontFamily"))
        #expect(frameSource.contains("return .system(size: size, weight: .medium, design: .rounded)"))
        #expect(frameSource.contains("return .custom(family, size: size).weight(.medium)"))
    }

    @Test
    func comparisonPreviewUsesTheExportCanvasForTitleLayout() throws {
        let source = try viewSource("ComparisonVideoFrameView.swift")

        #expect(source.contains("let canvasSize = orientation.pixelSize"))
        #expect(source.contains("canvasSize.width * (orientation == .portrait ? 0.84 : 0.78)"))
        #expect(source.contains(".frame(width: canvasSize.width, height: canvasSize.height)"))
        #expect(source.contains(".scaleEffect(scale)"))
    }

    @Test
    func comparisonElementsShareOneDragPathAndInspectorRendersAsOneCanvas() throws {
        let source = try viewSource("ComparisonVideoFrameView.swift")

        #expect(source.components(separatedBy: "ComparisonVideoPositionedElement(").count - 1 == 4)
        #expect(source.components(separatedBy: "@GestureState").count - 1 == 1)
        #expect(source.components(separatedBy: ".gesture(dragGesture)").count - 1 == 1)
        #expect(source.contains(".updating($dragTranslation)"))
        #expect(source.contains(".offset(clampedTranslation)"))
        #expect(source.contains(".onEnded"))
        #expect(source.contains("Canvas(opaque: false, rendersAsynchronously: false)"))
        #expect(source.contains("context.scaleBy(x: scale, y: scale)"))
        #expect(source.contains("let labelSize = layout.labelFontSize"))
        #expect(source.contains("let valueSize = layout.valueFontSize"))
        #expect(!source.contains("orientation == .portrait ? 18 : 22"))
        #expect(!source.contains("orientation == .portrait ? 22 : 27"))
        #expect(!source.contains("ComparisonVideoInspectorOverlay"))
        #expect(!source.contains("Grid("))
        #expect(!source.contains(".equatable()"))
        #expect(!source.contains(".onChanged"))
        #expect(!source.contains("onInspectorResize"))
        #expect(!source.contains("resizeDragGesture"))
        #expect(!source.contains("arrow.up.left.and.arrow.down.right"))
        #expect(!source.contains("LazyVGrid"))
    }

    @Test
    func comparisonVisualizerUsesPrecomputedSpectrumAndKeepsStaticFrameRendering() throws {
        let frameSource = try viewSource("ComparisonVideoFrameView.swift")
        let modelSource = try projectSource("Models/ComparisonVideoWindowModel.swift")
        let serviceSource = try projectSource("Services/ComparisonVideoExportService.swift")

        #expect(frameSource.contains("ComparisonVideoSpectrumVisualizer"))
        #expect(frameSource.contains("ComparisonVideoSpectrumGeometry.dots"))
        #expect(frameSource.contains("gradientStops: state.displaySettings.visualizerGradientStops"))
        #expect(frameSource.contains("heightScale: state.displaySettings.visualizerHeightScale"))
        #expect(modelSource.contains("previewSpectrumTimeline"))
        #expect(modelSource.contains("refreshPreviewSpectrumTimeline()"))
        #expect(serviceSource.contains("first: first.spectrogram"))
        #expect(serviceSource.contains("second: second.spectrogram"))
        #expect(serviceSource.contains("first?.realtimeSpectrumTimeline"))
        #expect(serviceSource.contains("second?.realtimeSpectrumTimeline"))
        #expect(!serviceSource.contains("RealtimeSpectrumAnalyzer.timeline("))
        #expect(serviceSource.contains("showsDynamicOverlays: false"))
        #expect(serviceSource.contains("drawDynamicOverlays("))
        #expect(serviceSource.contains("prepared.spectrumFrame(at: outputTime)"))
        #expect(serviceSource.contains("ComparisonVideoSpectrumGeometry.dots"))
        #expect(serviceSource.contains("response: displaySettings?.visualizerResponse ?? 0.8"))
        #expect(serviceSource.contains("heightScale: settings.visualizerHeightScale"))
        #expect(serviceSource.contains("let stops = settings.visualizerGradientStops"))
        #expect(serviceSource.contains("locations: stops.map { CGFloat($0.location) }"))
    }

    @Test
    func comparisonVisualizerPaletteUsesTheSharedSegmentedControl() throws {
        let source = try viewSource("ComparisonVideoDisplaySettingsView.swift")

        #expect(source.contains("ComparisonVideoVisualizerPaletteMode.allCases"))
        #expect(source.contains("$model.displaySettings.visualizerPaletteMode"))
        #expect(source.contains("model.displaySettings.visualizerPaletteMode == .custom"))
        #expect(source.contains("Text(\"3色グラデーション\")"))
    }

    @Test
    func comparisonVisualizerScaleUsesPercentageSliderNumberAndFineAdjustment() throws {
        let source = try viewSource("ComparisonVideoDisplaySettingsView.swift")

        #expect(source.contains("$model.displaySettings.visualizerScale"))
        #expect(source.contains("Text(\"拡大率\")"))
        #expect(source.contains("Text(\"%\")"))
        #expect(source.components(separatedBy: "in: 25...200").count - 1 == 2)
        #expect(source.components(separatedBy: "step: 1").count - 1 >= 2)
        #expect(source.contains("get: { value.wrappedValue * 100 }"))
        #expect(source.contains("set: { value.wrappedValue = $0 / 100 }"))
    }

    @Test
    func comparisonVisualizerResponseAndHeightScaleUsePercentageControls() throws {
        let source = try viewSource("ComparisonVideoDisplaySettingsView.swift")

        #expect(source.contains("title: \"反応速度\""))
        #expect(source.contains("range: 0...99"))
        #expect(source.contains("高いほど滑らかに動きます"))
        #expect(source.contains("title: \"高さスケール\""))
        #expect(source.contains("range: 25...300"))
        #expect(source.contains("音量に対するドットの高さを調整します"))
    }

    @Test
    func comparisonPositionControlsUseNormalizedSlidersNumbersAndFineAdjustment() throws {
        let source = try viewSource("ComparisonVideoDisplaySettingsView.swift")

        #expect(source.contains("positionAxisControl(title: \"水平位置\""))
        #expect(source.contains("positionAxisControl(title: \"垂直位置\""))
        #expect(source.contains("Slider(value: normalizedValue, in: 0...1, step: 0.01)"))
        #expect(source.contains("format: .number.precision(.fractionLength(2))"))
        #expect(source.contains("value: normalizedValue,\n                in: 0...1,\n                step: 0.01"))
        #expect(source.contains("get: { value.wrappedValue / 100 }"))
        #expect(source.contains("* 100"))
        #expect(!source.contains("numericPositionField"))
    }

    @Test
    func comparisonPreviewDoesNotReinstallAHostedOverlayForStateChanges() throws {
        let source = try viewSource("ComparisonVideoPlayerView.swift")
        let modelFileSource = try projectSource("Models/ComparisonVideoWindowModel.swift")
        let serviceFileSource = try projectSource("Services/ComparisonVideoExportService.swift")

        #expect(source.contains("ComparisonVideoCanvasView"))
        #expect(source.contains("ComparisonVideoFrameView("))
        #expect(!source.contains("NSViewRepresentable"))
        #expect(!source.contains("NSHostingView"))
        #expect(!source.contains("AnyView"))
        #expect(!source.contains("updateNSView"))
        #expect(!source.contains("rootView ="))
        #expect(modelFileSource.contains("let player = AVPlayer(url: url)"))
        #expect(!modelFileSource.contains("previewVideoFileURL"))
        #expect(!modelFileSource.contains("makePreviewPlayer"))
        #expect(!serviceFileSource.contains("writePreviewVideo"))
    }

    @Test
    func onlyTheComparisonWindowHidesWhenTheAppDeactivates() throws {
        let comparisonSource = try viewSource("ComparisonVideoWindowView.swift")
        let rootSource = try viewSource("VelouraRootView.swift")
        let aboutSource = try viewSource("VelouraAboutView.swift")

        #expect(comparisonSource.contains("hidesOnDeactivate: true"))
        #expect(!rootSource.contains("hidesOnDeactivate: true"))
        #expect(!aboutSource.contains("hidesOnDeactivate: true"))
    }

    @Test
    func comparisonBackgroundImageLayoutCannotResizeTheExportCanvas() throws {
        let source = try viewSource("ComparisonVideoFrameView.swift")

        #expect(source.contains("ComparisonVideoBackgroundView("))
        #expect(source.contains("canvasSize: canvasSize"))
        #expect(source.contains("let canvasSize: CGSize"))
        #expect(source.contains(".frame(width: canvasSize.width, height: canvasSize.height)\n        .overlay"))
    }

    @MainActor
    @Test
    func backgroundImageLayoutKeepsRenderedTextAtTheSameCoordinates() throws {
        let plan = try #require(ComparisonVideoPlan.make(
            sourceDuration: 20,
            requestedStartTime: 0
        ))
        let backgroundImage = NSImage(size: NSSize(width: 300, height: 900))
        backgroundImage.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: backgroundImage.size))
        backgroundImage.unlockFocus()

        var settings = ComparisonVideoDisplaySettings(
            trackTitle: "TITLE",
            firstRoleTitle: "ROLE",
            secondRoleTitle: "SECOND",
            titleFontSize: 120,
            roleFontSize: 96,
            titlePositionX: 32,
            titlePositionY: 38,
            rolePositionX: 68,
            rolePositionY: 62,
            titleColor: ComparisonVideoRGBAColor(red: 1, green: 0, blue: 0, alpha: 1),
            firstRoleColor: ComparisonVideoRGBAColor(red: 0, green: 1, blue: 0, alpha: 1),
            backgroundColor: ComparisonVideoRGBAColor(red: 0, green: 0, blue: 1, alpha: 1),
            backgroundImage: ComparisonVideoBackgroundImage(
                image: backgroundImage,
                fileName: "tall-background.png"
            ),
            backgroundImageLayout: .fill
        )

        let fillImage = try renderedComparisonFrame(settings: settings, plan: plan)
        settings.backgroundImageLayout = .fit
        let fitImage = try renderedComparisonFrame(settings: settings, plan: plan)

        #expect(try colorBounds(in: fillImage, color: .red) == colorBounds(in: fitImage, color: .red))
        #expect(try colorBounds(in: fillImage, color: .green) == colorBounds(in: fitImage, color: .green))
        #expect(try lightPixelBounds(in: fillImage) == lightPixelBounds(in: fitImage))
    }

    private func source(
        _ url: URL,
        role: String,
        spectrogram: SpectrogramSnapshot? = nil
    ) -> ComparisonVideoSource {
        ComparisonVideoSource(
            fileURL: url,
            trackTitle: "Test Song",
            roleTitle: role,
            spectrogram: spectrogram
        )
    }

    private func spectrogram(
        levelDB: Double,
        realtimeLevelsDB: [Double]? = nil
    ) -> SpectrogramSnapshot {
        let timeBucketCount = 4
        let frequencyBucketCount = 56
        let duration: TimeInterval = 60
        let minimumFrequency = 80.0
        let maximumFrequency = 24_000.0
        let cells = (0..<timeBucketCount).flatMap { timeIndex in
            (0..<frequencyBucketCount).map { bandIndex in
                let lower = minimumFrequency * pow(
                    maximumFrequency / minimumFrequency,
                    Double(bandIndex) / Double(frequencyBucketCount)
                )
                let upper = minimumFrequency * pow(
                    maximumFrequency / minimumFrequency,
                    Double(bandIndex + 1) / Double(frequencyBucketCount)
                )
                return SpectrogramCell(
                    id: "\(timeIndex)-\(bandIndex)",
                    timeIndex: timeIndex,
                    bandIndex: bandIndex,
                    timeStart: duration * Double(timeIndex) / Double(timeBucketCount),
                    timeEnd: duration * Double(timeIndex + 1) / Double(timeBucketCount),
                    frequencyStart: lower,
                    frequencyEnd: upper,
                    levelDB: levelDB
                )
            }
        }
        let frequencies = (0..<frequencyBucketCount).map { bandIndex in
            let lower = minimumFrequency * pow(
                maximumFrequency / minimumFrequency,
                Double(bandIndex) / Double(frequencyBucketCount)
            )
            let upper = minimumFrequency * pow(
                maximumFrequency / minimumFrequency,
                Double(bandIndex + 1) / Double(frequencyBucketCount)
            )
            return sqrt(lower * upper)
        }
        let timelineLevels = realtimeLevelsDB ?? Array(
            repeating: levelDB,
            count: timeBucketCount
        )
        let realtimeSpectrumTimeline = timelineLevels.map { timelineLevel in
            frequencies.enumerated().map { bandIndex, frequency in
                RealtimeSpectrumPoint(
                    id: "comparison-\(bandIndex)",
                    frequencyHz: frequency,
                    levelDB: timelineLevel
                )
            }
        }
        return SpectrogramSnapshot(
            cells: cells,
            timeBucketCount: timeBucketCount,
            frequencyBucketCount: frequencyBucketCount,
            duration: duration,
            minLevelDB: -100,
            maxLevelDB: 0,
            realtimeSpectrumTimeline: realtimeSpectrumTimeline
        )
    }

    @MainActor
    private func renderedComparisonFrame(
        settings: ComparisonVideoDisplaySettings,
        plan: ComparisonVideoPlan
    ) throws -> CGImage {
        let orientation = ComparisonVideoOrientation.landscape
        let previewSize = CGSize(width: 480, height: 270)
        let renderer = ImageRenderer(
            content: ComparisonVideoFrameView(
                state: ComparisonVideoFrameState(
                    displaySettings: settings,
                    firstInspectorInfo: nil,
                    secondInspectorInfo: nil,
                    plan: plan,
                    outputTime: 1
                ),
                orientation: orientation
            )
            .frame(width: previewSize.width, height: previewSize.height)
        )
        renderer.proposedSize = ProposedViewSize(previewSize)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.colorMode = .nonLinear
        return try #require(renderer.cgImage)
    }

    private func colorBounds(in image: CGImage, color: NSColor) throws -> CGRect {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let target = try #require(color.usingColorSpace(.sRGB))
        var minimumX = bitmap.pixelsWide
        var minimumY = bitmap.pixelsHigh
        var maximumX = -1
        var maximumY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let matches: Bool
                if target.redComponent > target.greenComponent {
                    matches = pixel.redComponent > 0.75
                        && pixel.greenComponent < 0.35
                        && pixel.blueComponent < 0.35
                } else {
                    matches = pixel.greenComponent > 0.75
                        && pixel.redComponent < 0.35
                        && pixel.blueComponent < 0.35
                }
                guard matches else { continue }
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }

        return try #require(
            maximumX >= minimumX && maximumY >= minimumY
                ? CGRect(
                    x: minimumX,
                    y: minimumY,
                    width: maximumX - minimumX + 1,
                    height: maximumY - minimumY + 1
                )
                : nil
        )
    }

    private func lightPixelBounds(in image: CGImage) throws -> CGRect {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var minimumX = bitmap.pixelsWide
        var minimumY = bitmap.pixelsHigh
        var maximumX = -1
        var maximumY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                guard pixel.redComponent > 0.75,
                      pixel.greenComponent > 0.75,
                      pixel.blueComponent > 0.75 else { continue }
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }

        return try #require(
            maximumX >= minimumX && maximumY >= minimumY
                ? CGRect(
                    x: minimumX,
                    y: minimumY,
                    width: maximumX - minimumX + 1,
                    height: maximumY - minimumY + 1
                )
                : nil
        )
    }

    private func metrics(
        integratedLoudness: Double,
        truePeak: Double
    ) -> AudioMetricSnapshot {
        AudioMetricSnapshot(
            duration: 60,
            peakDBFS: truePeak,
            rmsDBFS: integratedLoudness,
            crestFactorDB: 12,
            loudnessRangeLU: 8,
            integratedLoudnessLUFS: integratedLoudness,
            truePeakDBFS: truePeak,
            stereoWidth: 0.6,
            stereoCorrelation: 0.5,
            stereoCorrelationTimeline: [],
            stereoCorrelationTimelineStatus: .unavailable,
            harshnessScore: 0,
            centroidHz: 2_000,
            hf12Ratio: 0,
            hf16Ratio: 0,
            hf18Ratio: 0,
            bandEnergies: [],
            masteringBandEnergies: [],
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: []
        )
    }

    private func viewSource(_ fileName: String) throws -> String {
        try projectSource("Views/\(fileName)")
    }

    private func projectSource(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appending(
            path: "Sources/VelouraLucent/\(relativePath)"
        )
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
