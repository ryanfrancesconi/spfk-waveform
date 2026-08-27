import AVFoundation
import os.signpost
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKWaveform

@Suite(.tags(.file))
class WaveformDataTests: TestCaseModel {
    let waveformData: WaveformData = {
        let duration: TimeInterval = 60 * 2 // 2 minutes
        let sampleRate: Double = 44100
        let channelCount: Int = 2
        let frameCount: Int = Int(duration * sampleRate)

        var floatChannelData = Array(repeating: [Float](zeros: frameCount), count: channelCount)

        // fill data with dummy sequential numbers
        for n in 0 ..< channelCount {
            for i in 0 ..< frameCount {
                floatChannelData[n][i] = Float(i)
            }
        }

        return WaveformData(
            floatChannelData: floatChannelData,
            samplesPerPoint: WaveformDrawingResolution.lossless.samplesPerPoint,
            audioDuration: duration,
            sampleRate: sampleRate
        )
    }()

    @Test func data() throws {
        #expect(waveformData.floatChannelData.count == 2)
        #expect(waveformData.floatChannelData[0].count == 5_292_000)
        #expect(waveformData.floatChannelData[1].count == 5_292_000)
    }

    @Test func subdata_1() throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)")
        defer { benchmark.stop() }

        let subdata = try waveformData.subdata(in: 0 ... 60) // 1 minute

        #expect(subdata.count == 2)

        for n in 0 ..< subdata.count {
            #expect(subdata[n].first == 0)
            #expect(subdata[n].last == 2_645_999.0)
        }
    }

    @Test func subdataClamped() throws {
        // range is out of bounds so will be clamped to 0 ... duration
        let subdata2 = try waveformData.subdata(in: -1 ... 121)
        #expect(subdata2[0].count == 44100 * 60 * 2)
    }
}

extension WaveformDataTests {
    @Test func subdata_real() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)")
        defer { benchmark.stop() }

        let url = TestBundleResources.shared.tabla_6_channel

        Log.signpost(.begin, name: "parse")
        let parser = WaveformDataParser(resolution: .medium)
        let waveformData = try await parser.parse(url: url)
        Log.signpost(.end, name: "parse")

        #expect(waveformData.channelCount == 6)

        // All channels must have equal frame count
        let fullCount = waveformData.floatChannelData[0].count
        for channel in waveformData.floatChannelData {
            #expect(channel.count == fullCount)
        }

        // Real file must contain non-trivial values
        #expect(waveformData.floatChannelData.contains { $0.max() ?? 0 > 0 })

        Log.signpost(.begin, name: "subdata")
        let halfDuration = waveformData.audioDuration / 2
        let subdata = try waveformData.subdata(in: 0 ... halfDuration)
        Log.signpost(.end, name: "subdata")

        #expect(subdata.count == waveformData.channelCount)

        // Frame count must match the time→index formula used by subdata(in:)
        let expectedCount = Int(halfDuration * waveformData.samplesPerSecond)
        for channel in subdata {
            #expect(channel.count == expectedCount)
        }

        // Subdata from t=0 must share its opening values with the full data
        #expect(Array(subdata[0].prefix(4)) == Array(waveformData.floatChannelData[0].prefix(4)))
    }
}
