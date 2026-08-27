// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import SPFKUtils
import Testing

@testable import SPFKWaveform

@Suite(.tags(.file))
final class WaveformDataStoreMigrationTests: BinTestCase {
    private func fakeURL(index: Int) -> URL {
        URL(string: "file:///fake/audio/wfmigrate_\(index).wav")!
    }

    private func makeWaveformItem(url: URL) -> WaveformDataItem {
        let floats: [[Float]] = [[0.1, 0.5, -0.3, 0.8, -0.2]]
        let waveformData = WaveformData(
            floatChannelData: floats,
            samplesPerPoint: 512,
            audioDuration: 2.5,
            sampleRate: 44100
        )
        return WaveformDataItem(
            url: url,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileSize: 123_456,
            waveformData: waveformData
        )
    }

    private func writeLegacyWfcache(for url: URL, flatDir: URL) throws {
        let item = makeWaveformItem(url: url)
        let key = url.sha256
        let path = flatDir.appendingPathComponent("\(key).\(WaveformCacheFile.fileExtension)")
        try WaveformCacheFile.write(item, to: path)
    }

    // MARK: - Tests

    @Test func sweepMigratesWfcacheEntriesToShardedLocation() async throws {
        deleteBinOnExit = true
        let migration = FlatToShardedMigration.waveform(inCachesDirectory: bin)
        let store = try WaveformDataStore(inDirectory: bin)

        try FileManager.default.createDirectory(at: migration.oldFlatDirectoryURL, withIntermediateDirectories: true)
        let urls = (0 ..< 4).map { fakeURL(index: $0 + 100) }
        for url in urls { try writeLegacyWfcache(for: url, flatDir: migration.oldFlatDirectoryURL) }

        await migration.start()?.value

        for url in urls {
            let item = try await store.fetch(key: WaveformCacheKey(url: url))
            #expect(item.url == url)
        }
        #expect(!FileManager.default.fileExists(atPath: migration.oldFlatDirectoryURL.path))
    }

    @Test func fetchDoesNotConsultOldFlatDirectory() async throws {
        deleteBinOnExit = true
        let migration = FlatToShardedMigration.waveform(inCachesDirectory: bin)
        let store = try WaveformDataStore(inDirectory: bin)

        let url = fakeURL(index: 9000)
        try FileManager.default.createDirectory(at: migration.oldFlatDirectoryURL, withIntermediateDirectories: true)
        try writeLegacyWfcache(for: url, flatDir: migration.oldFlatDirectoryURL)
        // Do NOT start sweep — fetch must only look at sharded location

        await #expect(throws: (any Error).self) {
            try await store.fetch(key: WaveformCacheKey(url: url))
        }
    }

    @Test func sweepDeletesOldDirectoryWhenComplete() async throws {
        deleteBinOnExit = true
        let migration = FlatToShardedMigration.waveform(inCachesDirectory: bin)
        try FileManager.default.createDirectory(at: migration.oldFlatDirectoryURL, withIntermediateDirectories: true)
        for i in 0 ..< 3 { try writeLegacyWfcache(for: fakeURL(index: i + 200), flatDir: migration.oldFlatDirectoryURL) }

        #expect(FileManager.default.fileExists(atPath: migration.oldFlatDirectoryURL.path))
        _ = try WaveformDataStore(inDirectory: bin)
        await migration.start()?.value

        #expect(!FileManager.default.fileExists(atPath: migration.oldFlatDirectoryURL.path))
    }

    @Test func oldFlatKeysIncludesEntriesBeforeSweep() async throws {
        deleteBinOnExit = true
        let migration = FlatToShardedMigration.waveform(inCachesDirectory: bin)
        let store = try WaveformDataStore(inDirectory: bin)

        let flatURLs = (0 ..< 3).map { fakeURL(index: $0 + 300) }
        try FileManager.default.createDirectory(at: migration.oldFlatDirectoryURL, withIntermediateDirectories: true)
        for url in flatURLs { try writeLegacyWfcache(for: url, flatDir: migration.oldFlatDirectoryURL) }

        let freshURL = fakeURL(index: 9999)
        try await store.insert(dto: makeWaveformItem(url: freshURL))

        let shardedCount = try await store.count()
        let flatCount = migration.oldFlatKeys().count
        #expect(shardedCount + flatCount == flatURLs.count + 1)
    }

    @Test func pruneOldFlatRemovesOrphanedEntries() async throws {
        deleteBinOnExit = true
        let migration = FlatToShardedMigration.waveform(inCachesDirectory: bin)
        let store = try WaveformDataStore(inDirectory: bin)

        let flatURLs = (0 ..< 3).map { fakeURL(index: $0 + 400) }
        try FileManager.default.createDirectory(at: migration.oldFlatDirectoryURL, withIntermediateDirectories: true)
        for url in flatURLs { try writeLegacyWfcache(for: url, flatDir: migration.oldFlatDirectoryURL) }

        let keepURL = fakeURL(index: 8888)
        try await store.insert(dto: makeWaveformItem(url: keepURL))

        let activeKeys = Set([keepURL.sha256])
        let removed = migration.pruneOldFlat(retaining: activeKeys)
        #expect(removed == flatURLs.count)
        #expect(migration.oldFlatKeys().isEmpty)
    }

    @Test func sweepIsResumable() async throws {
        deleteBinOnExit = true
        let migration = FlatToShardedMigration.waveform(inCachesDirectory: bin)
        let store = try WaveformDataStore(inDirectory: bin)

        let urls = (0 ..< 4).map { fakeURL(index: $0 + 500) }
        try FileManager.default.createDirectory(at: migration.oldFlatDirectoryURL, withIntermediateDirectories: true)
        for url in urls { try writeLegacyWfcache(for: url, flatDir: migration.oldFlatDirectoryURL) }

        // Manually move half the entries to simulate a partial sweep
        for url in urls.prefix(2) {
            let key = url.sha256
            try await store.insert(dto: makeWaveformItem(url: url))
            try FileManager.default.removeItem(
                at: migration.oldFlatDirectoryURL.appendingPathComponent("\(key).\(WaveformCacheFile.fileExtension)")
            )
        }
        #expect(FileManager.default.fileExists(atPath: migration.oldFlatDirectoryURL.path))

        await migration.start()?.value

        let total = try await store.count()
        #expect(total == urls.count)
        #expect(!FileManager.default.fileExists(atPath: migration.oldFlatDirectoryURL.path))
    }
}
