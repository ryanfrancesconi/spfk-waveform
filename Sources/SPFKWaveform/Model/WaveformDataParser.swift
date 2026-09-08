// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Accelerate
import AVFAudio
import AVFoundation
import SPFKAudioBase
import SPFKBase

/// Get audio data from a file suitable for waveform visualization
public struct WaveformDataParser: Sendable {
    public let resolution: WaveformDrawingResolution
    public let eventHandler: WaveformDataLoadEventHandler?

    /// Failed reads, with none successful, before the scan gives up on the file. More than one, so
    /// a single bad packet at the head of a readable file is still skipped rather than fatal.
    static let unreadableFileReadAttempts = 4

    public init(
        resolution: WaveformDrawingResolution = .medium,
        eventHandler: WaveformDataLoadEventHandler? = nil
    ) {
        self.resolution = resolution
        self.eventHandler = eventHandler
    }

    public func parse(url: URL) async throws -> WaveformData {
        try await parse(audioFile: AVAudioFile(forReading: url))
    }

    public func parse(audioFile: AVAudioFile) async throws -> WaveformData {
        // store the current frame before scanning the file
        let currentFrame = audioFile.framePosition

        defer {
            // return the file to frame is was on previously
            audioFile.framePosition = currentFrame
        }

        let floatChannelData: FloatChannelData = try await _parse(audioFile: audioFile)

        let waveformData = WaveformData(
            floatChannelData: floatChannelData,
            samplesPerPoint: resolution.samplesPerPoint,
            audioDuration: audioFile.duration,
            sampleRate: audioFile.fileFormat.sampleRate
        )

        await eventHandler?(
            .complete(url: audioFile.url, value: waveformData)
        )

        return waveformData
    }
}

extension WaveformDataParser {
    private func _parse(audioFile: AVAudioFile) async throws -> FloatChannelData {
        guard resolution != .lossless else {
            return try await readEntire(audioFile: audioFile)
        }

        let url = audioFile.url

        var lastSentProgress: UnitInterval = 0
        func send(progress: UnitInterval) async {
            await eventHandler?(.progress(url: url, value: progress))
        }

        let totalFrames = AVAudioFrameCount(audioFile.length)
        let totalFramesDouble = Double(totalFrames)

        guard totalFrames > 0 else {
            throw NSError(description: "No audio was found in \(audioFile.url.path)")
        }

        // will be >= 1
        let samplesPerPoint: Int = resolution.samplesPerPoint

        // analysis buffer size
        var framesPerBuffer = AVAudioFrameCount(samplesPerPoint)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: framesPerBuffer
        ) else {
            throw NSError(description: "Unable to create buffer")
        }

        // divide the file into this amount of chunks, it will take the peak of each chunk
        let chunkCount = totalFrames.int / samplesPerPoint
        let channelCount = audioFile.fileFormat.channelCount.int
        var currentFrame: AVAudioFramePosition = 0

        // allocates with all 0 values
        var outfloatChannelData = allocateFloatChannelData(length: chunkCount, channelCount: channelCount)

        var chunksSkipped: Int = 0

        // scan a chunk and take the max magnitude in it, discard the rest
        for i in 0 ..< chunkCount {
            try Task.checkCancellation()

            audioFile.framePosition = currentFrame

            let didRead: Bool

            do {
                try audioFile.read(into: buffer, frameCount: framesPerBuffer)
                didRead = true

            } catch {
                chunksSkipped += 1
                didRead = false

                // A skipped chunk is one bad packet in a readable file. When no read has succeeded
                // yet, the file is one the decoder cannot open -- a DRM-protected purchase reads
                // this way -- and every remaining read would only repeat the failure.
                if chunksSkipped == i + 1, chunksSkipped >= Self.unreadableFileReadAttempts {
                    throw NSError(
                        description: "Unable to read audio from \(url.lastPathComponent): the first \(chunksSkipped) reads failed (\(error.localizedDescription))"
                    )
                }
            }

            if didRead {
                guard buffer.floatChannelData != nil else {
                    throw NSError(description: "Failed to read from buffer")
                }

                Self.writePeaks(
                    from: buffer,
                    frameCount: framesPerBuffer.int,
                    channelCount: channelCount,
                    into: &outfloatChannelData,
                    at: i
                )
            }

            // Advanced on a skip too, or the next read retries the same frames and every later
            // peak lands one chunk early.
            currentFrame += AVAudioFramePosition(framesPerBuffer)

            // buffer has reached end of file, trim it
            if currentFrame + AVAudioFramePosition(framesPerBuffer) > totalFrames {
                framesPerBuffer = totalFrames - AVAudioFrameCount(currentFrame)

                guard framesPerBuffer > 0 else { break }
            }

            let progress: UnitInterval = Double(currentFrame) / totalFramesDouble

            if progress - lastSentProgress > 0.05 {
                await send(progress: progress)
                lastSentProgress = progress
            }
        }

        if chunksSkipped > 0 {
            Log.error("audioFile.read error skipped \(chunksSkipped)/\(chunkCount) chunks for \(url.path)")
        }

        return outfloatChannelData
    }

    /// read the entire file into memory. should only be used on short files
    private func readEntire(audioFile: AVAudioFile) async throws -> FloatChannelData {
        Log.debug("reading entire file \(audioFile.url.path)")

        guard let buffer = try AVAudioPCMBuffer(audioFile: audioFile) else {
            throw NSError(description: "Unable to create buffer")
        }

        guard let floatData = buffer.floatData else {
            throw NSError(description: "Failed to read from buffer")
        }

        return floatData
    }
}
