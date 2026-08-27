// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation
import SPFKBase

/// Binary file format wrapper for waveform cache entries (`.wfcache`).
///
/// Layout: `[header: 64 bytes][url: variable UTF-8][float data]`
///
/// The fixed header contains all metadata needed for freshness checks and
/// `WaveformData` reconstruction. Freshness fields (`modificationDate`,
/// `fileSize`) sit early in the header so a partial read can reach them.
///
/// **Only the current version is readable.** An entry written by an older build is a cache miss
/// rather than a migration — this is a derived cache whose worst case is one re-scan, so carrying a
/// second parser for every past layout costs more than it saves. `WaveformDataStore` deletes what it
/// cannot read.
public struct WaveformCacheFile {
    /// File extension for the unified cache format.
    public static let fileExtension = "wfcache"

    /// Magic bytes identifying this file format: "WFDC".
    public static let magic: [UInt8] = [0x57, 0x46, 0x44, 0x43]

    /// Current format version. 2 added the audio track identifier.
    public static let currentVersion: UInt16 = 2

    /// `flags` bit 0: the entry names a specific audio track rather than the container's default.
    private static let hasAudioTrackFlag: UInt16 = 1 << 0

    /// Fixed header size in bytes (before the variable-length URL).
    public static let fixedHeaderSize = 64

    /// Byte offsets of each fixed-header field. `write` appends these in order rather than
    /// addressing them, so the assert at the end of it is what ties the two halves together.
    private enum Offset {
        static let version = 4
        static let flags = 6
        static let modificationDate = 8
        static let fileSize = 16
        static let audioDuration = 24
        static let sampleRate = 32
        static let samplesPerPoint = 40
        static let channelCount = 44
        static let pointsPerChannel = 48
        static let urlByteCount = 52
        static let audioTrackID = 56
    }

    /// Number of bytes to read for freshness validation: through the end of `fileSize`.
    private static let freshnessReadSize = Offset.fileSize + MemoryLayout<Int64>.size

    private init() {}
}

// MARK: - Write

