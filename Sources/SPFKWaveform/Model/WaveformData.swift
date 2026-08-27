// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Accelerate
import Foundation
import SPFKBase

/// Data needed for drawing waveforms
public struct WaveformData: Hashable, Codable, Sendable {
    public let floatChannelData: FloatChannelData
    public let audioDuration: TimeInterval
    public let sampleRate: Double
    public let samplesPerPoint: Int

    // MARK: Derived values

    public let samplesPerSecond: Double
    public let resolution: WaveformDrawingResolution

    public var channelCount: Int {
        floatChannelData.count
    }

    public init(
        floatChannelData: FloatChannelData = .init(),
        samplesPerPoint: Int = 0,
        audioDuration: TimeInterval = 0,
        sampleRate: Double = 0
    ) {
        self.floatChannelData = floatChannelData
        self.samplesPerPoint = samplesPerPoint
        self.audioDuration = audioDuration
        self.sampleRate = sampleRate

        samplesPerSecond = sampleRate / samplesPerPoint.double
        resolution = WaveformDrawingResolution(samplesPerPoint: samplesPerPoint)
    }

    /// Extract a time range of audio data or the entire data if it matches
    /// 0 ... audioDuration
    ///
    /// - Parameter timeRange: time range to extract
    /// - Returns: FloatChannelData suitable for drawing
    public func subdata(in timeRange: ClosedRange<TimeInterval>) throws -> FloatChannelData {
        let timeRange = timeRange.clamped(to: 0 ... audioDuration)

        guard timeRange != 0 ... audioDuration else {
            return floatChannelData
        }

        let startTime = timeRange.lowerBound.clamped(
            to: 0 ... audioDuration - 0.01
        )

        let endTime = timeRange.upperBound.clamped(
            to: startTime + 0.01 ... audioDuration
        )

        guard startTime < endTime else {
            throw NSError(description: "audioDuration: \(audioDuration), invalid edit times \(startTime)...\(endTime)")
        }

        let startIndex = Int(startTime * samplesPerSecond)
        let endIndex = Int(endTime * samplesPerSecond)

        return try edit(startIndex: startIndex, endIndex: endIndex)
    }

    func edit(startIndex: Int, endIndex: Int) throws -> FloatChannelData {
        var subdata = FloatChannelData()
        subdata.reserveCapacity(channelCount)

        for n in 0 ..< floatChannelData.count {
            subdata.append(Array(floatChannelData[n][startIndex ..< endIndex]))
            try Task.checkCancellation()
        }

        return subdata
    }
}
