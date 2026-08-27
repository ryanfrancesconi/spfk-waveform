// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem
import SPFKTesting
import SPFKUtils
import Testing

@testable import SPFKWaveform

@Suite(.tags(.file))
final class WaveformDataModelTests: BinTestCase {
    lazy var urls: [URL] = (try? copyToBin(urls: TestBundleResources.shared.audioCases)) ?? []

    var cowbell: URL? {
        guard
            let value = urls.first(
                where: { $0.lastPathComponent.contains("cowbell") }
            ), value.exists
        else {
            return nil
        }

        return value
    }
}

@MainActor
extension WaveformDataModelTests {
    func createCache() async throws -> [WaveformDataItem] {
        var items = [WaveformDataItem]()

        for file in urls {
            let waveformData = try await WaveformDataParser(resolution: .medium).parse(url: file)

            items.append(
                WaveformDataItem(url: file, waveformData: waveformData)
            )
        }

        return items
    }

    func insertCache(into data: WaveformDataStore) async throws {
        let cache: [WaveformDataItem] = try await createCache()

        for item in cache {
            Log.debug("inserting", item.url.path)
            try await data.insert(dto: .init(url: item.url, waveformData: item.waveformData))
        }
    }

    func dataStore() async throws -> WaveformDataStore {
        let data = try WaveformDataStore(inDirectory: bin)
        try await insertCache(into: data)
        try await data.save()
        return data
    }
}

@MainActor
extension WaveformDataModelTests {
    @Test func fetch() async throws {
        deleteBinOnExit = true

        let data = try await dataStore()

        var items = [WaveformDataItem]()

        for file in urls {
            let item = try await data.fetch(key: WaveformCacheKey(url: file))

            items.append(item)
        }

        #expect(
            items.count == urls.count
        )
    }

    @Test func delete() async throws {
        deleteBinOnExit = true

        let data = try await dataStore()

        guard let cowbell else {
            throw NSError(description: "no cowbell")
        }

        let startingCount = try await data.count()

        #expect(startingCount == urls.count)

        try await data.delete(url: cowbell)

        let newCount = try await data.count()

        #expect(newCount == startingCount - 1)
    }

    @Test func insertDuplicate() async throws {
        deleteBinOnExit = true
        let data = try await dataStore()
        await data.deleteAll()

        let startingCount = try await data.count()
        #expect(startingCount == 0)

        let url = TestBundleResources.shared.cowbell_wav

        let item = try await WaveformDataItem(
            url: url,
            waveformData: WaveformDataParser(resolution: .medium).parse(url: url)
        )

        let item2 = try await WaveformDataItem(
            url: TestBundleResources.shared.mp3_id3,
            waveformData: WaveformDataParser(resolution: .medium).parse(url: url)
        )

        for _ in 0 ..< 5 {
            try await data.insert(dto: .init(url: item.url, waveformData: item.waveformData))
        }

        try await data.insert(dto: .init(url: item2.url, waveformData: item2.waveformData))

        let newCount = try await data.count()

        #expect(newCount == 2) // still 2
    }

    @Test func fetchIfFresh() async throws {
        deleteBinOnExit = true
        let data = try await dataStore()

        guard let cowbell else {
            throw NSError(description: "no cowbell")
        }

        // freshly inserted — should return cached data
        let fresh = try await data.fetchIfFresh(key: WaveformCacheKey(url: cowbell))
        #expect(fresh != nil)
        #expect(fresh?.fileSize != nil)

        let task = Task<WaveformDataItem?, Error> {
            try await Task.sleep(seconds: 0.01) // let time progress
            try AVAudioFile(forReading: cowbell).normalize() // modify file

            return try await data.fetchIfFresh(key: WaveformCacheKey(url: cowbell))
        }

        // file was modified — should return nil and delete stale record
        let staleResult = try await task.value
        #expect(staleResult == nil)

        // record should have been deleted
        let count = try await data.count()
        #expect(count == urls.count - 1)
    }

    @Test func prune() async throws {
        deleteBinOnExit = true
        let data = try await dataStore()

        let startingCount = try await data.count()
        #expect(startingCount == urls.count)

        // keep only the first URL as "active"
        let activeURLs: Set<URL> = [urls[0]]
        let removed = try await data.prune(activeURLs: activeURLs)

        #expect(removed == urls.count - 1)

        let remainingCount = try await data.count()
        #expect(remainingCount == 1)
    }

    /// Verifies that waveform cache survives a metadata-only save when
    /// `refreshFreshness` is called afterward.
    @Test func refreshFreshnessAfterMetadataSave() async throws {
        deleteBinOnExit = true
        let data = try await dataStore()

        guard let cowbell else {
            throw NSError(description: "no cowbell")
        }

        // Verify freshly inserted data is retrievable
        let fresh = try await data.fetchIfFresh(key: WaveformCacheKey(url: cowbell))
        #expect(fresh != nil)

        // Simulate a metadata-only save: bump the file's modification date
        try await Task.sleep(seconds: 0.01)
        try cowbell.updateModificationDate()

        // Without refreshFreshness, the cache should be stale
        let staleCheck = try await data.fetchIfFresh(key: WaveformCacheKey(url: cowbell))
        #expect(staleCheck == nil, "Expected nil because modification date changed")

        // Re-insert the waveform (simulating what happens after a full reparse)
        let waveformData = try await WaveformDataParser(resolution: .medium).parse(url: cowbell)
        try await data.insert(dto: .init(url: cowbell, waveformData: waveformData))

        // Now simulate the same scenario but WITH refreshFreshness
        try await Task.sleep(seconds: 0.01)
        try cowbell.updateModificationDate()

        // Call refreshFreshness to update the stored dates
        try await data.refreshFreshness(url: cowbell)

        // Cache should still be valid
        let afterRefresh = try await data.fetchIfFresh(key: WaveformCacheKey(url: cowbell))
        #expect(afterRefresh != nil, "Expected cached data after refreshFreshness")
    }

    /// Verifies that waveform cache is correctly invalidated when actual audio
    /// data changes (external modification without refreshFreshness).
    @Test func freshnessInvalidatedByAudioDataChange() async throws {
        deleteBinOnExit = true
        let data = try await dataStore()

        guard let cowbell else {
            throw NSError(description: "no cowbell")
        }

        // Verify freshly inserted data is retrievable
        let fresh = try await data.fetchIfFresh(key: WaveformCacheKey(url: cowbell))
        #expect(fresh != nil)

        // Modify the actual audio data (normalize changes sample values)
        try await Task.sleep(seconds: 0.01)
        try AVAudioFile(forReading: cowbell).normalize()

        // Without refreshFreshness, the cache should be invalidated
        let staleResult = try await data.fetchIfFresh(key: WaveformCacheKey(url: cowbell))
        #expect(staleResult == nil, "Expected nil after audio data change")
    }
}

extension AVAudioFile {
    public func normalize() throws {
        guard let buffer = try AVAudioPCMBuffer(url: url) else {
            throw NSError(description: "failed to read into buffer")
        }

        let normalized = try buffer.normalize()

        _ = try AVAudioFile(url: url, fromBuffer: normalized)
    }
}
