// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation
import SPFKBase

public struct WaveformDataItem: Sendable, Hashable, Codable, Equatable {
    /// Identity is the cache key, not the URL: a file with two audio tracks has two of these, and
    /// comparing on the URL alone made them the same value.
    public static func == (lhs: WaveformDataItem, rhs: WaveformDataItem) -> Bool {
        lhs.cacheKey == rhs.cacheKey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(cacheKey)
    }

    public let url: URL

    /// Which audio track this describes, or `nil` for the container's default — see
    /// ``WaveformCacheKey``.
    public let audioTrackID: UInt64?

    public let modificationDate: Date?
    public let fileSize: Int?
    public let waveformData: WaveformData

    public var cacheKey: WaveformCacheKey {
        WaveformCacheKey(url: url, audioTrackID: audioTrackID)
    }

    public init(
        url: URL,
        audioTrackID: UInt64? = nil,
        modificationDate: Date? = nil,
        fileSize: Int? = nil,
        waveformData: WaveformData
    ) {
        self.url = url
        self.audioTrackID = audioTrackID
        self.modificationDate = modificationDate ?? url.modificationDate
        self.fileSize = fileSize ?? url.fileSize
        self.waveformData = waveformData
    }

    /// Returns true if the cached data no longer matches the file on disk
    public func isFresh(comparedTo url: URL) -> Bool {
        modificationDate == url.modificationDate && fileSize == url.fileSize
    }
}
