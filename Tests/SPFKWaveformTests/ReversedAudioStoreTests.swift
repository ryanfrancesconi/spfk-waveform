// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKWaveform

@Suite(.tags(.file, .reverse), .serialized)
final class ReversedAudioStoreTests: BinTestCase {
    private func makeStore() throws -> ReversedAudioStore {
        deleteBinOnExit = true
        return try ReversedAudioStore(inDirectory: bin.appendingPathComponent("cache"))
    }

    private func makeSource(_ name: String = "source.wav") throws -> URL {
        let url = bin.appendingPathComponent("files/\(name)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: url)
        return url
    }

    /// A finished build in scratch, as the builder leaves one.
    private func makeBuild(_ store: ReversedAudioStore, bytes: UInt8 = 7) throws -> URL {
        let url = try store.makeScratchURL()
        try Data(repeating: bytes, count: 128).write(to: url)
        return url
    }

    private func sidecarURL(_ store: ReversedAudioStore, _ key: ReversedAudioKey) -> URL {
        store.shardedDirectory.fileURL(for: key.storageKey, suffix: ".json")
    }

    // MARK: - WaveformData

    @Test func reversedWaveformReversesEachChannelAndKeepsTheRest() {
        let data = WaveformData(floatChannelData: [[1, 2, 3], [4, 5, 6]], samplesPerPoint: 64, audioDuration: 2.5, sampleRate: 48000)
        let reversed = data.reversed()
        #expect(reversed.floatChannelData == [[3, 2, 1], [6, 5, 4]])
        #expect(reversed.samplesPerPoint == 64)
        #expect(reversed.audioDuration == 2.5)
        #expect(reversed.sampleRate == 48000)
        #expect(reversed.reversed() == data)
    }

    // MARK: - Store

    @Test func commitThenFetch() async throws {
        let store = try makeStore()
        let key = ReversedAudioKey(url: try makeSource())
        let build = try makeBuild(store)

        try await store.commit(key: key, from: build, frameCount: 1234, sampleRate: 48000)

        let entry = try #require(await store.fetchIfFresh(key: key))
        #expect(entry.frameCount == 1234)
        #expect(entry.sampleRate == 48000)
        #expect(try Data(contentsOf: entry.url) == Data(repeating: 7, count: 128))
        #expect(!FileManager.default.fileExists(atPath: build.path))
    }

    @Test func aTouchedSourceIsAMissAndDeleted() async throws {
        let store = try makeStore()
        let source = try makeSource()
        let key = ReversedAudioKey(url: source)
        try await store.commit(key: key, from: try makeBuild(store), frameCount: 10, sampleRate: 44100)

        try Data(repeating: 2, count: 99).write(to: source)

        #expect(await store.fetchIfFresh(key: key) == nil)
        #expect(await store.count() == 0)
    }

    @Test func anUnreadableSidecarIsAMiss() async throws {
        let store = try makeStore()
        let key = ReversedAudioKey(url: try makeSource())
        try await store.commit(key: key, from: try makeBuild(store), frameCount: 10, sampleRate: 44100)

        try Data("not json".utf8).write(to: sidecarURL(store, key))

        #expect(await store.fetchIfFresh(key: key) == nil)
        #expect(await store.count() == 0)
    }

    @Test func refreshFreshnessKeepsAnEntryAcrossAMetadataWrite() async throws {
        let store = try makeStore()
        let source = try makeSource()
        let key = ReversedAudioKey(url: source, audioTrackID: 2)
        try await store.commit(key: key, from: try makeBuild(store), frameCount: 10, sampleRate: 44100)

        try Data(repeating: 3, count: 80).write(to: source)
        try await store.refreshFreshness(urls: [source])

        #expect(await store.fetchIfFresh(key: key)?.frameCount == 10)
    }

    @Test func rekeyMovesTheEntry() async throws {
        let store = try makeStore()
        let old = try makeSource("old.wav")
        let new = try makeSource("new.wav")
        try await store.commit(key: ReversedAudioKey(url: old, audioTrackID: 3), from: try makeBuild(store), frameCount: 42, sampleRate: 48000)

        try await store.rekey(from: old, to: new)

        #expect(await store.fetchIfFresh(key: ReversedAudioKey(url: new, audioTrackID: 3))?.frameCount == 42)
        #expect(await store.fetchIfFresh(key: ReversedAudioKey(url: old, audioTrackID: 3)) == nil)
        #expect(await store.count() == 1)
    }

    @Test func pruneKeepsPerTrackEntriesAndRefusesAnEmptySet() async throws {
        let store = try makeStore()
        let kept = try makeSource("kept.wav")
        let gone = try makeSource("gone.wav")
        try await store.commit(key: ReversedAudioKey(url: kept), from: try makeBuild(store), frameCount: 1, sampleRate: 48000)
        try await store.commit(key: ReversedAudioKey(url: kept, audioTrackID: 5), from: try makeBuild(store), frameCount: 2, sampleRate: 48000)
        try await store.commit(key: ReversedAudioKey(url: gone), from: try makeBuild(store), frameCount: 3, sampleRate: 48000)

        #expect(await store.prune(activeKeys: []) == 0)
        #expect(await store.count() == 3)

        #expect(await store.prune(activeKeys: [kept.sha256]) == 1)
        #expect(await store.fetchIfFresh(key: ReversedAudioKey(url: kept, audioTrackID: 5))?.frameCount == 2)
        #expect(await store.fetchIfFresh(key: ReversedAudioKey(url: kept))?.frameCount == 1)
    }

    @Test func aSecondCommitOfOneKeyWinsCleanly() async throws {
        let store = try makeStore()
        let key = ReversedAudioKey(url: try makeSource())
        try await store.commit(key: key, from: try makeBuild(store, bytes: 1), frameCount: 10, sampleRate: 44100)
        try await store.commit(key: key, from: try makeBuild(store, bytes: 2), frameCount: 20, sampleRate: 48000)

        let entry = try #require(await store.fetchIfFresh(key: key))
        #expect(entry.frameCount == 20)
        #expect(try Data(contentsOf: entry.url) == Data(repeating: 2, count: 128))
        #expect(await store.count() == 1)
    }

    @Test func aBuildInScratchIsNotAnEntry() async throws {
        let store = try makeStore()
        let source = try makeSource()
        try await store.commit(key: ReversedAudioKey(url: source), from: try makeBuild(store), frameCount: 1, sampleRate: 48000)
        let inFlight = try makeBuild(store)

        #expect(await store.count() == 1)
        #expect(await store.prune(activeKeys: [source.sha256]) == 0)
        #expect(FileManager.default.fileExists(atPath: inFlight.path))
    }

    @Test func deleteAllEmptiesTheStoreAndScratch() async throws {
        let store = try makeStore()
        try await store.commit(key: ReversedAudioKey(url: try makeSource()), from: try makeBuild(store), frameCount: 1, sampleRate: 48000)
        let leftover = try makeBuild(store)

        await store.deleteAll()

        #expect(await store.count() == 0)
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
    }
}
