// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation
import SPFKAudioBase
import SPFKBase
import Testing

@testable import SPFKWaveform

@Suite
final class WaveformChannelLaneTests {
    private let left: [Float] = [0.5, -0.25, 1, 0, 0.125]
    private let right: [Float] = [0.25, 0.75, -1, 0.5, 0]

    private var data: WaveformData {
        WaveformData(floatChannelData: [left, right], samplesPerPoint: 32, audioDuration: 1, sampleRate: 160)
    }

    @Test func noneIsTheChannelsUnchanged() {
        #expect(data.lanes(for: .none) == [left, right])
    }

    @Test func swapReversesAndOneChannelIsThatChannel() {
        #expect(data.lanes(for: .swap) == [right, left])
        #expect(data.lanes(for: .mono(.left)) == [left])
        #expect(data.lanes(for: .mono(.right)) == [right])
    }

    @Test func monoIsTheAveragePointForPoint() {
        #expect(data.lanes(for: .mono(.average)) == [zip(left, right).map { ($0 + $1) / 2 }])
    }

    @Test func encodeThenDecodeAtUnitWidthIsTheInput() {
        let encoded = data.lanes(for: .midSideEncode)
        #expect(WaveformData.lanes(encoded, for: .midSideDecode(width: 1)) == [left, right])
    }

    @Test func monoInputIsUnchanged() {
        let mono = WaveformData(floatChannelData: [left], samplesPerPoint: 32, audioDuration: 1, sampleRate: 160)
        #expect(mono.lanes(for: .mono(.average)) == [left])
        #expect(mono.lanes(for: .swap) == [left])
    }
}
