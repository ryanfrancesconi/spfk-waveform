// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKWaveform

/// A file with more than one audio track has a waveform per track, which is the dimension the cache
/// key gained.
@MainActor
@Suite(.tags(.file))
final class WaveformPerTrackCacheTests: BinTestCase {
    /// A real file, because freshness is measured against one — a fake URL has no modification date
    /// and every lookup would read as stale for reasons unrelated to the track.
    private var url: URL { TestBundleResources.shared.tabla_wav }

    private func item(audioTrackID: UInt64?, value: Float) -> WaveformDataItem {
        WaveformDataItem(
            url: url,
            audioTrackID: audioTrackID,
            waveformData: WaveformData(
                floatChannelData: [[value, value, value]],
                samplesPerPoint: 1024,
                audioDuration: 4,
                sampleRate: 44100
            )
        )
    }

    private func makeStore() throws -> WaveformDataStore {
        deleteBinOnExit = true
        return try WaveformDataStore(inDirectory: bin)
    }

    /// The whole point: two tracks of one file are two entries, and each reads back its own data.
    /// Keyed on the URL alone, the second insert overwrote the first and both lookups answered with
    /// whichever was scanned last.
    @Test func twoTracksOfOneFileAreSeparateEntries() async throws {
        let store = try makeStore()

        try await store.insert(dto: item(audioTrackID: 1, value: 0.25))
        try await store.insert(dto: item(audioTrackID: 2, value: 0.75))

        let first = try await store.fetchIfFresh(key: WaveformCacheKey(url: url, audioTrackID: 1))
        let second = try await store.fetchIfFresh(key: WaveformCacheKey(url: url, audioTrackID: 2))

        #expect(first?.waveformData.floatChannelData.first?.first == 0.25)
        #expect(second?.waveformData.floatChannelData.first?.first == 0.75)
        #expect(try await store.count() == 2)
    }

    /// The default entry is the bare file key, so a single-track file keeps the entry it already had
    /// rather than every library re-scanning on first launch after this ships.
    @Test func theDefaultTrackKeepsTheFileKeyUnchanged() async throws {
        let store = try makeStore()

        try await store.insert(dto: item(audioTrackID: nil, value: 0.5))

        #expect(WaveformCacheKey(url: url).storageKey == url.sha256)
        #expect(try await store.fetchIfFresh(key: WaveformCacheKey(url: url)) != nil)
    }

    /// A default entry and a track entry are different entries, not the same one twice.
    @Test func theDefaultAndANamedTrackDoNotCollide() async throws {
        let store = try makeStore()

        try await store.insert(dto: item(audioTrackID: nil, value: 0.1))
        try await store.insert(dto: item(audioTrackID: 3, value: 0.9))

        #expect(try await store.count() == 2)
        #expect(try await store.fetchIfFresh(key: WaveformCacheKey(url: url))?
            .waveformData.floatChannelData.first?.first == 0.1)
    }

    /// **The trap.** Pruning compares against URL hashes, and a per-track entry is `<hash>-<track>`,
    /// which is in no such set. Matching whole keys deleted every per-track waveform on the next
    /// sweep and re-scanned them all on the next load.
    @Test func pruningKeepsEveryTrackOfALiveFile() async throws {
        let store = try makeStore()

        try await store.insert(dto: item(audioTrackID: nil, value: 0.1))
        try await store.insert(dto: item(audioTrackID: 1, value: 0.2))
        try await store.insert(dto: item(audioTrackID: 2, value: 0.3))

        let removed = try await store.prune(activeURLs: [url])

        #expect(removed == 0)
        #expect(try await store.count() == 3)
    }

    /// And a file that is gone loses all of its tracks, not just the default one.
    @Test func pruningRemovesEveryTrackOfADeadFile() async throws {
        let store = try makeStore()

        try await store.insert(dto: item(audioTrackID: nil, value: 0.1))
        try await store.insert(dto: item(audioTrackID: 1, value: 0.2))

        // A live URL that is not this one, rather than an empty set: pruning against nothing is
        // refused outright, because a caller that could not enumerate what is live looks exactly
        // like a library with nothing in it.
        let removed = try await store.prune(activeURLs: [URL(fileURLWithPath: "/tmp/still-here.wav")])

        #expect(removed == 2)
        #expect(try await store.count() == 0)
    }

    /// One save changes the file, so every track's entry goes stale at the same moment. Restamping
    /// only the default one left the rest to be re-scanned a track at a time.
    @Test func refreshingFreshnessCoversEveryTrack() async throws {
        let store = try makeStore()

        let stale = Date(timeIntervalSinceReferenceDate: 1)

        for track in [nil, UInt64(1), UInt64(2)] {
            try await store.insert(dto: WaveformDataItem(
                url: url,
                audioTrackID: track,
                modificationDate: stale,
                fileSize: 1,
                waveformData: item(audioTrackID: track, value: 0.5).waveformData
            ))
        }

        // Every entry is stale against the real file, so nothing is fetchable — which is what makes
        // the refresh below observable rather than vacuous.
        #expect(try await store.fetchIfFresh(key: WaveformCacheKey(url: url, audioTrackID: 2)) == nil)

        // Re-inserted, not redundantly: a stale fetch *deletes* the entry it rejected, so the check
        // above consumed one. Removing this loop makes the test pass for the wrong reason.
        for track in [nil, UInt64(1), UInt64(2)] {
            try await store.insert(dto: WaveformDataItem(
                url: url,
                audioTrackID: track,
                modificationDate: stale,
                fileSize: 1,
                waveformData: item(audioTrackID: track, value: 0.5).waveformData
            ))
        }

        try await store.refreshFreshness(url: url)

        #expect(try await store.fetchIfFresh(key: WaveformCacheKey(url: url)) != nil)
        #expect(try await store.fetchIfFresh(key: WaveformCacheKey(url: url, audioTrackID: 1)) != nil)
        #expect(try await store.fetchIfFresh(key: WaveformCacheKey(url: url, audioTrackID: 2)) != nil)
    }

    /// Deleting means "this file's waveform is gone", which is true of every track at once.
    @Test func deletingRemovesEveryTrackOfTheFile() async throws {
        let store = try makeStore()

        try await store.insert(dto: item(audioTrackID: nil, value: 0.1))
        try await store.insert(dto: item(audioTrackID: 1, value: 0.2))

        try await store.delete(url: url)

        #expect(try await store.count() == 0)
    }

    /// An entry this build cannot parse is a miss, not a thrown error: it is a derived cache, and
    /// failing the load of a good audio file over a stale header is the wrong trade.
    @Test func anUnreadableEntryReadsAsAMiss() async throws {
        let store = try makeStore()

        try await store.insert(dto: item(audioTrackID: nil, value: 0.5))

        let key = WaveformCacheKey(url: url)
        let entry = store.shardedDirectory.fileURL(
            for: key.storageKey,
            suffix: ".\(WaveformCacheFile.fileExtension)"
        )

        // A valid header whose version this build does not know.
        var corrupted = try Data(contentsOf: entry)
        corrupted.replaceSubrange(4 ..< 6, with: Data([0xFF, 0x00]))
        try corrupted.write(to: entry)

        #expect(try await store.fetchIfFresh(key: key) == nil)
        #expect(try await store.count() == 0)
    }
}
