import Accelerate
import AppKit
import CoreGraphics
import CoreImage

/// Applies edge detection to an image and returns a pixel-intensity buffer
/// for the ASCII converter to map to line-art glyphs.
///
/// Uses a Core Image Sobel edge-detection filter (CISobelH) on the luminance
/// channel, then reads the resulting grayscale intensity values. The converter
/// maps high-intensity (edge) pixels to line characters (`/ \ | _ -`) and
/// low-intensity (non-edge) pixels to spaces.
///
/// SR-5: built on Apple imaging APIs only — no third-party packages.
public enum ASCIIEdgeDetector {

    /// The edge-detection style determines which line-art glyphs are used.
    public enum EdgeStyle: String, CaseIterable, Sendable {
        case simple = "Simple"
        case shaded = "Shaded"
        case dense = "Dense"
    }

    /// Detects edges in `cgImage` and returns a 2D grid of intensity values
    /// (0.0 = no edge, 1.0 = strongest edge), one per output cell.
    ///
    /// The output dimensions are `width × height` — the same geometry the
    /// ASCII converter expects.
    ///
    /// - Parameters:
    ///   - cgImage: The source image (will be resized if needed).
    ///   - width: Target column count.
    ///   - height: Target row count.
    /// - Returns: A flat array of `Double` values in row-major order, or
    ///            `nil` if the Core Image pipeline fails.
    public static func detectEdges(
        in cgImage: CGImage,
        width: Int,
        height: Int
    ) -> [Double]? {
        // 1. Create CIIMage from the CGImage.
        let ciImage = CIImage(cgImage: cgImage)

        // 2. Resample to target size.
        let scaleX = CGFloat(width) / CGFloat(cgImage.width)
        let scaleY = CGFloat(height) / CGFloat(cgImage.height)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // 3. Convert to grayscale (luminance).
        let grayscale = scaled.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0.0
            ])

        // 4. Apply Sobel edge detection.
        //    CISobelH computes horizontal edges; we combine with a threshold.
        guard let edged = CIFilter(name: "CISobelH") else { return nil }
        edged.setValue(grayscale, forKey: kCIInputImageKey)
        guard let edgedImage = edged.outputImage else { return nil }

        // 5. Clamp and threshold for cleaner results.
        let contrast: CGFloat = 1.5
        guard let adjusted = CIFilter(name: "CIColorControls") else { return nil }
        adjusted.setValue(edgedImage, forKey: kCIInputImageKey)
        adjusted.setValue(contrast, forKey: kCIInputContrastKey)
        guard let adjustedImage = adjusted.outputImage else { return nil }

        // 6. Render back to a bitmap context.
        let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
        let bytesPerRow = width * 4
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard
            let cgOut = ciContext.createCGImage(
                adjustedImage,
                from: CGRect(x: 0, y: 0, width: width, height: height)
            )
        else { return nil }

        // Draw into our buffer.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: &rawData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.draw(cgOut, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 7. Extract intensity from the red channel (grayscale, all channels equal).
        var intensities = [Double](repeating: 0, count: width * height)
        for row in 0..<height {
            for col in 0..<width {
                let offset = (row * bytesPerRow) + col * 4
                let r = Double(rawData[offset]) / 255.0
                intensities[row * width + col] = r
            }
        }

        return intensities
    }

    /// Returns the line-art character set for a given edge style.
    public static func characters(for style: EdgeStyle) -> [Character] {
        switch style {
        case .simple:
            // Default: spaces for non-edge, simple line glyphs for edges.
            return [" ", "/", "|", "\\", "_", "-"]
        case .shaded:
            // Shaded: more granular line representation.
            return [" ", ".", ":", "/", "|", "\\", "#"]
        case .dense:
            // Dense: maximum edge detail.
            return [" ", "·", "⋅", "╱", "╲", "─", "│", "╳"]
        }
    }

    /// Maps a normalised intensity (0…1) to a line-art character.
    ///
    /// - Parameters:
    ///   - intensity: Edge strength, 0…1.
    ///   - style: The edge style controlling the character set.
    /// - Returns: A single character.
    public static func character(for intensity: Double, style: EdgeStyle) -> Character {
        let ramp = characters(for: style)
        let idx = min(Int(intensity * Double(ramp.count - 1)), ramp.count - 1)
        return ramp[max(0, idx)]
    }
}
