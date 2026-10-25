// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation

extension WaveformData {
    /// The waveform of the reversed file: each channel's points in reverse order. A frame count that
    /// is not a multiple of `samplesPerPoint` misplaces it by at most one point.
    public func reversed() -> WaveformData {
        WaveformData(
            floatChannelData: floatChannelData.map { Array($0.reversed()) },
            samplesPerPoint: samplesPerPoint,
            audioDuration: audioDuration,
            sampleRate: sampleRate
        )
    }
}
