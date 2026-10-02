// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKWaveform

/// A relinked file keeps its waveform: the entry moves to the new path's key and stays fresh there.
@MainActor
@Suite(.tags(.file))
final class WaveformRekeyTests: BinTestCase {
    private func makeStore() throws -> WaveformDataStore {
        deleteBinOnExit = true
        return try WaveformDataStore(inDirectory: bin.appendingPathComponent("cache"))
    }

    /// Two copies of one file whose modification dates differ, as a copy to another volume can leave them.
    private func makeCopies() throws -> (old: URL, new: URL) {
        let source = TestBundleResources.shared.tabla_wav
        let old = bin.appendingPathComponent("old/tabla.wav")
        let new = bin.appendingPathComponent("new/tabla.wav")

        for url in [old, new] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: url)
        }

        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: new.path)

        return (old, new)
    }

    private func item(url: URL, audioTrackID: UInt64? = nil, value: Float) -> WaveformDataItem {
        WaveformDataItem(
            url: url,
            audioTrackID: audioTrackID,
            waveformData: WaveformData(floatChannelData: [[value, value]], samplesPerPoint: 1024, audioDuration: 4, sampleRate: 44100)
        )
    }

    @Test func aRekeyedEntryIsFreshAtTheNewPathAndNamesIt() async throws {
        let store = try makeStore()
        let (old, new) = try makeCopies()

        try await store.insert(dto: item(url: old, value: 0.25))
        try await store.insert(dto: item(url: old, audioTrackID: 2, value: 0.5))

        try await store.rekey(from: old, to: new)

        let moved = try await store.fetchIfFresh(key: WaveformCacheKey(url: new))
        let movedTrack = try await store.fetchIfFresh(key: WaveformCacheKey(url: new, audioTrackID: 2))

        #expect(moved?.url == new)
        #expect(moved?.waveformData.floatChannelData.first?.first == 0.25)
        #expect(movedTrack?.waveformData.floatChannelData.first?.first == 0.5)
        #expect(try await store.count() == 2)
    }

    /// On a merge the file already in the library keeps its own waveform.
    @Test func anExistingEntryAtTheNewPathWins() async throws {
        let store = try makeStore()
        let (old, new) = try makeCopies()

        try await store.insert(dto: item(url: old, value: 0.25))
        try await store.insert(dto: item(url: new, value: 0.75))

        try await store.rekey(from: old, to: new)

        let kept = try await store.fetchIfFresh(key: WaveformCacheKey(url: new))

        #expect(kept?.waveformData.floatChannelData.first?.first == 0.75)
        #expect(try await store.count() == 1)
    }

    /// A relinked file whose waveform does not move leaves nothing under its old URL.
    @Test func deletingWhatIsPresentRemovesEveryTrackAndToleratesNothing() async throws {
        let store = try makeStore()
        let (old, new) = try makeCopies()

        try await store.insert(dto: item(url: old, value: 0.25))
        try await store.insert(dto: item(url: old, audioTrackID: 2, value: 0.5))
        try await store.insert(dto: item(url: new, value: 0.75))

        await store.deleteIfPresent(url: old)
        await store.deleteIfPresent(url: old)

        #expect(try await store.count() == 1)
    }
}
