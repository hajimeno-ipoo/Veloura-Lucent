import Foundation

extension MasteringProcessor {
    func applyStereoWidth(signal: AudioSignal, targetWidth: Float) -> AudioSignal {
        guard signal.channels.count >= 2 else { return signal }
        let left = signal.channels[0]
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else { return signal }

        let lowLeft = SpectralDSP.lowPass(left, cutoff: 180, sampleRate: signal.sampleRate)
        let lowRight = SpectralDSP.lowPass(right, cutoff: 180, sampleRate: signal.sampleRate)
        let highLeft = zip(left, lowLeft).map(-)
        let highRight = zip(right, lowRight).map(-)

        var widenedLeft = Array(repeating: Float.zero, count: count)
        var widenedRight = Array(repeating: Float.zero, count: count)
        for index in 0..<count {
            let highMid = (highLeft[index] + highRight[index]) * 0.5
            let highSide = (highLeft[index] - highRight[index]) * 0.5 * targetWidth
            widenedLeft[index] = lowLeft[index] + highMid + highSide
            widenedRight[index] = lowRight[index] + highMid - highSide
        }

        var channels = signal.channels
        channels[0] = widenedLeft
        channels[1] = widenedRight
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }
}
