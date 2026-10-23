// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Accelerate
import Foundation
import SPFKAudioBase
import SPFKBase

extension WaveformData {
    /// The lanes to draw while `operation` is pending, derived from the stored points.
    public func lanes(for operation: ChannelOperation) -> FloatChannelData {
        Self.lanes(floatChannelData, for: operation)
    }

    /// Swap, left and right are exact. Mono, encode and decode combine each channel's per-point peak,
    /// which approximates the peak of the combined signal: the two peaks may come from different
    /// samples. Anything but two channels is returned unchanged.
    public static func lanes(_ channels: FloatChannelData, for operation: ChannelOperation) -> FloatChannelData {
        guard channels.count == 2, channels[0].count == channels[1].count else { return channels }

        let first = channels[0]
        let second = channels[1]

        switch operation {
        case .none:
            return channels

        case .swap:
            return [second, first]

        case .mono(.average):
            return [vDSP.multiply(0.5, vDSP.add(first, second))]

        case .mono(.left):
            return [first]

        case .mono(.right):
            return [second]

        case let .midSideDecode(width):
            let side = vDSP.multiply(width, second)
            return [vDSP.add(first, side), vDSP.subtract(first, side)]

        case .midSideEncode:
            return [
                vDSP.multiply(0.5, vDSP.add(first, second)),
                vDSP.multiply(0.5, vDSP.subtract(first, second)),
            ]
        }
    }
}
