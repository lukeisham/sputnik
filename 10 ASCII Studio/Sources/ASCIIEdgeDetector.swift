import AppKit
import CoreGraphics
import CoreImage

/// Applies edge detection to an image and returns a pixel-intensity buffer
/// for the ASCII converter to map to line-art glyphs.
///
/// Runs both horizontal (`CISobelH`) and vertical (`CISobelV`) Sobel passes,
/// then computes gradient magnitude per pixel as `√(Gx² + Gy²)` and normalises
/// the result to 0…1. Both filters are macOS 10.10+; macOS 14 is required by the
/// project so no deployment-target guard is needed.
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
        // 1. Create CIImage from the CGImage.
        let ciImage = CIImage(cgImage: cgImage)

        // 2. Resample to target size.
        let scaleX = CGFloat(width) / CGFloat(cgImage.width)
        let scaleY = CGFloat(height) / CGFloat(cgImage.height)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // 3. Convert to grayscale (luminance).
        let grayscale = scaled.applyingFilter(
            "CIColorControls",
            parameters: [kCIInputSaturationKey: 0.0]
        )

        // 4. Apply horizontal and vertical Sobel passes (both macOS 10.10+).
        guard let sobelH = CIFilter(name: "CISobelH"),
              let sobelV = CIFilter(name: "CISobelV")
        else { return nil }
        sobelH.setValue(grayscale, forKey: kCIInputImageKey)
        sobelV.setValue(grayscale, forKey: kCIInputImageKey)
        guard let edgedH = sobelH.outputImage,
              let edgedV = sobelV.outputImage
        else { return nil }

        // 5. Render both passes to pixel buffers.
        let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
        let outputRect = CGRect(x: 0, y: 0, width: width, height: height)
        guard
            let cgH = ciContext.createCGImage(edgedH, from: outputRect),
            let cgV = ciContext.createCGImage(edgedV, from: outputRect)
        else { return nil }

        let bytesPerRow = width * 4
        var rawH = [UInt8](repeating: 0, count: height * bytesPerRow)
        var rawV = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard
            let ctxH = CGContext(data: &rawH, width: width, height: height,
                                 bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                 space: colorSpace, bitmapInfo: bitmapInfo),
            let ctxV = CGContext(data: &rawV, width: width, height: height,
                                 bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                 space: colorSpace, bitmapInfo: bitmapInfo)
        else { return nil }

        ctxH.draw(cgH, in: outputRect)
        ctxV.draw(cgV, in: outputRect)

        // 6. Compute gradient magnitude: √(Gx² + Gy²), then normalise to 0…1.
        var intensities = [Double](repeating: 0, count: width * height)
        var maxMag = 0.0
        for row in 0..<height {
            for col in 0..<width {
                let offset = row * bytesPerRow + col * 4
                let gx = Double(rawH[offset]) / 255.0
                let gy = Double(rawV[offset]) / 255.0
                let mag = (gx * gx + gy * gy).squareRoot()
                intensities[row * width + col] = mag
                if mag > maxMag { maxMag = mag }
            }
        }
        if maxMag > 0 {
            for i in intensities.indices { intensities[i] /= maxMag }
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
