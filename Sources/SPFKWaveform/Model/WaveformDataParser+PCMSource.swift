// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import AVFAudio
import AVFoundation
import Accelerate
import SPFKBase

// MARK: - Scanning

public extension WaveformDataParser {
    /// Builds waveform data from decoded PCM rather than from a file.
    ///
    /// The counterpart to ``parse(audioFile:)`` for sources AVFoundation will not open. Everything
    /// downstream — the waveform view, its cache, markers, the editor — consumes the returned
    /// ``WaveformData`` and neither knows nor cares which entry point produced it.
    ///
    /// - Parameter duration: the source's duration in seconds. Taken as a parameter because a
    ///   streamed source generally knows it from its container's header rather than from having
    ///   read to the end.
    func parse(
        pcmSource: some SequentialPCMSource,
        url: URL,
        duration: TimeInterval
    ) async throws -> WaveformData {
        let format = pcmSource.processingFormat
        let channelCount = format.channelCount.int

        let samplesPerPoint = max(resolution.samplesPerPoint, 1)

        // A streamed source may not know its length, so fall back to what the duration implies --
        // the scan needs a chunk count up front to allocate, and reading twice to find out is the
        // thing streaming exists to avoid.
        let totalFrames = pcmSource.totalFrameCount > 0
            ? pcmSource.totalFrameCount
            : AVAudioFramePosition(duration * format.sampleRate)

        guard totalFrames > 0 else {
            throw NSError(description: "No audio was found in \(url.path)")
        }

        let chunkCount = max(Int(totalFrames) / samplesPerPoint, 1)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samplesPerPoint)
        ) else {
            throw NSError(description: "Unable to create buffer")
        }

        var floatChannelData = allocateFloatChannelData(length: chunkCount, channelCount: channelCount)

        var lastSentProgress: UnitInterval = 0
        var index = 0

        while index < chunkCount {
            try Task.checkCancellation()

            let written = try pcmSource.readNextChunk(
                into: buffer,
                frameCount: AVAudioFrameCount(samplesPerPoint)
            )

            guard written > 0 else { break }

            Self.writePeaks(
                from: buffer,
                frameCount: Int(written),
                channelCount: channelCount,
                into: &floatChannelData,
                at: index
            )

            index += 1

            let progress: UnitInterval = Double(index) / Double(chunkCount)

            if progress - lastSentProgress > 0.05 {
                await eventHandler?(.progress(url: url, value: progress))
                lastSentProgress = progress
            }
        }

        // The chunk count came from a duration, which is an estimate -- a container states the
        // segment's length, not the audio track's. Allocating from it and stopping when the source
        // runs out would leave a silent tail on the end of the waveform, so trim to what was read.
        if index < chunkCount {
            for channel in floatChannelData.indices {
                floatChannelData[channel].removeLast(chunkCount - index)
            }
        }

        let waveformData = WaveformData(
            floatChannelData: floatChannelData,
            samplesPerPoint: samplesPerPoint,
            audioDuration: duration,
            sampleRate: format.sampleRate
        )

        await eventHandler?(.complete(url: url, value: waveformData))

        return waveformData
    }
}

// MARK: - Peak reduction

extension WaveformDataParser {
    /// The peak magnitude of one chunk, per channel — the only numerically meaningful step in a
    /// waveform scan, and shared so the file and streamed paths cannot disagree about what a
    /// waveform looks like.
    ///
    /// The two paths around it stay separate on purpose: reading a file is random-access and skips
    /// a chunk it cannot read, while a stream has no seek and no retry.
    static func writePeaks(
        from buffer: AVAudioPCMBuffer,
        frameCount: Int,
        channelCount: Int,
        into floatChannelData: inout FloatChannelData,
        at index: Int
    ) {
        guard let rawData = buffer.floatChannelData, frameCount > 0 else { return }

        for channel in 0 ..< channelCount {
            let bufferPointer = UnsafeBufferPointer(start: rawData[channel], count: frameCount)

            let minimum: Float = vDSP.minimum(bufferPointer)
            let maximum: Float = vDSP.maximum(bufferPointer)
            let value = Float.maximumMagnitude(minimum, maximum)

            if !value.isNaN {
                floatChannelData[channel][index] = value
            }
        }
    }
}
