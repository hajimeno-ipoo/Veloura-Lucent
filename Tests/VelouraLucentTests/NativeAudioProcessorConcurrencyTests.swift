import Foundation
import Testing
@testable import VelouraLucent

struct NativeAudioProcessorConcurrencyTests {
    @Test
    func concurrentChannelMappingMatchesSerialMapping() {
        let channels = makeChannels(channelCount: 4, frameCount: 2_048)

        let serial = channels.map(testTransform)
        let concurrent = mapChannelsConcurrently(channels, transform: testTransform)

        #expect(concurrent.count == serial.count)
        for index in serial.indices {
            #expect(concurrent[index] == serial[index])
        }
    }

    @Test
    func concurrentChannelMappingPreservesChannelOrder() {
        let channels = (0..<8).map { channelIndex in
            Array(repeating: Float(channelIndex), count: 32)
        }

        let concurrent = mapChannelsConcurrently(channels) { channel in
            channel.map { $0 + 100 }
        }

        #expect(concurrent.count == channels.count)
        for index in concurrent.indices {
            #expect(concurrent[index].allSatisfy { $0 == Float(index + 100) })
        }
    }

    private func makeChannels(channelCount: Int, frameCount: Int) -> [[Float]] {
        (0..<channelCount).map { channelIndex in
            (0..<frameCount).map { frameIndex in
                let phase = Double(frameIndex + channelIndex * 31) / 64.0
                return Float(sin(phase) * 0.25 + cos(phase * 0.37) * 0.05)
            }
        }
    }

    private func testTransform(_ channel: [Float]) -> [Float] {
        channel.enumerated().map { index, sample in
            let gain = Float((index % 17) + 1) / 17.0
            return tanhf(sample * gain)
        }
    }
}
