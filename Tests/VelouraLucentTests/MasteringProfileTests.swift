import Testing
@testable import VelouraLucent

struct MasteringProfileTests {
    @Test
    func profilesExposeDifferentSettings() {
        let naturalProfile = MasteringProfile.natural
        let streamingProfile = MasteringProfile.streaming
        let forwardProfile = MasteringProfile.forward

        let natural = naturalProfile.settings
        let streaming = streamingProfile.settings
        let forward = forwardProfile.settings

        #expect(natural.targetLoudness < streaming.targetLoudness)
        #expect(streaming.targetLoudness < forward.targetLoudness)
        #expect(streaming.targetLoudness == -14.5)
        #expect(forward.targetLoudness <= -13.8)
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
    }
}
