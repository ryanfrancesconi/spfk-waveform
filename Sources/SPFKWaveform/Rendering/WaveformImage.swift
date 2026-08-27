// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Accelerate
import CoreGraphics
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKUtils

/// Renders waveform data into CGImages using a reusable bitmap context.
///
/// Maintains an internal `CGContext` that is allocated once and reused across
/// draw calls. The context is only reallocated when the requested size changes.
public final class WaveformImage {
    private var context: CGContext?
    private var contextSize: CGSize = .zero

    public init() {}

    public func createImages(
        size: CGSize,
        floatChannelData: FloatChannelData,
        waveformDisplay: WaveformDisplay,
        waveformQuality: WaveformQuality,
        strokeColor: CGColor
    ) throws -> [CGImage] {
        var images: [CGImage] = []
        images.reserveCapacity(floatChannelData.count)

        for n in 0 ..< floatChannelData.count {
            let image = try createImage(
                size: size,
                channelData: floatChannelData[n],
                waveformDisplay: waveformDisplay,
                waveformQuality: waveformQuality,
                strokeColor: strokeColor
            )
            images.append(image)
        }

        return images
    }

    public func createImage(
        size: CGSize,
        channelData: [Float],
        waveformDisplay: WaveformDisplay,
        waveformQuality: WaveformQuality,
        strokeColor: CGColor
    ) throws -> CGImage {
        guard !channelData.isEmpty else {
            throw NSError(description: "data is empty")
        }

        guard size.width > 0, size.height > 0 else {
            throw NSError(description: "Both width and height must be > 0, size is: \(size)")
        }

        let context = try getContext(size: size)

        let path = try Self.createPath(
            size: size,
            channelData: channelData,
            waveformQuality: waveformQuality,
            waveformDisplay: waveformDisplay
        )

        // Clear the buffer
        context.clear(CGRect(origin: .zero, size: size))

        // Stroke the path
        context.setStrokeColor(strokeColor)
        context.addPath(path)
        context.strokePath()

        guard let image = context.makeImage() else {
            throw NSError(description: "Failed to create CGImage from context")
        }

        return image
    }

    /// Returns a reusable CGContext, reallocating only when the size changes.
    private func getContext(size: CGSize) throws -> CGContext {
        let width = Int(size.width)
        let height = Int(size.height)

        if let context, contextSize == size {
            return context
        }

        guard let newContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(description: "Failed to create CGContext, width: \(width), height: \(height)")
        }

        newContext.setShouldAntialias(true)
        newContext.setAllowsAntialiasing(true)
        newContext.interpolationQuality = .low

        self.context = newContext
        contextSize = size

        return newContext
    }
}

extension WaveformImage {
    /// Create a CGPath from audio data points scaled from minimum to maximum.
    /// This sets the range of values, so a rectified waveform would have a minimum
    /// of 0 whereas a full waveform is -1.
    ///
    /// WaveformQuality is the oversample value in the stride, 1-10
    public static func createPath(
        size: CGSize,
        channelData: [Float],
        waveformQuality: WaveformQuality,
        waveformDisplay: WaveformDisplay
    ) throws -> CGPath {
        guard size.width > 0, size.height > 0 else {
            throw NSError(description: "Create Path: Size must be > 0")
        }

        let minimum = waveformDisplay.minimum
        let maximum = waveformDisplay.maximum
        let rawCount = channelData.count

        // increase the resolution of the stride
        let oversampleBy = waveformQuality.rawValue

        // 1:1 over the width
        let rawStride: CGFloat = rawCount.cgFloat / size.width

        // then divde by the quality value which makes the stride smaller
        let strideWidth: Int = max(1, rawStride / oversampleBy).int

        // the size of the final array of points
        let strideCount: Int = (rawCount / strideWidth) + 1

        let xScale = size.width / CGFloat(strideCount)
        let yScale = CGFloat(1 / (maximum - minimum))

        let cgPath = CGMutablePath()

        var index = 0
        for i in stride(from: 0, to: rawCount, by: strideWidth) {
            let yValue = CGFloat(channelData[i] - minimum)
            let point = CGPoint(
                x: xScale * CGFloat(index),
                y: yScale * yValue * size.height
            )

            if index == 0 {
                cgPath.move(to: point)
            } else {
                cgPath.addLine(to: point)
            }

            index += 1
        }

        return cgPath
    }
}
