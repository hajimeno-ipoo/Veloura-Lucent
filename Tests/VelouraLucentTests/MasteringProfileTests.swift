import Testing
@testable import VelouraLucent

struct MasteringProfileTests {
    @Test
    func profilesExposeDifferentSettings() {
        let naturalProfile = MasteringProfile.natural
        let streamingProfile = MasteringProfile.streaming
        let forwardProfile = MasteringProfile.forward
        let safeAIProfile = MasteringProfile.safeAIStreaming
        let youtubeSpotifyProfile = MasteringProfile.youtubeSpotify
        let releaseLoudProfile = MasteringProfile.releaseLoud

        let natural = naturalProfile.settings
        let streaming = streamingProfile.settings
        let forward = forwardProfile.settings
        let safeAI = safeAIProfile.settings
        let youtubeSpotify = youtubeSpotifyProfile.settings
        let releaseLoud = releaseLoudProfile.settings

        #expect(natural.targetLoudness < streaming.targetLoudness)
        #expect(streaming.targetLoudness < forward.targetLoudness)
        #expect(streaming.targetLoudness == -16.7)
        #expect(forward.targetLoudness <= -14.8)
        #expect(safeAI.targetLoudness == -14.5)
        #expect(safeAI.peakCeilingDB == -1.2)
        #expect(safeAI.finishingIntensity == 0.65)
        #expect(youtubeSpotify.targetLoudness == -14.0)
        #expect(youtubeSpotify.peakCeilingDB == -1.0)
        #expect(youtubeSpotify.finishingIntensity == 0.85)
        #expect(releaseLoud.targetLoudness == -12.0)
        #expect(releaseLoud.peakCeilingDB == -1.0)
        #expect(releaseLoud.finishingIntensity == 0.95)
        #expect(streaming.lowShelfGain == 0.72)
        #expect(streaming.lowMidGain == -0.34)
        #expect(streaming.highShelfGain == 0.48)
        #expect(natural.saturationAmount < forward.saturationAmount)
        #expect(forward.saturationAmount <= 0.12)
        #expect(natural.dynamicsRetention > streaming.dynamicsRetention)
        #expect(streaming.dynamicsRetention > forward.dynamicsRetention)
        #expect(natural.finishingIntensity < streaming.finishingIntensity)
        #expect(streaming.finishingIntensity < forward.finishingIntensity)
        #expect(streaming.stereoWidth >= natural.stereoWidth)
        #expect(natural.multibandCompression.low.ratio < forward.multibandCompression.low.ratio)
        #expect(streaming.multibandCompression.high.attackMs < natural.multibandCompression.high.attackMs)
        #expect(natural.deEsserAmount < forward.deEsserAmount)
        #expect(streaming.lowMidGain <= natural.lowMidGain)
        #expect(naturalProfile.title == "自然")
        #expect(streamingProfile.title == "聴きやすく整える")
        #expect(forwardProfile.title == "押し出し強め")
        #expect(safeAIProfile.title == "安全AI配信")
        #expect(youtubeSpotifyProfile.title == "YouTube / Spotify向け")
        #expect(releaseLoudProfile.title == "リリース音圧重視")
        #expect(MasteringProfile.allCases == [
            .natural,
            .streaming,
            .forward,
            .safeAIStreaming,
            .youtubeSpotify,
            .releaseLoud
        ])
    }

    @Test
    func aggressiveMasteringSettingsExposeWarningsWithoutChangingRanges() {
        var settings = MasteringProfile.streaming.settings

        #expect(settings.aggressiveSettingWarnings.isEmpty)

        settings.targetLoudness = -11.8
        #expect(settings.aggressiveSettingWarnings.contains("音圧重視。強弱が少なくなる場合があります。"))

        let releaseSettings = MasteringProfile.releaseLoud.settings
        #expect(releaseSettings.aggressiveSettingWarnings.contains("音圧重視。強弱が少なくなる場合があります。"))

        settings.peakCeilingDB = -0.6
        #expect(settings.aggressiveSettingWarnings.contains("歪みやすい設定です。配信や再生環境によって音割れする可能性があります。"))
    }

    @Test
    func profilesExposePresetHelpTextWithTargetAndPeakValues() {
        #expect(MasteringProfile.natural.presetTargetText == "目安: -17.4 LUFS / True Peak上限: -1.2 dBFS")
        #expect(MasteringProfile.streaming.presetTargetText == "目安: -16.7 LUFS / True Peak上限: -1.5 dBFS")
        #expect(MasteringProfile.forward.presetTargetText == "目安: -14.8 LUFS / True Peak上限: -0.9 dBFS")
        #expect(MasteringProfile.safeAIStreaming.presetTargetText == "目安: -14.5 LUFS / True Peak上限: -1.2 dBFS")
        #expect(MasteringProfile.youtubeSpotify.presetTargetText == "目安: -14.0 LUFS / True Peak上限: -1.0 dBFS")
        #expect(MasteringProfile.releaseLoud.presetTargetText == "目安: -12.0 LUFS / True Peak上限: -1.0 dBFS")
        #expect(MasteringProfile.youtubeSpotify.presetHelpText == "YouTubeやSpotify向けに、扱いやすい音量を狙います。")
        #expect(MasteringProfile.releaseLoud.presetHelpText == "音圧を重視します。強弱が少なくなる場合があります。")
        #expect(MasteringProfile.allCases.allSatisfy { !$0.presetHelpText.contains("必ず") })
    }

    @Test
    func profilesExposeLoudnessAdjustmentPolicies() {
        let natural = MasteringProfile.natural.settings.loudnessAdjustmentPolicy
        let streaming = MasteringProfile.streaming.settings.loudnessAdjustmentPolicy
        let forward = MasteringProfile.forward.settings.loudnessAdjustmentPolicy
        let safeAI = MasteringProfile.safeAIStreaming.settings.loudnessAdjustmentPolicy
        let youtubeSpotify = MasteringProfile.youtubeSpotify.settings.loudnessAdjustmentPolicy
        let releaseLoud = MasteringProfile.releaseLoud.settings.loudnessAdjustmentPolicy

        #expect(natural.label == "自然")
        #expect(natural.maxBoostDB == 1.5)
        #expect(natural.maxCutDB == 1.0)
        #expect(natural.finalRestoreLimitDB == 1.5)
        #expect(natural.targetOvershootLimitDB == 0.75)
        #expect(streaming.label == "聴きやすく整える")
        #expect(streaming.maxBoostDB == 3.0)
        #expect(streaming.maxCutDB == 1.5)
        #expect(streaming.finalRestoreLimitDB == 2.0)
        #expect(streaming.targetOvershootLimitDB == 1.25)
        #expect(forward.label == "押し出し強め")
        #expect(forward.maxBoostDB == 4.5)
        #expect(forward.maxCutDB == 2.0)
        #expect(forward.finalRestoreLimitDB == 2.0)
        #expect(forward.targetOvershootLimitDB == 1.25)
        #expect(safeAI.label == "安全AI配信")
        #expect(safeAI.maxBoostDB == 4.0)
        #expect(safeAI.maxCutDB == 1.5)
        #expect(safeAI.finalRestoreLimitDB == 2.5)
        #expect(safeAI.targetOvershootLimitDB == 0.75)
        #expect(youtubeSpotify.label == "YouTube / Spotify向け")
        #expect(youtubeSpotify.maxBoostDB == 5.0)
        #expect(youtubeSpotify.maxCutDB == 2.0)
        #expect(youtubeSpotify.finalRestoreLimitDB == 3.0)
        #expect(youtubeSpotify.targetOvershootLimitDB == 0.75)
        #expect(releaseLoud.label == "リリース音圧重視")
        #expect(releaseLoud.maxBoostDB == 6.0)
        #expect(releaseLoud.maxCutDB == 2.0)
        #expect(releaseLoud.finalRestoreLimitDB == 3.0)
        #expect(releaseLoud.targetOvershootLimitDB == 2.0)
        #expect([natural, streaming, forward, safeAI, youtubeSpotify, releaseLoud].allSatisfy { $0.deadbandDB == 0.5 })
    }

    @Test
    func finishingIntensityBoundariesSelectExpectedPolicies() {
        var settings = MasteringProfile.streaming.settings

        settings.finishingIntensity = 0.45
        #expect(settings.loudnessAdjustmentPolicy.label == "自然")

        settings.finishingIntensity = 0.46
        #expect(settings.loudnessAdjustmentPolicy.label == "聴きやすく整える")

        settings.finishingIntensity = 0.60
        #expect(settings.loudnessAdjustmentPolicy.label == "安全AI配信")

        settings.finishingIntensity = 0.70
        #expect(settings.loudnessAdjustmentPolicy.label == "押し出し強め")

        settings.finishingIntensity = 0.80
        #expect(settings.loudnessAdjustmentPolicy.label == "YouTube / Spotify向け")

        settings.finishingIntensity = 0.90
        #expect(settings.loudnessAdjustmentPolicy.label == "リリース音圧重視")
    }
}
