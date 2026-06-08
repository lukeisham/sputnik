import AppKit
import CoreGraphics

/// Converts an `NSImage` to an ASCII-art string using Rec.601 luminance mapping.
///
/// Runs on `Task(priority: .userInitiated)` because the user is waiting for the
/// live preview in the Studio panel (SR-4). CoreGraphics pixel reads are off
/// the main thread; all `NSTextStorage` writes happen on `@MainActor` in the caller.
public enum ImageToASCIIConverter {

    // MARK: - Ramp styles

    /// Character density ramp styles for luminance mapping.
    public enum RampStyle: String, CaseIterable, Sendable {
        case block   = "Block"
        case minimal = "Minimal"
        case braille = "Braille"

        /// Characters ordered from darkest (index 0) to lightest (last index).
        var characters: [Character] {
            switch self {
            case .block:   return Array("@#S%?*+;:,. ")
            case .minimal: return Array("#. ")
            case .braille: return Array("⣿⣷⣦⣄⡀ ")
            }
        }
    }

    // MARK: - Conversion

    /// Converts `image` to a multi-line ASCII string.
    ///
    /// - Parameters:
    ///   - image:  Source image.
    ///   - width:  Target column count. Height is derived from the aspect ratio,
    ///             corrected for the typical 2:1 character-cell height-to-width ratio.
    ///   - invert: Reverses luminance mapping (for dark backgrounds).
    ///   - style:  The density-ramp character set.
    /// - Returns: A plain `String` of ASCII rows separated by newlines,
    ///            or an empty string if the context cannot be created.
    public static func convert(
        _ image: NSImage,
        width:   Int,
        invert:  Bool,
        style:   RampStyle
    ) -> String {
        let imageSize   = image.size
        let aspectRatio = imageSize.width / max(imageSize.height, 1)
        // Character cells are ~2× taller than wide, so halve the row count.
        let height      = max(1, Int(Double(width) / aspectRatio / 2.0))

        // Draw into a CGBitmapContext at the target resolution.
        let colorSpace  = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var rawData     = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data:             &rawData,
            width:            width,
            height:           height,
            bitsPerComponent: 8,
            bytesPerRow:      bytesPerRow,
            space:            colorSpace,
            bitmapInfo:       CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return "" }

        let rect    = CGRect(x: 0, y: 0, width: width, height: height)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        context.draw(cgImage, in: rect)

        // Map each pixel to a ramp character.
        let ramp = style.characters
        var rows = [String]()
        rows.reserveCapacity(height)

        for row in 0 ..< height {
            var rowChars = ""
            rowChars.reserveCapacity(width)
            for col in 0 ..< width {
                let offset = (row * bytesPerRow) + col * 4
                let r      = Double(rawData[offset])     / 255.0
                let g      = Double(rawData[offset + 1]) / 255.0
                let b      = Double(rawData[offset + 2]) / 255.0
                // Zero-alpha pixel → treat as white (fully transparent = background).
                let alpha  = Double(rawData[offset + 3]) / 255.0
                var lum    = alpha < 0.01 ? 1.0 : (0.299 * r + 0.587 * g + 0.114 * b)
                if invert { lum = 1.0 - lum }
                let idx    = min(Int(lum * Double(ramp.count - 1)), ramp.count - 1)
                rowChars.append(ramp[idx])
            }
            rows.append(rowChars)
        }
        return rows.joined(separator: "\n")
    }
}
