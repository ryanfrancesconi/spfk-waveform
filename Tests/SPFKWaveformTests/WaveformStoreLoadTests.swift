// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKWaveform

@MainActor
@Suite(.tags(.file, .slow))
final class WaveformStoreLoadTests: BinTestCase {
    /// Creates a synthetic WaveformDataItem with deterministic float data.
    /// Uses fake file:// URLs that hash to unique SHA256 keys.
    private func makeSyntheticWaveform(
        index: Int,
        duration: TimeInterval = 10,
        channelCount: Int = 2,
        sampleRate: Double = 44100,
        resolution: WaveformDrawingResolution = .medium
    ) -> WaveformDataItem {
        let pointCount = Int(duration * sampleRate) / resolution.samplesPerPoint
        let url = URL(string: "file:///fake/audio/track_\(index).wav")!

        // Fill with a simple repeating pattern — fast to generate
        let floatChannelData: FloatChannelData = (0 ..< channelCount).map { ch in
            (0 ..< pointCount).map { i in
                sin(Float(i + ch * 1000) * 0.01)
            }
        }

        let waveformData = WaveformData(
            floatChannelData: floatChannelData,
            samplesPerPoint: resolution.samplesPerPoint,
            audioDuration: duration,
            sampleRate: sampleRate
        )

        return WaveformDataItem(
            url: url,
            modificationDate: nil,
            fileSize: nil,
            waveformData: waveformData
        )
    }

    /// Creates a store and inserts `count` synthetic waveforms.
    private func populatedStore(
        count: Int,
        duration: TimeInterval = 10,
        channelCount: Int = 2
    ) async throws -> (WaveformDataStore, [URL]) {
        let store = try WaveformDataStore(inDirectory: bin)
        var urls = [URL]()
        urls.reserveCapacity(count)

        for i in 0 ..< count {
            let item = makeSyntheticWaveform(
                index: i,
                duration: duration,
                channelCount: channelCount
            )
            try await store.insert(dto: item)
            urls.append(item.url)
        }

        return (store, urls)
    }

    // MARK: - Tests

    @Test func bulkInsert() async throws {
        deleteBinOnExit = true
        let (store, _) = try await populatedStore(count: 200)
        let count = try await store.count()
        #expect(count == 200)
    }

    @Test func bulkFetch() async throws {
        deleteBinOnExit = true
        let (store, urls) = try await populatedStore(count: 200)

        for url in urls {
            let item = try await store.fetch(key: WaveformCacheKey(url: url))
            #expect(item.waveformData.channelCount == 2)
        }
    }

    @Test func bulkFetchIfFresh() async throws {
        deleteBinOnExit = true
        let (store, urls) = try await populatedStore(count: 200)

        // All items were inserted with nil modificationDate/fileSize.
        // Fake URLs don't exist on disk, so url.modificationDate == nil == stored value → fresh.
        for url in urls {
            let result = try await store.fetchIfFresh(key: WaveformCacheKey(url: url))
            #expect(result != nil)
        }
    }

    @Test func bulkPrune() async throws {
        deleteBinOnExit = true
        let (store, urls) = try await populatedStore(count: 200)

        // Keep only the first 50
        let activeURLs = Set(urls.prefix(50))
        let removed = try await store.prune(activeURLs: activeURLs)
        #expect(removed == 150)

        let remaining = try await store.count()
        #expect(remaining == 50)

        // Pruning against an empty active set removes nothing. An empty set means the caller
        // could not enumerate what is live, not that nothing is -- `deleteAll()` is how a caller
        // asks for everything to go, and `bulkDeleteAll` covers it.
        let removedAll = try await store.prune(activeURLs: [])
        #expect(removedAll == 0)

        let finalCount = try await store.count()
        #expect(finalCount == 50)
    }

    @Test func bulkDeleteAll() async throws {
        deleteBinOnExit = true
        let (store, _) = try await populatedStore(count: 200)

        await store.deleteAll()
        let count = try await store.count()
        #expect(count == 0)
    }

    @Test func concurrentAccess() async throws {
        deleteBinOnExit = true
        let store = try WaveformDataStore(inDirectory: bin)

        // 50 concurrent inserts
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< 50 {
                let item = makeSyntheticWaveform(index: i, duration: 10)
                group.addTask {
                    try await store.insert(dto: item)
                }
            }
            try await group.waitForAll()
        }

        let count = try await store.count()
        #expect(count == 50)

        // 50 concurrent fetches
        try await withThrowingTaskGroup(of: WaveformDataItem.self) { group in
            for i in 0 ..< 50 {
                let url = URL(string: "file:///fake/audio/track_\(i).wav")!
                group.addTask {
                    try await store.fetch(key: WaveformCacheKey(url: url))
                }
            }

            var fetchCount = 0
            for try await _ in group {
                fetchCount += 1
            }

            #expect(fetchCount == 50)
        }
    }

    @Test func largeWaveformRoundTrip() async throws {
        deleteBinOnExit = true
        let store = try WaveformDataStore(inDirectory: bin)

        // 10-minute stereo waveform at medium resolution (64 spp)
        // Points per channel: (600 * 44100) / 64 = ~413,437
        let item = makeSyntheticWaveform(
            index: 0,
            duration: 600,
            channelCount: 2,
            resolution: .medium
        )

        let expectedPointCount = item.waveformData.floatChannelData[0].count

        try await store.insert(dto: item)

        let fetched = try await store.fetch(key: WaveformCacheKey(url: item.url))
        #expect(fetched.waveformData.channelCount == 2)
        #expect(fetched.waveformData.floatChannelData[0].count == expectedPointCount)
        #expect(fetched.waveformData.floatChannelData[1].count == expectedPointCount)
        #expect(fetched.waveformData.audioDuration == 600)
        #expect(fetched.waveformData.sampleRate == 44100)
    }
}
