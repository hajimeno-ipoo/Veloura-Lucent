import AVFoundation
import Foundation
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

        let sources = ComparisonVideoSourceCatalog.standard(job: job)

        #expect(sources.map(\.fileURL) == [
            input.standardizedFileURL,
            corrected.standardizedFileURL,
            mastered.standardizedFileURL,
        ])
        #expect(sources.map(\.trackTitle) == ["Test Song", "Test Song", "Test Song"])
        #expect(sources.map(\.roleTitle) == ["入力", "補正後", "最終版"])
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
            ]
        )

        #expect(sources.map(\.fileURL) == [inputURL.standardizedFileURL, validURL.standardizedFileURL])
        #expect(sources.map(\.trackTitle) == ["Stem Song", "Stem Song"])
        #expect(sources.map(\.roleTitle) == ["入力", "ボーカル（補正済み）"])
        #expect(!sources.contains { $0.roleTitle == "変換済み入力" })
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
        let firstSamples = (0..<frames).map { index in
            Float(sin(2 * Double.pi * 220 * Double(index) / sampleRate)) * 0.2
        }
        let secondSamples = (0..<frames).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate)) * 0.2
        }
        try AudioFileService.saveAudio(
            AudioSignal(channels: [firstSamples, firstSamples], sampleRate: sampleRate),
            to: firstURL
        )
        try AudioFileService.saveAudio(
            AudioSignal(channels: [secondSamples, secondSamples], sampleRate: sampleRate),
            to: secondURL
        )
        for orientation in ComparisonVideoOrientation.allCases {
            for format in ComparisonVideoFormat.allCases {
                let destination = root.appending(
                    path: "output-\(orientation.rawValue).\(format.fileExtension)"
                )
                try await ComparisonVideoExportService().export(.init(
                    first: source(firstURL, role: "補正後"),
                    second: source(secondURL, role: "最終版"),
                    startTime: 0,
                    orientation: orientation,
                    format: format,
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
    func previewVideoProvidesARealVideoTrackForTheNativePlayer() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ComparisonVideoPreviewTrackTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "preview.mov")

        try await ComparisonVideoExportService().writePreviewVideo(
            duration: 60,
            to: destination
        )

        let asset = AVURLAsset(url: destination)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration).seconds
        #expect(size == CGSize(width: 16, height: 16))
        #expect(abs(duration - 60) < 0.05)
    }

    @Test
    func comparisonWindowObservesSharedAppearanceSettings() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appending(
            path: "Sources/VelouraLucent/Views/ComparisonVideoWindowView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

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

    private func source(_ url: URL, role: String) -> ComparisonVideoSource {
        ComparisonVideoSource(fileURL: url, trackTitle: "Test Song", roleTitle: role)
    }
}
