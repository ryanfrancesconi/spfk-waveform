// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import SPFKUtils
import Testing

@testable import SPFKWaveform

@MainActor
@Suite(.tags(.file))
final class WaveformBinaryStorageTests: BinTestCase {
    @Test func binaryRoundTripExactValues() async throws {
        deleteBinOnExit = true
        let store = try WaveformDataStore(inDirectory: bin)

        // Edge-case float values that would lose precision in JSON text
        let floats: FloatChannelData = [
            [0.0, 1.0, -1.0, 0.5, Float.leastNormalMagnitude, Float.greatestFiniteMagnitude],
            [0.123456789, -0.987654321, 0.0, 1e-10, 1e10, Float.pi],
        ]

        let waveformData = WaveformData(
            floatChannelData: floats,
            samplesPerPoint: 64,
            audioDuration: 10,
            sampleRate: 44100
        )

        let url = URL(string: "file:///fake/exact_test.wav")!
        let item = WaveformDataItem(url: url, waveformData: waveformData)

        try await store.insert(dto: item)
        let fetched = try await store.fetch(key: WaveformCacheKey(url: url))

        #expect(fetched.waveformData.floatChannelData == floats)
        #expect(fetched.waveformData.audioDuration == 10)
        #expect(fetched.waveformData.sampleRate == 44100)
        #expect(fetched.waveformData.samplesPerPoint == 64)
    }

    @Test func legacyFullJSONMigration() async throws {
        deleteBinOnExit = true
        let migration = FlatToShardedMigration.waveform(inCachesDirectory: bin)
        let store = try WaveformDataStore(inDirectory: bin)

        let url = URL(string: "file:///fake/legacy_test.wav")!
        let key = url.sha256
        let shard = String(key.prefix(2))

        let floats: FloatChannelData = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
        let item = WaveformDataItem(
            url: url,
            waveformData: WaveformData(floatChannelData: floats, samplesPerPoint: 64, audioDuration: 5, sampleRate: 44100)
        )

        try FileManager.default.createDirectory(at: migration.oldFlatDirectoryURL, withIntermediateDirectories: true)
        let jsonFile = migration.oldFlatDirectoryURL.appendingPathComponent("\(key).json")
        try JSONEncoder().encode(item).write(to: jsonFile)

        let shardedFile = store.directoryURL
            .appendingPathComponent(shard)
            .appendingPathComponent("\(key).wfcache")
        #expect(!FileManager.default.fileExists(atPath: shardedFile.path))

        await migration.start()?.value

        #expect(FileManager.default.fileExists(atPath: shardedFile.path))
        #expect(!FileManager.default.fileExists(atPath: jsonFile.path))

        let fetched = try await store.fetch(key: WaveformCacheKey(url: url))
        #expect(fetched.waveformData.floatChannelData == floats)
        #expect(fetched.waveformData.audioDuration == 5)
        #expect(fetched.waveformData.sampleRate == 44100)
    }

    @Test func legacyPairedJsonBinMigration() async throws {
        deleteBinOnExit = true
        let migration = FlatToShardedMigration.waveform(inCachesDirectory: bin)
        let store = try WaveformDataStore(inDirectory: bin)

        let url = URL(string: "file:///fake/paired_test.wav")!
        let key = url.sha256
        let shard = String(key.prefix(2))

        let floats: FloatChannelData = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]

        struct MetadataRecord: Codable {
            let url: URL
            let modificationDate: Date?
            let fileSize: Int?
            let audioDuration: TimeInterval
            let sampleRate: Double
            let samplesPerPoint: Int
        }

        let record = MetadataRecord(url: url, modificationDate: nil, fileSize: nil, audioDuration: 5, sampleRate: 44100, samplesPerPoint: 64)

        try FileManager.default.createDirectory(at: migration.oldFlatDirectoryURL, withIntermediateDirectories: true)
        let jsonFile = migration.oldFlatDirectoryURL.appendingPathComponent("\(key).json")
        let binFile = migration.oldFlatDirectoryURL.appendingPathComponent("\(key).bin")
        let shardedFile = store.directoryURL
            .appendingPathComponent(shard)
            .appendingPathComponent("\(key).wfcache")

