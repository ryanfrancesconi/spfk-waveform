// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKWaveform

@Suite(.tags(.file))
class WaveformDataParserTests: BinTestCase {
    @Test func parse() async throws {
        let url = TestBundleResources.shared.tabla_6_channel

        let parser = WaveformDataParser(
            resolution: .low,
        )

        let waveformData = try await parser.parse(url: url)

        // channel count for the file
        #expect(waveformData.channelCount == 6)

        for channel in waveformData.floatChannelData {
            #expect(channel.count == 1315)
        }
    }

    // (25 iterations) took 0.09867474999919068 seconds.
    // (50 iterations) took 0.19027300000016112 seconds.
    // (1000 iterations) took 3.5749457916608662 seconds.
    @Test(arguments: [25, 50, 1000]) func parseWithBenchmark(loopCount: Int) async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function) (\(loopCount) iterations)"); defer { benchmark.stop() }

        for _ in 0 ..< loopCount {
            try await parse()
        }
    }

    @Test func parseLossless() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)")
        defer { benchmark.stop() }

        let url = TestBundleResources.shared.cowbell_wav

        let audioFile = try AVAudioFile(forReading: url)
        #expect(audioFile.length == 88201)
        #expect(audioFile.fileFormat.sampleRate == 44100)
        #expect(audioFile.duration == 2.0000226757369615)

        let parser = WaveformDataParser(
            resolution: .lossless,
        )

        let waveformData = try await parser.parse(url: url)

        // channel count for the file
        #expect(waveformData.channelCount == audioFile.fileFormat.channelCount)

        for channel in waveformData.floatChannelData {
            #expect(channel.count == audioFile.length)
        }
    }

    @Test func cancelTask() async throws {
        let input = TestBundleResources.shared.tabla_6_channel

        // Cancel from the parser's own progress callback rather than from a timer:
        // the handler is awaited inside the chunk loop, so the first progress event
        // puts cancellation mid-parse with no dependence on scheduling or wall clock.
        let task = Task<WaveformData, Error>(priority: .high) {
            let parser = WaveformDataParser(resolution: .veryHigh, eventHandler: { event in
                Log.debug(event.progress)

                guard case .progress = event else { return }

                withUnsafeCurrentTask { $0?.cancel() }
            })

            return try await parser.parse(url: input)
        }

        let result = await task.result

        #expect(!result.isSuccess)
        #expect(result.failureValue as? CancellationError != nil)
    }

    // MARK: - Unreadable files

    /// One second of mono float PCM, written and closed.
    private func writeSine(to url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let writer = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false
        )
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100

        let samples = try #require(buffer.floatChannelData?[0])
        for i in 0 ..< 44100 {
            samples[i] = sin(Float(i) * 0.05)
        }

        try writer.write(from: buffer)
    }

    /// Truncates the file behind an open reader. Measured 2026-09-08: the reader keeps its `length`
    /// and format, and every read past the truncation throws -- the same shape a DRM-protected
    /// file presents, where the decoder fails each chunk of an otherwise well-formed container.
    private func truncate(_ url: URL, to bytes: UInt64) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: bytes)
        try handle.close()
    }

    /// A file whose every read fails is thrown once, not skipped once per chunk: a multi-hour
    /// protected audiobook is tens of thousands of chunks, each logging the same decoder error.
    @Test func aFileWhoseEveryReadFailsThrowsRatherThanSkippingEveryChunk() async throws {
        let url = bin.appendingPathComponent("unreadable.wav")
        try writeSine(to: url)

        let audioFile = try AVAudioFile(forReading: url)
        try truncate(url, to: 100)

        let parser = WaveformDataParser(resolution: .low)

        await #expect(throws: (any Error).self) {
            _ = try await parser.parse(audioFile: audioFile)
        }
    }

    /// A read that fails partway is still a skip. The peaks before it survive, and the ones after
    /// land at their own positions rather than one chunk early.
    @Test func aFileThatFailsPartwayKeepsTheReadableHalfInPlace() async throws {
        let url = bin.appendingPathComponent("half.wav")
        try writeSine(to: url)

        let audioFile = try AVAudioFile(forReading: url)
        let dataStart = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
        // Half the samples, as float32.
        try truncate(url, to: dataStart - 22050 * 4)

        let parser = WaveformDataParser(resolution: .low)
        let waveformData = try await parser.parse(audioFile: audioFile)

        let peaks = try #require(waveformData.floatChannelData.first)
        let half = peaks.count / 2

        #expect(peaks.count == 44100 / WaveformDrawingResolution.low.samplesPerPoint)
        // A peak keeps its sign, so magnitude is what says a chunk was read.
        #expect(peaks[0 ..< half - 1].allSatisfy { abs($0) > 0.5 })
        #expect(peaks[(half + 1)...].allSatisfy { $0 == 0 })
    }

    @Test func noDataChunk() async throws {
        let url = TestBundleResources.shared.no_data_chunk
        let request = WaveformDataParser(resolution: .low)

        await #expect(throws: (any Error).self) {
            do {
                _ = try await request.parse(url: url)
            } catch {
                Log.error(error)

                #expect(
                    error.localizedDescription.contains("No audio was found")
                )

                throw error
            }
        }
    }
}
