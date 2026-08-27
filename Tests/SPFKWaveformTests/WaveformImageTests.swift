import Accelerate
import Foundation
import SPFKAudioBase
import SPFKBase
import Testing

@testable import SPFKWaveform

struct WaveformImageTests {
    let sampleData: [Float] = vDSP.ramp(in: -1 ... 1, count: 1000)
    let renderer = WaveformImage()

    // MARK: - createPath

    @Test func createPathFullWaveform() throws {
        let path = try WaveformImage.createPath(
            size: CGSize(width: 200, height: 100),
            channelData: sampleData,
            waveformQuality: .medium,
            waveformDisplay: .full
        )
        #expect(!path.isEmpty)
    }

    @Test func createPathRectifiedWaveform() throws {
        let path = try WaveformImage.createPath(
            size: CGSize(width: 200, height: 100),
            channelData: sampleData,
            waveformQuality: .medium,
            waveformDisplay: .rectified
        )
        #expect(!path.isEmpty)
    }

    @Test func createPathAllQualities() throws {
        for quality in WaveformQuality.allCases {
            let path = try WaveformImage.createPath(
                size: CGSize(width: 200, height: 100),
                channelData: sampleData,
                waveformQuality: quality,
                waveformDisplay: .full
            )
            #expect(!path.isEmpty)
        }
    }

    @Test func createPathZeroWidthThrows() {
        #expect(throws: Error.self) {
            try WaveformImage.createPath(
                size: CGSize(width: 0, height: 100),
                channelData: sampleData,
                waveformQuality: .medium,
                waveformDisplay: .full
            )
        }
    }

    @Test func createPathZeroHeightThrows() {
        #expect(throws: Error.self) {
            try WaveformImage.createPath(
                size: CGSize(width: 100, height: 0),
                channelData: sampleData,
                waveformQuality: .medium,
                waveformDisplay: .full
            )
        }
    }

    // MARK: - createImage

    @Test func createImageFull() throws {
        let image = try renderer.createImage(
            size: CGSize(width: 200, height: 100),
            channelData: sampleData,
            waveformDisplay: .full,
            waveformQuality: .medium,
            strokeColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        )
        #expect(image.width == 200)
        #expect(image.height == 100)
    }

    @Test func createImageRectified() throws {
        let image = try renderer.createImage(
            size: CGSize(width: 150, height: 80),
            channelData: sampleData,
            waveformDisplay: .rectified,
            waveformQuality: .high,
            strokeColor: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        )
        #expect(image.width == 150)
        #expect(image.height == 80)
    }

    @Test func createImageEmptyDataThrows() {
        #expect(throws: Error.self) {
            try renderer.createImage(
                size: CGSize(width: 100, height: 100),
                channelData: [],
                waveformDisplay: .full,
                waveformQuality: .medium,
                strokeColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            )
        }
    }

    @Test func createImageZeroSizeThrows() {
        #expect(throws: Error.self) {
            try renderer.createImage(
                size: .zero,
                channelData: sampleData,
                waveformDisplay: .full,
                waveformQuality: .medium,
                strokeColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            )
        }
    }

    // MARK: - createImages (multi-channel)

    @Test func createImagesMultiChannel() throws {
        let channelData: FloatChannelData = [sampleData, sampleData]
        let images = try renderer.createImages(
            size: CGSize(width: 200, height: 100),
            floatChannelData: channelData,
            waveformDisplay: .full,
            waveformQuality: .medium,
            strokeColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        )
        #expect(images.count == 2)
        #expect(images[0].width == 200)
        #expect(images[1].width == 200)
    }

    @Test func createImagesSingleChannel() throws {
        let channelData: FloatChannelData = [sampleData]
        let images = try renderer.createImages(
            size: CGSize(width: 100, height: 50),
            floatChannelData: channelData,
            waveformDisplay: .rectified,
            waveformQuality: .low,
            strokeColor: CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        )
        #expect(images.count == 1)
    }

    // MARK: - WaveformDisplay

    @Test func waveformDisplayMinMax() {
        #expect(WaveformDisplay.full.minimum == -1)
        #expect(WaveformDisplay.full.maximum == 1)
        #expect(WaveformDisplay.rectified.minimum == 0)
        #expect(WaveformDisplay.rectified.maximum == 1)
    }

    // MARK: - WaveformQuality

    @Test func waveformQualityRawValues() {
        #expect(WaveformQuality.minimum.rawValue == 1)
        #expect(WaveformQuality.low.rawValue == 2)
        #expect(WaveformQuality.medium.rawValue == 5)
        #expect(WaveformQuality.high.rawValue == 8)
        #expect(WaveformQuality.maximum.rawValue == 10)
    }

    @Test func waveformQualityLabels() {
        #expect(WaveformQuality.minimum.label == "Minimum")
        #expect(WaveformQuality.low.label == "Low")
        #expect(WaveformQuality.medium.label == "Medium")
        #expect(WaveformQuality.high.label == "High")
        #expect(WaveformQuality.maximum.label == "Maximum")
    }

}
