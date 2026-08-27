// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKWaveform
import SPFKBase
import SPFKTesting
import Testing

@Suite(.tags(.file))
final class WaveformCacheFileTests: BinTestCase {
    @Test func cacheFileDirectRoundTrip() throws {
        let floats: FloatChannelData = [
            [0.0, 1.0, -1.0, Float.pi, Float.leastNormalMagnitude],
            [0.5, -0.5, Float.greatestFiniteMagnitude, 1e-10, 1e10],
        ]

        let waveformData = WaveformData(
            floatChannelData: floats,
            samplesPerPoint: 32,
            audioDuration: 7.5,
            sampleRate: 48000
        )

        let sourceURL = URL(string: "file:///test/direct_roundtrip.wav")!
        let modDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let item = WaveformDataItem(
            url: sourceURL,
            modificationDate: modDate,
            fileSize: 12345,
            waveformData: waveformData
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(WaveformCacheFile.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try WaveformCacheFile.write(item, to: tempFile)
        let readBack = try WaveformCacheFile.read(from: tempFile)

        #expect(readBack.url == sourceURL)
        #expect(readBack.modificationDate == modDate)
        #expect(readBack.fileSize == 12345)
        #expect(readBack.waveformData.floatChannelData == floats)
        #expect(readBack.waveformData.audioDuration == 7.5)
        #expect(readBack.waveformData.sampleRate == 48000)
        #expect(readBack.waveformData.samplesPerPoint == 32)
    }

    @Test func invalidMagicThrows() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(WaveformCacheFile.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Write a file with wrong magic bytes but sufficient size
        var data = Data(repeating: 0xFF, count: 100)
        data[0] = 0xBA
        data[1] = 0xAD
        data[2] = 0xCA
        data[3] = 0xFE
        try data.write(to: tempFile)

        #expect(throws: (any Error).self) {
            _ = try WaveformCacheFile.read(from: tempFile)
        }

        #expect(!WaveformCacheFile.isValid(at: tempFile))
    }

    @Test func freshnessPartialRead() throws {
        let waveformData = WaveformData(
            floatChannelData: [[1.0, 2.0, 3.0]],
            samplesPerPoint: 64,
            audioDuration: 1,
            sampleRate: 44100
        )

        let sourceURL = URL(string: "file:///test/freshness.wav")!
        let modDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let item = WaveformDataItem(
            url: sourceURL,
            modificationDate: modDate,
            fileSize: 99999,
            waveformData: waveformData
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(WaveformCacheFile.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try WaveformCacheFile.write(item, to: tempFile)

        let freshness = try WaveformCacheFile.readFreshness(from: tempFile)
        #expect(freshness.modificationDate == modDate)
        #expect(freshness.fileSize == 99999)
    }

    @Test func nilDateAndSizeRoundTrip() throws {
        let waveformData = WaveformData(
            floatChannelData: [[1.0]],
            samplesPerPoint: 64,
            audioDuration: 1,
            sampleRate: 44100
        )

        let sourceURL = URL(string: "file:///test/nil_fields.wav")!
        let item = WaveformDataItem(
            url: sourceURL,
            modificationDate: nil,
            fileSize: nil,
            waveformData: waveformData
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(WaveformCacheFile.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try WaveformCacheFile.write(item, to: tempFile)
        let readBack = try WaveformCacheFile.read(from: tempFile)

        #expect(readBack.modificationDate == nil)
        #expect(readBack.fileSize == nil)

        let freshness = try WaveformCacheFile.readFreshness(from: tempFile)
        #expect(freshness.modificationDate == nil)
        #expect(freshness.fileSize == nil)
    }

    /// Verifies that `refreshFreshness` updates date and size in the header
    /// while preserving all other fields (URL, audio metadata, float data).
    @Test func refreshFreshnessUpdatesHeader() throws {
        let floats: FloatChannelData = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
        let waveformData = WaveformData(
            floatChannelData: floats,
            samplesPerPoint: 64,
            audioDuration: 5,
            sampleRate: 44100
        )

        let sourceURL = URL(string: "file:///test/refresh_header.wav")!
        let originalDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let item = WaveformDataItem(
            url: sourceURL,
            modificationDate: originalDate,
            fileSize: 10000,
            waveformData: waveformData
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(WaveformCacheFile.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try WaveformCacheFile.write(item, to: tempFile)

        // Verify original freshness
        let before = try WaveformCacheFile.readFreshness(from: tempFile)
        #expect(before.modificationDate == originalDate)
        #expect(before.fileSize == 10000)

        // Create a real temp file to use as the "source file" with known attributes
        let fakeSourceFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: fakeSourceFile) }
        try Data(repeating: 0xAB, count: 54321).write(to: fakeSourceFile)

        // Refresh freshness from the fake source file
        try WaveformCacheFile.refreshFreshness(at: tempFile, from: fakeSourceFile)

        // Verify freshness fields changed
        let after = try WaveformCacheFile.readFreshness(from: tempFile)
        #expect(after.modificationDate == fakeSourceFile.modificationDate)
        #expect(after.fileSize == 54321)
        #expect(after.modificationDate != originalDate)

        // Verify all other fields are preserved
        let readBack = try WaveformCacheFile.read(from: tempFile)
        #expect(readBack.url == sourceURL)
        #expect(readBack.waveformData.floatChannelData == floats)
        #expect(readBack.waveformData.audioDuration == 5)
        #expect(readBack.waveformData.sampleRate == 44100)
        #expect(readBack.waveformData.samplesPerPoint == 64)
    }

    @Test func sizeMismatchThrows() throws {
        let waveformData = WaveformData(
            floatChannelData: [[1.0, 2.0, 3.0]],
            samplesPerPoint: 64,
            audioDuration: 1,
            sampleRate: 44100
        )

        let item = WaveformDataItem(
            url: URL(string: "file:///test/truncated.wav")!,
            waveformData: waveformData
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(WaveformCacheFile.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try WaveformCacheFile.write(item, to: tempFile)

        // Truncate the file — remove some float bytes from the end
        var data = try Data(contentsOf: tempFile)
        data.removeLast(4) // remove one Float
        try data.write(to: tempFile)

        #expect(throws: (any Error).self) {
            _ = try WaveformCacheFile.read(from: tempFile)
        }
    }

    @Test func singleChannelRoundTrip() throws {
        let floats: FloatChannelData = [[0.1, 0.2, 0.3, 0.4, 0.5]]
        let waveformData = WaveformData(
            floatChannelData: floats,
            samplesPerPoint: 128,
            audioDuration: 3,
            sampleRate: 22050
        )

        let item = WaveformDataItem(
            url: URL(string: "file:///test/mono.wav")!,
            waveformData: waveformData
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(WaveformCacheFile.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try WaveformCacheFile.write(item, to: tempFile)
        let readBack = try WaveformCacheFile.read(from: tempFile)

        #expect(readBack.waveformData.floatChannelData == floats)
        #expect(readBack.waveformData.channelCount == 1)
        #expect(readBack.waveformData.samplesPerPoint == 128)
        #expect(readBack.waveformData.sampleRate == 22050)
    }

    @Test func isValidDetectsCacheFiles() throws {
        let waveformData = WaveformData(
            floatChannelData: [[1.0]],
            samplesPerPoint: 64,
            audioDuration: 1,
            sampleRate: 44100
        )

        let item = WaveformDataItem(
            url: URL(string: "file:///test/valid.wav")!,
            waveformData: waveformData
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(WaveformCacheFile.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try WaveformCacheFile.write(item, to: tempFile)
        #expect(WaveformCacheFile.isValid(at: tempFile))

        // Non-existent file
        let fakeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent.wfcache")
        #expect(!WaveformCacheFile.isValid(at: fakeURL))
    }
}
