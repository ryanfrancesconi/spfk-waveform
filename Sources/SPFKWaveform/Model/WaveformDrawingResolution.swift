// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation

public enum WaveformDrawingResolution: CaseIterable, Equatable, Codable, Sendable {
    case low
    case medium
    case high
    case veryHigh
    case lossless

    /// The amount of samples to buffer for a maximumMagnitude of for each point
    public var samplesPerPoint: Int {
        switch self {
        case .low:
            128
        case .medium:
            64
        case .high:
            32
        case .veryHigh:
            16
        case .lossless:
            1
        }
    }

    /// Chooses a suggested value based on an audio file's duration
    /// - Parameter duration: the audio duration
    public init(duration: TimeInterval) {
        let duration = max(0, duration)

        switch duration {
        case 0 ..< 2:
            self = .lossless

        case 2 ..< 10:
            self = .veryHigh

        case 10 ..< 120:
            self = .high

        case 120...:
            self = .medium

        default:
            self = .medium
        }
    }

    /// Returns an exact match or averages into a range to one of the preset values
    public init(samplesPerPoint: Int) {
        let samplesPerPoint = max(1, samplesPerPoint)

        for item in Self.allCases where item.samplesPerPoint == samplesPerPoint {
            self = item
            return
        }

        // samplesPerPoint: low=128, medium=64, high=32, veryHigh=16, lossless=1
        // Higher samplesPerPoint means lower resolution.
        // Bucket non-exact values to the nearest preset.
        switch samplesPerPoint {
        case Self.low.samplesPerPoint...:
            self = .low

        case Self.medium.samplesPerPoint...:
            self = .medium

        case Self.high.samplesPerPoint...:
            self = .high

        case Self.veryHigh.samplesPerPoint...:
            self = .veryHigh

        default:
            self = .lossless
        }
    }
}
