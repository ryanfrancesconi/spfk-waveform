// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation

/// What a reversed audio cache entry is the reversal *of*: a file and one of its audio tracks,
/// named on disk exactly as ``WaveformCacheKey`` names a waveform.
public struct ReversedAudioKey: Hashable, Sendable {
    public let url: URL
    public let audioTrackID: UInt64?

    public init(url: URL, audioTrackID: UInt64? = nil) {
        self.url = url
        self.audioTrackID = audioTrackID
    }

    public var fileKey: String { waveformKey.fileKey }
    public var storageKey: String { waveformKey.storageKey }

    private var waveformKey: WaveformCacheKey { WaveformCacheKey(url: url, audioTrackID: audioTrackID) }
}

/// A fresh reversed cache file: forward playback of `url` is the source played backwards.
public struct ReversedAudioEntry: Equatable, Sendable {
    public let url: URL
    public let frameCount: Int
    public let sampleRate: Double

    public init(url: URL, frameCount: Int, sampleRate: Double) {
        self.url = url
        self.frameCount = frameCount
        self.sampleRate = sampleRate
    }
}
