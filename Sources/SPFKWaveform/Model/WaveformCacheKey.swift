// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation
import SPFKBase

/// What a cached waveform is the waveform *of*.
///
/// A file used to be enough, and stopped being enough once a container could offer more than one
/// audio track: the same URL then has as many waveforms as it has tracks, and a cache keyed on the
/// URL alone serves whichever was scanned first.
///
/// **The track is an opaque discriminator, not a track type.** This package knows nothing about
/// containers, and a cache does not need to — `AudioTrackDescription.ID` lives in `spfk-video`,
/// which `spfk-audio-base` deliberately does not depend on. A caller passes the identifier's raw
/// value and the cache treats it as a number that makes two entries different.
public struct WaveformCacheKey: Hashable, Sendable {
    public let url: URL

    /// `nil` is the container's default audio, which is every file with a single track — and so is
    /// every entry written before tracks were a dimension at all.
    public let audioTrackID: UInt64?

    public init(url: URL, audioTrackID: UInt64? = nil) {
        self.url = url
        self.audioTrackID = audioTrackID
    }

    /// Every key for this file, whatever track it names. What pruning matches on: a file that is
    /// still in a playlist keeps all of its tracks' waveforms, and a file that is gone loses all of
    /// them.
    public var fileKey: String { url.sha256 }

    /// The cache entry's name on disk.
    ///
    /// **`nil` resolves to the file key unchanged**, so a single-track file keeps the entry it
    /// already had rather than every library re-scanning the first time this ships. That is a
    /// consequence of the encoding rather than a migration — there is no second path to maintain.
    public var storageKey: String {
        guard let audioTrackID else { return fileKey }

        return "\(fileKey)-\(audioTrackID)"
    }
}
