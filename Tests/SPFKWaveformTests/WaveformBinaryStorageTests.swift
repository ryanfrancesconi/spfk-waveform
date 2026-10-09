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