extension WaveformCacheFile {
    /// Writes a complete waveform cache entry to a single `.wfcache` file.
    public static func write(_ item: WaveformDataItem, to url: URL) throws {
        let floatChannelData = item.waveformData.floatChannelData
        let channelCount = UInt32(floatChannelData.count)
        let pointsPerChannel = UInt32(floatChannelData.first?.count ?? 0)
        let urlBytes = Array(item.url.absoluteString.utf8)
        let urlByteCount = UInt32(urlBytes.count)
        let totalFloats = Int(channelCount) * Int(pointsPerChannel)
        let totalSize = fixedHeaderSize + urlBytes.count + totalFloats * MemoryLayout<Float>.size

        var data = Data(capacity: totalSize)

        // Magic (4 bytes)
        data.append(contentsOf: magic)

        // Version (UInt16) + Flags (UInt16)
        appendValue(&data, currentVersion)
        appendValue(&data, item.audioTrackID == nil ? UInt16(0) : hasAudioTrackFlag)

        // Freshness fields
        appendValue(&data, encodeDate(item.modificationDate))
        appendValue(&data, encodeFileSize(item.fileSize))

        // Audio metadata
        appendValue(&data, Float64(item.waveformData.audioDuration))
        appendValue(&data, Float64(item.waveformData.sampleRate))
        appendValue(&data, UInt32(item.waveformData.samplesPerPoint))

        // Channel layout
        appendValue(&data, channelCount)
        appendValue(&data, pointsPerChannel)
        appendValue(&data, urlByteCount)

        // A flag rather than a sentinel, so every UInt64 stays a legal track identifier.
        appendValue(&data, item.audioTrackID ?? 0)

        assert(data.count == fixedHeaderSize)

        // Variable-length URL
        data.append(contentsOf: urlBytes)

        // Float channel data
        for channel in floatChannelData {
            channel.withUnsafeBufferPointer { buffer in
                data.append(buffer)
            }
        }

        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Read

extension WaveformCacheFile {
    /// Reads a complete waveform cache entry from a `.wfcache` file.
    public static func read(from url: URL) throws -> WaveformDataItem {
        let data = try Data(contentsOf: url)
        try validateMagic(data)

        guard data.count >= fixedHeaderSize else {
            throw NSError(description: "Waveform cache file too small: \(data.count) bytes")
        }

        return try data.withUnsafeBytes { raw in
            let version: UInt16 = raw.load(fromByteOffset: Offset.version, as: UInt16.self)
            guard version == currentVersion else {
                throw NSError(description: "Unsupported waveform cache version: \(version)")
            }

            let flags: UInt16 = raw.load(fromByteOffset: Offset.flags, as: UInt16.self)

            let modDate = decodeDate(raw.load(fromByteOffset: Offset.modificationDate, as: Float64.self))
            let fileSize = decodeFileSize(raw.load(fromByteOffset: Offset.fileSize, as: Int64.self))
            let audioDuration = raw.load(fromByteOffset: Offset.audioDuration, as: Float64.self)
            let sampleRate = raw.load(fromByteOffset: Offset.sampleRate, as: Float64.self)
            let samplesPerPoint = raw.load(fromByteOffset: Offset.samplesPerPoint, as: UInt32.self)
            let channelCount = raw.load(fromByteOffset: Offset.channelCount, as: UInt32.self)
            let pointsPerChannel = raw.load(fromByteOffset: Offset.pointsPerChannel, as: UInt32.self)
            let urlByteCount = raw.load(fromByteOffset: Offset.urlByteCount, as: UInt32.self)

            let audioTrackID: UInt64? = flags & hasAudioTrackFlag != 0
                ? raw.load(fromByteOffset: Offset.audioTrackID, as: UInt64.self)
                : nil

            let urlStart = fixedHeaderSize
            let urlEnd = urlStart + Int(urlByteCount)

            guard urlEnd <= data.count else {
                throw NSError(description: "Waveform cache URL extends past end of file")
            }

            let urlData = data[urlStart ..< urlEnd]
            guard let urlString = String(data: urlData, encoding: .utf8),
                  let sourceURL = URL(string: urlString)
            else {
                throw NSError(description: "Invalid URL in waveform cache file")
            }

            let floatStart = urlEnd
            let expectedFloatBytes = Int(channelCount) * Int(pointsPerChannel) * MemoryLayout<Float>.size
            let expectedTotal = floatStart + expectedFloatBytes

            guard data.count == expectedTotal else {
                throw NSError(
                    description: "Waveform cache size mismatch: expected \(expectedTotal), got \(data.count)"
                )
            }

            // Parse float channel data
            var floatChannelData = FloatChannelData()
            floatChannelData.reserveCapacity(Int(channelCount))

            let channelByteCount = Int(pointsPerChannel) * MemoryLayout<Float>.size
            var offset = floatStart

            for _ in 0 ..< channelCount {
                let channelData = data[offset ..< offset + channelByteCount]
                let floats = channelData.withUnsafeBytes { rawBuffer in
                    Array(rawBuffer.bindMemory(to: Float.self))
                }
                floatChannelData.append(floats)
                offset += channelByteCount
            }

            let waveformData = WaveformData(
                floatChannelData: floatChannelData,
                samplesPerPoint: Int(samplesPerPoint),
                audioDuration: TimeInterval(audioDuration),
                sampleRate: Double(sampleRate)
            )

            return WaveformDataItem(
                url: sourceURL,
                audioTrackID: audioTrackID,
                modificationDate: modDate,
                fileSize: fileSize,
                waveformData: waveformData
            )
        }
    }
}

// MARK: - Freshness

extension WaveformCacheFile {
    /// Lightweight metadata for freshness checks.
    public struct FreshnessInfo: Sendable {
        public let modificationDate: Date?
        public let fileSize: Int?

        public func isFresh(comparedTo fileURL: URL) -> Bool {
            modificationDate == fileURL.modificationDate && fileSize == fileURL.fileSize
        }
    }

    /// Reads only the magic, version, and freshness fields (24 bytes) via `FileHandle`.
    /// Does not load URL or float data.
    public static func readFreshness(from url: URL) throws -> FreshnessInfo {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let headerData = try handle.read(upToCount: freshnessReadSize),
              headerData.count == freshnessReadSize
        else {
            throw NSError(description: "Waveform cache file too small for freshness read")
        }

        try validateMagic(headerData)

        return headerData.withUnsafeBytes { raw in
            let modDate = decodeDate(raw.load(fromByteOffset: Offset.modificationDate, as: Float64.self))
            let fileSize = decodeFileSize(raw.load(fromByteOffset: Offset.fileSize, as: Int64.self))
            return FreshnessInfo(modificationDate: modDate, fileSize: fileSize)
        }
    }

    /// Rewrites the file with updated freshness metadata while preserving all other fields.
    public static func refreshFreshness(at cacheURL: URL, from fileURL: URL) throws {
        var data = try Data(contentsOf: cacheURL)
        try validateMagic(data)

        guard data.count >= fixedHeaderSize else {
            throw NSError(description: "Waveform cache file too small for freshness update")
        }

        var modDate = encodeDate(fileURL.modificationDate)
        data.replaceSubrange(
            Offset.modificationDate ..< Offset.fileSize,
            with: Data(bytes: &modDate, count: MemoryLayout<Float64>.size)
        )

        var size = encodeFileSize(fileURL.fileSize)
        data.replaceSubrange(
            Offset.fileSize ..< Offset.audioDuration,
            with: Data(bytes: &size, count: MemoryLayout<Int64>.size)
        )

        try data.write(to: cacheURL, options: .atomic)
    }
}

// MARK: - Validation

extension WaveformCacheFile {
    /// Returns true if the file at the given URL starts with valid WFDC magic bytes.
    public static func isValid(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let headerData = try? handle.read(upToCount: 4),
              headerData.count == 4
        else { return false }
        return headerData.elementsEqual(magic)
    }
}

// MARK: - Private Helpers

private extension WaveformCacheFile {
    static func appendValue<T>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }

    static func encodeDate(_ date: Date?) -> Float64 {
        date?.timeIntervalSinceReferenceDate ?? 0.0
    }

    static func decodeDate(_ value: Float64) -> Date? {
        value == 0.0 ? nil : Date(timeIntervalSinceReferenceDate: value)
    }

    static func encodeFileSize(_ size: Int?) -> Int64 {
        size.map { Int64($0) } ?? -1
    }

    static func decodeFileSize(_ value: Int64) -> Int? {
        value == -1 ? nil : Int(value)
    }

    static func validateMagic(_ data: Data) throws {
        guard data.count >= 4,
              data[data.startIndex] == magic[0],
              data[data.startIndex + 1] == magic[1],
              data[data.startIndex + 2] == magic[2],
              data[data.startIndex + 3] == magic[3]
        else {
            throw NSError(description: "Invalid waveform cache file: bad magic bytes")
        }
    }
}
