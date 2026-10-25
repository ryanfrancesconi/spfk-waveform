// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation
import SPFKBase
import SPFKUtils

/// Reversed copies of audio files, built once per source version for reversed preview.
///
/// Each entry is `<storageKey>.caf` plus a `<storageKey>.json` sidecar holding the source's
/// freshness and the cache's frame count. The sidecar is written last, so an entry without one is
/// incomplete and reads as a miss.
public actor ReversedAudioStore {
    /// Sharded cache root: `<inDirectory>/Data/Reversed/<shard>/<key>.caf`
    public nonisolated let directoryURL: URL
    nonisolated let shardedDirectory: ShardedDirectory
    nonisolated let scratchDirectoryURL: URL

    private static let audioSuffix = ".caf"
    private static let sidecarSuffix = ".json"

    struct Sidecar: Codable, Equatable {
        var modificationDate: Date?
        var fileSize: Int?
        var frameCount: Int
        var sampleRate: Double

        var freshness: WaveformCacheFile.FreshnessInfo {
            WaveformCacheFile.FreshnessInfo(modificationDate: modificationDate, fileSize: fileSize)
        }

        mutating func stamp(from url: URL) {
            modificationDate = url.modificationDate
            fileSize = url.fileSize
        }
    }

    public init(inDirectory: URL) throws {
        directoryURL = inDirectory.appendingPathComponent("Data/Reversed")
        shardedDirectory = ShardedDirectory(rootURL: directoryURL)
        scratchDirectoryURL = directoryURL.appendingPathComponent("Scratch")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func audioURL(for key: String) -> URL {
        shardedDirectory.fileURL(for: key, suffix: Self.audioSuffix)
    }

    private func sidecarURL(for key: String) -> URL {
        shardedDirectory.fileURL(for: key, suffix: Self.sidecarSuffix)
    }

    private func deleteFiles(for key: String) {
        try? FileManager.default.removeItem(at: sidecarURL(for: key))
        try? FileManager.default.removeItem(at: audioURL(for: key))
    }

    /// Either half counts, so an entry left incomplete is still found and removed.
    private func entryKeys() -> Set<String> {
        Set(shardedDirectory.entryKeys(suffix: Self.audioSuffix) + shardedDirectory.entryKeys(suffix: Self.sidecarSuffix))
    }

    private func entryKeys(forFileKey fileKey: String) -> Set<String> {
        let keys = shardedDirectory.entryKeys(suffix: Self.audioSuffix, inShardOf: fileKey)
            + shardedDirectory.entryKeys(suffix: Self.sidecarSuffix, inShardOf: fileKey)
        return Set(keys.filter { $0 == fileKey || $0.hasPrefix("\(fileKey)-") })
    }

    private func readSidecar(for key: String) throws -> Sidecar {
        try JSONDecoder().decode(Sidecar.self, from: Data(contentsOf: sidecarURL(for: key)))
    }

    private func writeSidecar(_ sidecar: Sidecar, for key: String) throws {
        try JSONEncoder().encode(sidecar).write(to: sidecarURL(for: key), options: .atomic)
    }
}

// MARK: - Public

extension ReversedAudioStore {
    /// The cached reversal if the source is unchanged. A stale, incomplete or unreadable entry is
    /// deleted and returns nil: this is a derived cache whose worst case is one rebuild.
    public func fetchIfFresh(key: ReversedAudioKey) -> ReversedAudioEntry? {
        let storageKey = key.storageKey
        let audio = audioURL(for: storageKey)

        guard FileManager.default.fileExists(atPath: sidecarURL(for: storageKey).path)
            || FileManager.default.fileExists(atPath: audio.path)
        else { return nil }

        guard let sidecar = try? readSidecar(for: storageKey),
              FileManager.default.fileExists(atPath: audio.path)
        else {
            Log.debug("incomplete reversed audio for \(key.url.lastPathComponent), deleting")
            deleteFiles(for: storageKey)
            return nil
        }

        guard sidecar.freshness.isFresh(comparedTo: key.url) else {
            Log.debug("stale reversed audio for \(key.url.lastPathComponent), deleting")
            deleteFiles(for: storageKey)
            return nil
        }

        return ReversedAudioEntry(url: audio, frameCount: sidecar.frameCount, sampleRate: sidecar.sampleRate)
    }

    /// A fresh path on the store's volume for a build to write into.
    public nonisolated func makeScratchURL() throws -> URL {
        try FileManager.default.createDirectory(at: scratchDirectoryURL, withIntermediateDirectories: true)
        return scratchDirectoryURL.appendingPathComponent("\(UUID().uuidString).caf")
    }

    /// Moves a finished build at `temporaryURL` into place with an atomic rename, then writes the
    /// sidecar stamped from the source as it is now. A second commit of one key replaces the first.
    public func commit(key: ReversedAudioKey, from temporaryURL: URL, frameCount: Int, sampleRate: Double) throws {
        let storageKey = key.storageKey
        try shardedDirectory.ensureShardDirectory(for: storageKey)

        // The old sidecar goes first, so no moment pairs it with the new audio.
        try? FileManager.default.removeItem(at: sidecarURL(for: storageKey))

        guard rename(temporaryURL.path, audioURL(for: storageKey).path) == 0 else {
            throw NSError(description: "Couldn't move the reversed audio into place: \(String(cString: strerror(errno)))")
        }

        var sidecar = Sidecar(frameCount: frameCount, sampleRate: sampleRate)
        sidecar.stamp(from: key.url)
        try writeSidecar(sidecar, for: storageKey)
    }

    /// Removes every entry for `url`, across all of its tracks.
    public func deleteIfPresent(url: URL) {
        for key in entryKeys(forFileKey: url.sha256) {
            deleteFiles(for: key)
        }
    }

    /// Removes every entry and any build left in scratch.
    public func deleteAll() {
        for key in entryKeys() {
            deleteFiles(for: key)
        }
        try? FileManager.default.removeItem(at: scratchDirectoryURL)
    }

    public func count() -> Int {
        entryKeys().count
    }

    /// Removes entries whose file is not in `activeKeys`, matching the file half of each key as
    /// ``WaveformDataStore/prune(activeKeys:)`` does. An empty set removes nothing.
    @discardableResult
    public func prune(activeKeys: Set<String>) -> Int {
        guard activeKeys.isNotEmpty else { return 0 }

        var removedCount = 0

        for key in entryKeys() where !activeKeys.contains(WaveformDataStore.fileKey(ofEntry: key)) {
            Log.debug("pruning orphaned reversed audio: \(key)")
            deleteFiles(for: key)
            removedCount += 1
        }

        return removedCount
    }

    /// Re-stamps every entry for `url` after the app's own write bumped its modification date
    /// without touching its audio.
    public func refreshFreshness(url: URL) throws {
        for key in entryKeys(forFileKey: url.sha256) {
            guard var sidecar = try? readSidecar(for: key) else { continue }
            sidecar.stamp(from: url)
            try writeSidecar(sidecar, for: key)
        }
    }

    /// Moves every entry for `oldURL` to `newURL`, re-stamped from `newURL`. **Only for a file
    /// verified to hold the same audio.** Entries already under `newURL` win.
    public func rekey(from oldURL: URL, to newURL: URL) throws {
        let oldKeys = entryKeys(forFileKey: oldURL.sha256)

        guard oldKeys.isNotEmpty, oldURL.sha256 != newURL.sha256 else { return }

        defer {
            for key in oldKeys {
                deleteFiles(for: key)
            }
        }

        guard entryKeys(forFileKey: newURL.sha256).isEmpty else { return }

        let oldFileKey = oldURL.sha256

        for key in oldKeys {
            guard var sidecar = try? readSidecar(for: key),
                  FileManager.default.fileExists(atPath: audioURL(for: key).path)
            else { continue }

            let newKey = newURL.sha256 + key.dropFirst(oldFileKey.count)
            try shardedDirectory.ensureShardDirectory(for: newKey)
            try FileManager.default.moveItem(at: audioURL(for: key), to: audioURL(for: newKey))

            sidecar.stamp(from: newURL)
            try writeSidecar(sidecar, for: newKey)
        }
    }
}
