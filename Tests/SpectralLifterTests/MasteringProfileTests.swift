import Testing
@testable import SpectralLifter

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
    }
}
