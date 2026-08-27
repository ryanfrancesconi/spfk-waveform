// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import CryptoKit
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKUtils

public actor WaveformDataStore {
    /// Sharded cache root: `<inDirectory>/Data/Waveform/<shard>/<key>.wfcache`
    public nonisolated let directoryURL: URL
    nonisolated let shardedDirectory: ShardedDirectory

    private static let wfcacheSuffix = ".\(WaveformCacheFile.fileExtension)"

    public init(inDirectory: URL) throws {
        directoryURL = inDirectory.appendingPathComponent("Data/Waveform")
        shardedDirectory = ShardedDirectory(rootURL: directoryURL)
        try Self.ensureDirectory(at: directoryURL)
    }

    private static func ensureDirectory(at url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func cacheFileURL(for key: String) -> URL {
        shardedDirectory.fileURL(for: key, suffix: Self.wfcacheSuffix)
    }

    private func entryKeys() -> [String] {
        shardedDirectory.entryKeys(suffix: Self.wfcacheSuffix)
    }

    private func deleteFiles(for key: String) {
        try? FileManager.default.removeItem(at: cacheFileURL(for: key))
    }

    /// Every entry belonging to one file, whichever track each names.
    ///
    /// A file's entries all begin with its hash — see `WaveformCacheKey.storageKey` — so this is a
    /// prefix match rather than an equality test. Anything that compares whole keys against file
    /// hashes treats every per-track entry as belonging to no file at all.
    private func entryKeys(forFileKey fileKey: String) -> [String] {
        entryKeys().filter { $0 == fileKey || $0.hasPrefix("\(fileKey)-") }
    }
}

// MARK: - Public

extension WaveformDataStore {
    /// Returns the cached waveform if the file hasn't changed, otherwise deletes the stale record and returns nil.
    ///
    /// **An entry that cannot be read is a miss, not an error.** This is a derived cache: a header
    /// written by an older build, or a truncated file, costs one re-scan, where propagating the
    /// throw would fail the load of a perfectly good audio file.
    public func fetchIfFresh(key: WaveformCacheKey) throws -> WaveformDataItem? {
        let storageKey = key.storageKey
        let cacheFile = cacheFileURL(for: storageKey)
        let url = key.url

        guard FileManager.default.fileExists(atPath: cacheFile.path) else { return nil }

        do {
            let freshness = try WaveformCacheFile.readFreshness(from: cacheFile)

            guard freshness.isFresh(comparedTo: url) else {
                Log.debug("stale waveform for \(url.lastPathComponent), deleting cached entry")
                deleteFiles(for: storageKey)
                return nil
            }

            return try WaveformCacheFile.read(from: cacheFile)

        } catch {
            Log.debug("unreadable waveform cache for \(url.lastPathComponent), deleting: \(error)")
            deleteFiles(for: storageKey)
            return nil
        }
    }

    public func insert(dto: WaveformDataItem) throws {
        let key = dto.cacheKey.storageKey
        try shardedDirectory.ensureShardDirectory(for: key)
        try WaveformCacheFile.write(dto, to: cacheFileURL(for: key))
    }

    public func fetch(key: WaveformCacheKey) throws -> WaveformDataItem {
        let cacheFile = cacheFileURL(for: key.storageKey)

        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            throw NSError(description: "No waveform data for \(key.url)")
        }

        return try WaveformCacheFile.read(from: cacheFile)
    }

    /// Removes every cached waveform for `url`, across all of its audio tracks.
    ///
    /// Per-file rather than per-track because every caller means "this file's waveform is gone" —
    /// the file was deleted, or its contents changed under us.
    public func delete(url: URL) throws {
        let keys = entryKeys(forFileKey: url.sha256)

        guard keys.isEmpty == false else {
            throw NSError(description: "No waveform data for \(url)")
        }

        for key in keys {
            deleteFiles(for: key)
        }
    }

    public func deleteAll() {
        let fm = FileManager.default
        guard let shardDirs = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for shardDir in shardDirs {
            guard (try? shardDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let files = try? fm.contentsOfDirectory(at: shardDir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == WaveformCacheFile.fileExtension {
                try? fm.removeItem(at: file)
            }
        }
    }

    public func count() throws -> Int {
        entryKeys().count
    }

    /// Removes cached waveform records for URLs that are no longer in any playlist.
    /// - Parameter activeURLs: the set of URLs currently referenced by playlists
    /// - Returns: the number of orphaned records removed
    @discardableResult
    public func prune(activeURLs: Set<URL>) throws -> Int {
        try prune(activeKeys: Set(activeURLs.map(\.sha256)))
    }

    /// Removes cached waveform records whose file is not in `activeKeys`.
    /// Prefer this overload when the caller already has pre-computed SHA256 keys.
    ///
    /// **Matches the file part of each entry, not the whole key.** An entry naming a track is
    /// `<hash>-<track>`, which is in no set of URL hashes — comparing whole keys deletes every
    /// per-track waveform on the next sweep and re-scans them all on the next load.
    ///
    /// - Parameter activeKeys: SHA256 hex strings of URLs currently referenced by playlists
    /// - Returns: the number of orphaned records removed
    @discardableResult
    public func prune(activeKeys: Set<String>) throws -> Int {
        // An empty set means the caller could not enumerate what is live, not that nothing is.
        // Pruning against it deletes every entry here.
        guard activeKeys.isNotEmpty else { return 0 }

        var removedCount = 0

        for key in entryKeys() where !activeKeys.contains(Self.fileKey(ofEntry: key)) {
            Log.debug("pruning orphaned waveform cache: \(key)")
            deleteFiles(for: key)
            removedCount += 1
        }

        return removedCount
    }

    /// The file half of an entry key, dropping any `-<track>` suffix.
    static func fileKey(ofEntry key: String) -> String {
        guard let separator = key.firstIndex(of: "-") else { return key }

        return String(key[key.startIndex ..< separator])
    }

    /// Updates the freshness metadata (modificationDate, fileSize) for a cached waveform
    /// without re-parsing the waveform data. Call after ShadowTag saves metadata to a file
    /// so the cache doesn't get invalidated by our own modification date bump.
    /// Restamps every cached waveform for `url` after the app's own write bumped its modification
    /// date.
    ///
    /// All of the file's tracks, not just one: a save changes the file, so every entry derived from
    /// it goes stale at the same moment and would otherwise be re-scanned one track at a time.
    public func refreshFreshness(url: URL) throws {
        for key in entryKeys(forFileKey: url.sha256) {
            let cacheFile = cacheFileURL(for: key)

            guard FileManager.default.fileExists(atPath: cacheFile.path) else { continue }

            try WaveformCacheFile.refreshFreshness(at: cacheFile, from: url)
        }
    }

    /// No-op for waveform store — each insert writes immediately.
    /// Kept for API compatibility with callers that call save() generically.
    public func save() throws {}
}
