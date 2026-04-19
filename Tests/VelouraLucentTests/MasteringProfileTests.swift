import Testing
@testable import VelouraLucent

struct MasteringProfileTests {
    @Test
    func profilesExposeDifferentSettings() {
        let natural = MasteringProfile.natural.settings
        let streaming = MasteringProfile.streaming.settings
        let forward = MasteringProfile.forward.settings

        #expect(natural.targetLoudness < streaming.targetLoudness)
        #expect(streaming.targetLoudness < forward.targetLoudness)
        #expect(natural.saturationAmount < forward.saturationAmount)
        #expect(streaming.stereoWidth >= natural.stereoWidth)
        #expect(natural.multibandCompression.low.ratio < forward.multibandCompression.low.ratio)
        #expect(streaming.multibandCompression.high.attackMs < natural.multibandCompression.high.attackMs)
        #expect(natural.deEsserAmount < forward.deEsserAmount)
        #expect(streaming.lowMidGain >= natural.lowMidGain)
    }
}