        try JSONEncoder().encode(record).write(to: jsonFile)

        var binData = Data()
        withUnsafeBytes(of: UInt32(floats.count)) { binData.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(floats[0].count)) { binData.append(contentsOf: $0) }
        for channel in floats { channel.withUnsafeBufferPointer { binData.append($0) } }
        try binData.write(to: binFile)

        await migration.start()?.value

        #expect(FileManager.default.fileExists(atPath: shardedFile.path))
        #expect(!FileManager.default.fileExists(atPath: jsonFile.path))
        #expect(!FileManager.default.fileExists(atPath: binFile.path))

        let fetched = try await store.fetch(key: WaveformCacheKey(url: url))
        #expect(fetched.waveformData.floatChannelData == floats)
        #expect(fetched.waveformData.audioDuration == 5)
        #expect(fetched.waveformData.sampleRate == 44100)
        #expect(fetched.waveformData.samplesPerPoint == 64)
    }

    @Test func fetchNonExistentThrows() async throws {
        deleteBinOnExit = true
        let store = try WaveformDataStore(inDirectory: bin)

        await #expect(throws: (any Error).self) {
            _ = try await store.fetch(key: WaveformCacheKey(url: URL(string: "file:///fake/nonexistent.wav")!))
        }
    }

    @Test func deleteNonExistentThrows() async throws {
        deleteBinOnExit = true
        let store = try WaveformDataStore(inDirectory: bin)

        await #expect(throws: (any Error).self) {
            try await store.delete(url: URL(string: "file:///fake/nonexistent.wav")!)
        }
    }

    @Test func corruptedCacheFileThrows() async throws {
        deleteBinOnExit = true
        let store = try WaveformDataStore(inDirectory: bin)

        let url = URL(string: "file:///fake/corrupt_test.wav")!
        let key = url.sha256
        let shard = String(key.prefix(2))

        try await store.insert(dto: WaveformDataItem(
            url: url,
            waveformData: WaveformData(floatChannelData: [[1.0, 2.0, 3.0]], samplesPerPoint: 64, audioDuration: 1, sampleRate: 44100)
        ))

        let cacheFile = store.directoryURL
            .appendingPathComponent(shard)
            .appendingPathComponent("\(key).wfcache")
        try Data([0x00, 0x01]).write(to: cacheFile, options: .atomic)

        await #expect(throws: (any Error).self) {
            _ = try await store.fetch(key: WaveformCacheKey(url: url))
        }
    }

    @Test func emptyStoreCountIsZero() async throws {
        deleteBinOnExit = true
        let store = try WaveformDataStore(inDirectory: bin)
        #expect(try await store.count() == 0)
    }

    @Test func fetchIfFreshReturnsNilForMissing() async throws {
        deleteBinOnExit = true
        let store = try WaveformDataStore(inDirectory: bin)
        let result = try await store.fetchIfFresh(key: WaveformCacheKey(url: URL(string: "file:///fake/missing.wav")!))
        #expect(result == nil)
    }

    @Test func deleteRemovesCacheFile() async throws {
        deleteBinOnExit = true
        let store = try WaveformDataStore(inDirectory: bin)

        let url = URL(string: "file:///fake/delete_test.wav")!
        let key = url.sha256
        let shard = String(key.prefix(2))

        try await store.insert(dto: WaveformDataItem(
            url: url,
            waveformData: WaveformData(floatChannelData: [[1.0, 2.0]], samplesPerPoint: 64, audioDuration: 1, sampleRate: 44100)
        ))

        let cacheFile = store.directoryURL
            .appendingPathComponent(shard)
            .appendingPathComponent("\(key).wfcache")
        #expect(FileManager.default.fileExists(atPath: cacheFile.path))

        try await store.delete(url: url)

        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
    }
}
