// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKUtils

// MARK: - Waveform Factory

extension FlatToShardedMigration {
    /// Creates a migration for `WaveformDataStore`'s legacy flat `Waveform/` directory.
    ///
    /// - Parameter cachesDirectory: the same `inDirectory` the store was initialized with.
    ///   Old flat location: `<cachesDirectory>/Waveform`. Target: `<cachesDirectory>/Data/Waveform`.
    public static func waveform(inCachesDirectory cachesDirectory: URL) -> Self {
        let oldFlatDirectory = cachesDirectory.appendingPathComponent("Waveform")
        let shardedDirectory = ShardedDirectory(
            rootURL: cachesDirectory.appendingPathComponent("Data/Waveform")
        )
        let wfcacheSuffix = ".\(WaveformCacheFile.fileExtension)"

        return Self(
            oldFlatDirectoryURL: oldFlatDirectory,
            keyExtractor: { file in
                let ext = file.pathExtension
                guard ext == WaveformCacheFile.fileExtension || ext == "json" else { return nil }
                return file.deletingPathExtension().lastPathComponent
            },
            migrateEntry: { key in
                try migrateWaveformEntry(key: key, from: oldFlatDirectory, to: shardedDirectory)
            },
            deleteOldFiles: { key in
                let fm = FileManager.default
                try? fm.removeItem(at: oldFlatDirectory.appendingPathComponent("\(key)\(wfcacheSuffix)"))
                try? fm.removeItem(at: oldFlatDirectory.appendingPathComponent("\(key).json"))
                try? fm.removeItem(at: oldFlatDirectory.appendingPathComponent("\(key).bin"))
            }
        )
    }
}

// MARK: - Waveform Migration Helpers

private struct WaveformLegacyMetadataRecord: Codable {
    let url: URL
    let modificationDate: Date?
    let fileSize: Int?
    let audioDuration: TimeInterval
    let sampleRate: Double
    let samplesPerPoint: Int
}

private func migrateWaveformEntry(
    key: String,
    from oldFlatDirectory: URL,
    to shardedDirectory: ShardedDirectory
) throws {
    let fm = FileManager.default
    let wfcacheSuffix = ".\(WaveformCacheFile.fileExtension)"
    let newURL = shardedDirectory.fileURL(for: key, suffix: wfcacheSuffix)

    let oldWfcache = oldFlatDirectory.appendingPathComponent("\(key).\(WaveformCacheFile.fileExtension)")
    if fm.fileExists(atPath: oldWfcache.path) {
        try shardedDirectory.ensureShardDirectory(for: key)
        if fm.fileExists(atPath: newURL.path) {
            try fm.removeItem(at: oldWfcache)
        } else {
            try fm.moveItem(at: oldWfcache, to: newURL)
        }
        return
    }

    // Legacy .json (+ optional .bin) format
    let oldJSON = oldFlatDirectory.appendingPathComponent("\(key).json")
    guard fm.fileExists(atPath: oldJSON.path) else { return }

    let item = try readLegacyWaveformEntry(key: key, from: oldFlatDirectory)
    try shardedDirectory.ensureShardDirectory(for: key)
    if !fm.fileExists(atPath: newURL.path) {
        try WaveformCacheFile.write(item, to: newURL)
    }
    try? fm.removeItem(at: oldJSON)
    try? fm.removeItem(at: oldFlatDirectory.appendingPathComponent("\(key).bin"))
}

private func readLegacyWaveformEntry(key: String, from oldFlatDirectory: URL) throws -> WaveformDataItem {
    let jsonURL = oldFlatDirectory.appendingPathComponent("\(key).json")
    let binURL = oldFlatDirectory.appendingPathComponent("\(key).bin")
    let jsonData = try Data(contentsOf: jsonURL)
    let decoder = JSONDecoder()

    if FileManager.default.fileExists(atPath: binURL.path) {
        let record = try decoder.decode(WaveformLegacyMetadataRecord.self, from: jsonData)
        let floatChannelData = try readLegacyBinaryData(from: binURL)
        let waveformData = WaveformData(
            floatChannelData: floatChannelData,
            samplesPerPoint: record.samplesPerPoint,
            audioDuration: record.audioDuration,
            sampleRate: record.sampleRate
        )
        return WaveformDataItem(
            url: record.url,
            modificationDate: record.modificationDate,
            fileSize: record.fileSize,
            waveformData: waveformData
        )
    }

    // Oldest format: full-JSON with floatChannelData embedded
    return try decoder.decode(WaveformDataItem.self, from: jsonData)
}

private func readLegacyBinaryData(from url: URL) throws -> FloatChannelData {
    let data = try Data(contentsOf: url)
    let headerSize = 8

    guard data.count >= headerSize else {
        throw NSError(description: "Legacy binary waveform file too small: \(data.count) bytes")
    }

    let channelCount: UInt32 = data.withUnsafeBytes { $0.load(as: UInt32.self) }
    let pointsPerChannel: UInt32 = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
    let expectedSize = headerSize + Int(channelCount) * Int(pointsPerChannel) * MemoryLayout<Float>.size

    guard data.count == expectedSize else {
        throw NSError(
            description: "Legacy binary waveform size mismatch: expected \(expectedSize), got \(data.count)"
        )
    }

    var floatChannelData = FloatChannelData()
    floatChannelData.reserveCapacity(Int(channelCount))
    var offset = headerSize
    let channelByteCount = Int(pointsPerChannel) * MemoryLayout<Float>.size

    for _ in 0 ..< channelCount {
        let channelData = data[offset ..< offset + channelByteCount]
        let floats = channelData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        floatChannelData.append(floats)
        offset += channelByteCount
    }

    return floatChannelData
}
