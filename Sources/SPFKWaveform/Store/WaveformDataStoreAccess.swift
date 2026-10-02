// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation
import SPFKAudioBase

public protocol WaveformDataStoreAccess: Sendable {
    /// Returns the cached waveform if fresh, or nil if stale/missing (stale records are deleted automatically)
    ///
    /// Keyed by file *and* audio track: a container offering several tracks has a waveform per
    /// track, and a lookup by URL alone answers with whichever was scanned first.
    func fetchFreshWaveformData(key: WaveformCacheKey) async throws -> WaveformDataItem?

    /// insert data into persistent waveform cache
    func insertWaveformData(waveform: WaveformDataItem) async throws

    /// Updates the waveform cache's freshness metadata (modification date, file size)
    /// without re-parsing the waveform. Call after saving metadata so our own
    /// modification date bump doesn't invalidate the cached waveform.
    ///
    /// Per file, covering every track: one save invalidates all of them at once.
    func refreshWaveformFreshness(url: URL) async throws

    /// Moves every cached waveform for a file that moved without its content changing. See
    /// ``WaveformDataStore/rekey(from:to:)``.
    func rekeyWaveformData(from oldURL: URL, to newURL: URL) async throws
}
