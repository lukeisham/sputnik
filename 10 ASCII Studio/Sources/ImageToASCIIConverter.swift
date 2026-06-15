import AppKit
import CoreGraphics

/// Converts an `NSImage` to an ASCII-art string using Rec.601 luminance mapping,
/// with support for brightness, contrast, dithering, and line-art (edge-detection)
/// conversion modes.
///
/// Runs on `Task(priority: .userInitiated)` because the user is waiting for the
/// live preview in the Studio panel (SR-4). CoreGraphics pixel reads are off
/// the main thread; all `NSTextStorage` writes happen on `@MainActor` in the caller.
///
/// SR-3: oversized images are scaled before conversion to keep memory bounded.
public enum ImageToASCIIConverter {

    // MARK: - Conversion mode

    /// The overall conversion strategy.
    public enum Mode: String, CaseIterable, Sendable {
        /// Standard luminance density ramp (existing behaviour).
        case luminance = "Luminance"
        /// Line-art edge-detection mode using Sobel filter.
        case lineArt = "Line-art"
        /// Composite: luminance fill with edge-overlay characters at high-edge cells.
        case composite = "Composite"
    }

    // MARK: - Ramp styles

    /// Character density ramp styles for luminance mapping.
    public enum RampStyle: String, CaseIterable, Sendable {
        case block = "Block"
        case minimal = "Minimal"
        case braille = "Braille"
        case ascii = "ASCII"
        case wide = "Wide"
        case custom = "Custom"

        /// Characters ordered from darkest (index 0) to lightest (last index).
        /// For `.custom`, callers should use `Settings.effectiveCharacters` instead.
        var characters: [Character] {
            switch self {
            case .block: return Array("@#S%?*+;:,. ")
            case .minimal: return Array("#. ")
            case .braille: return Array("⣿⣷⣦⣄⡀ ")
            case .ascii: return Array("MNHQ$OC?7>!:-;. ")
            case .wide: return Array("▓▒░ ")
            case .custom: return Array("MNHQ$OC?7>!:-;. ")  // fallback; use effectiveCharacters
            }
        }
    }

    // MARK: - Dither mode

    /// Dithering algorithm applied during luminance conversion.
    public enum DitherMode: String, CaseIterable, Sendable {
        case none = "None"
        case floydSteinberg = "Floyd–Steinberg"
        case bayer = "Bayer 4×4"
    }

    // MARK: - Conversion settings

    /// All parameters that affect the conversion output.
    public struct Settings: Sendable {
        public var width: Int = 80
        public var invert: Bool = false
        public var style: RampStyle = .block
        public var mode: Mode = .luminance
        public var brightness: Double = 0.0  // -1.0 … 1.0
        public var contrast: Double = 1.0  // 0.0 … 3.0
        public var ditherMode: DitherMode = .none
        public var edgeStyle: ASCIIEdgeDetector.EdgeStyle = .simple
        public var customRampString: String = ""
        /// Pixels brighter than this value are replaced with a space (0.5…1.0; 1.0 = no threshold).
        public var lightThreshold: Double = 1.0

        /// The active character ramp: uses `customRampString` for `.custom` style,
        /// falling back to the `.ascii` preset if the string is empty.
        public var effectiveCharacters: [Character] {
            if style == .custom {
                let chars = Array(customRampString)
                return chars.isEmpty ? RampStyle.ascii.characters : chars
            }
            return style.characters
        }

        public init(
            width: Int = 80,
            invert: Bool = false,
            style: RampStyle = .block,
            mode: Mode = .luminance,
            brightness: Double = 0.0,
            contrast: Double = 1.0,
            ditherMode: DitherMode = .none,
            edgeStyle: ASCIIEdgeDetector.EdgeStyle = .simple,
            customRampString: String = "",
            lightThreshold: Double = 1.0
        ) {
            self.width = width
            self.invert = invert
            self.style = style
            self.mode = mode
            self.brightness = brightness
            self.contrast = contrast
            self.ditherMode = ditherMode
            self.edgeStyle = edgeStyle
            self.customRampString = customRampString
            self.lightThreshold = lightThreshold
        }
    }

    // MARK: - Conversion (primary API)

    /// Converts `image` to a multi-line ASCII string using the given settings.
    ///
    /// - Parameters:
    ///   - image:  Source image.
    ///   - settings: All conversion parameters.
    /// - Returns: A plain `String` of ASCII rows separated by newlines,
    ///            or an empty string if the context cannot be created.
    public static func convert(
        _ image: NSImage,
        settings: Settings
    ) -> String {
        switch settings.mode {
        case .luminance:
            return convertLuminance(image, settings: settings)
        case .lineArt:
            return convertLineArt(image, settings: settings)
        case .composite:
            return convertComposite(image, settings: settings)
        }
    }

    /// Convenience overload for backward compatibility with the old 3-parameter signature.
    public static func convert(
        _ image: NSImage,
        width: Int,
        invert: Bool,
        style: RampStyle
    ) -> String {
        let settings = Settings(width: width, invert: invert, style: style)
        return convert(image, settings: settings)
    }

    // MARK: - Luminance conversion

    /// Converts using the standard Rec.601 luminance ramp with optional
    /// brightness, contrast, light-threshold, and dithering.
    private static func convertLuminance(
        _ image: NSImage,
        settings: Settings
    ) -> String {
        let (width, height) = targetDimensions(image: image, width: settings.width)
        guard width > 0, height > 0 else { return "" }

        guard let pixelData = readPixels(image, width: width, height: height) else { return "" }
        let ramp = settings.effectiveCharacters

        var luminances = [Double](repeating: 0, count: width * height)
        for i in 0..<luminances.count {
            let offset = i * 4
            let r = Double(pixelData[offset]) / 255.0
            let g = Double(pixelData[offset + 1]) / 255.0
            let b = Double(pixelData[offset + 2]) / 255.0
            let alpha = Double(pixelData[offset + 3]) / 255.0

            var lum = alpha < 0.01 ? 1.0 : (0.299 * r + 0.587 * g + 0.114 * b)
            lum = applyBrightnessContrast(lum, brightness: settings.brightness, contrast: settings.contrast)
            lum = max(0.0, min(1.0, lum))
            if settings.invert { lum = 1.0 - lum }
            luminances[i] = lum
        }

        switch settings.ditherMode {
        case .none:
            break
        case .floydSteinberg:
            luminances = applyFloydSteinbergDither(
                to: luminances, width: width, height: height, rampCount: ramp.count)
        case .bayer:
            applyBayerDither(to: &luminances, width: width, height: height)
        }

        var rows = [String]()
        rows.reserveCapacity(height)
        for row in 0..<height {
            var rowChars = ""
            rowChars.reserveCapacity(width)
            for col in 0..<width {
                let idx = row * width + col
                let lum = luminances[idx]
                if lum > settings.lightThreshold {
                    rowChars.append(" ")
                } else {
                    let charIdx = min(Int(lum * Double(ramp.count - 1)), ramp.count - 1)
                    rowChars.append(ramp[charIdx])
                }
            }
            rows.append(rowChars)
        }

        return rows.joined(separator: "\n")
    }

    // MARK: - Line-art conversion

    /// Converts using edge detection, mapping detected edges to line glyphs.
    private static func convertLineArt(
        _ image: NSImage,
        settings: Settings
    ) -> String {
        let (width, height) = targetDimensions(image: image, width: settings.width)
        guard width > 0, height > 0 else { return "" }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        guard
            let intensities = ASCIIEdgeDetector.detectEdges(
                in: cgImage, width: width, height: height
            )
        else { return "" }

        let edgeStyle = settings.edgeStyle
        let edgeRamp = ASCIIEdgeDetector.characters(for: edgeStyle)

        var rows = [String]()
        rows.reserveCapacity(height)
        for row in 0..<height {
            var rowChars = ""
            rowChars.reserveCapacity(width)
            for col in 0..<width {
                let idx = row * width + col
                var intensity = intensities[idx]

                intensity = applyBrightnessContrast(
                    intensity, brightness: settings.brightness, contrast: settings.contrast)
                intensity = max(0.0, min(1.0, intensity))

                let charIdx = min(Int(intensity * Double(edgeRamp.count - 1)), edgeRamp.count - 1)
                rowChars.append(edgeRamp[max(0, charIdx)])
            }
            rows.append(rowChars)
        }

        return rows.joined(separator: "\n")
    }

    // MARK: - Composite conversion

    /// Two-pass conversion: luminance fill with edge-overlay characters at high-edge cells.
    ///
    /// For each cell where edge intensity exceeds the overlay threshold (0.4), the
    /// luminance character is replaced by a border character from the last 3 chars of the ramp.
    private static func convertComposite(
        _ image: NSImage,
        settings: Settings
    ) -> String {
        // two-pass: luminance then edge overlay
        let (width, height) = targetDimensions(image: image, width: settings.width)
        guard width > 0, height > 0 else { return "" }

        guard let pixelData = readPixels(image, width: width, height: height) else { return "" }
        let ramp = settings.effectiveCharacters

        // Pass 1: luminance
        var luminances = [Double](repeating: 0, count: width * height)
        for i in 0..<luminances.count {
            let offset = i * 4
            let r = Double(pixelData[offset]) / 255.0
            let g = Double(pixelData[offset + 1]) / 255.0
            let b = Double(pixelData[offset + 2]) / 255.0
            let alpha = Double(pixelData[offset + 3]) / 255.0

            var lum = alpha < 0.01 ? 1.0 : (0.299 * r + 0.587 * g + 0.114 * b)
            lum = applyBrightnessContrast(lum, brightness: settings.brightness, contrast: settings.contrast)
            lum = max(0.0, min(1.0, lum))
            if settings.invert { lum = 1.0 - lum }
            luminances[i] = lum
        }

        // Pass 2: edge overlay
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let edgeIntensities = ASCIIEdgeDetector.detectEdges(in: cgImage, width: width, height: height)
        else {
            // Fall back to luminance-only if edge detection fails
            let lumSettings = Settings(
                width: settings.width, invert: settings.invert, style: settings.style,
                mode: .luminance, brightness: settings.brightness, contrast: settings.contrast,
                ditherMode: settings.ditherMode, edgeStyle: settings.edgeStyle,
                customRampString: settings.customRampString, lightThreshold: settings.lightThreshold)
            return convertLuminance(image, settings: lumSettings)
        }

        let overlayThreshold = 0.4
        let borderChars: [Character] = {
            let count = ramp.count
            if count >= 3 { return Array(ramp[(count - 3)...]) }
            return ramp.isEmpty ? ["|"] : [ramp.last!]
        }()

        var rows = [String]()
        rows.reserveCapacity(height)
        for row in 0..<height {
            var rowChars = ""
            rowChars.reserveCapacity(width)
            for col in 0..<width {
                let idx = row * width + col
                let edgeIntensity = edgeIntensities[idx]

                if edgeIntensity > overlayThreshold {
                    let borderIdx = min(
                        Int(edgeIntensity * Double(borderChars.count - 1)),
                        borderChars.count - 1)
                    rowChars.append(borderChars[max(0, borderIdx)])
                } else {
                    let lum = luminances[idx]
                    if lum > settings.lightThreshold {
                        rowChars.append(" ")
                    } else {
                        let charIdx = min(Int(lum * Double(ramp.count - 1)), ramp.count - 1)
                        rowChars.append(ramp[charIdx])
                    }
                }
            }
            rows.append(rowChars)
        }

        return rows.joined(separator: "\n")
    }

    // MARK: - Image dimension helpers

    /// Computes target width and height preserving aspect ratio.
    /// SR-3: scales oversized images before conversion.
    private static func targetDimensions(image: NSImage, width: Int) -> (Int, Int) {
        let imageSize = image.size
        let aspectRatio = imageSize.width / max(imageSize.height, 0.1)
        // Character cells are ~2× taller than wide, so halve the row count.
        let height = max(1, Int(Double(width) / aspectRatio / 2.0))
        // Cap maximum dimensions to prevent memory issues (SR-3).
        let maxDim = 500
        if width > maxDim || height > maxDim {
            let scale = min(Double(maxDim) / Double(width), Double(maxDim) / Double(height))
            return (Int(Double(width) * scale), Int(Double(height) * scale))
        }
        return (width, height)
    }

    /// Reads raw RGBA pixel data from an image at the given resolution.
    private static func readPixels(_ image: NSImage, width: Int, height: Int) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

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

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        context.draw(cgImage, in: rect)
        return rawData
    }

    // MARK: - Brightness / contrast

    /// Applies brightness offset and contrast scaling to a normalised luminance value.
    private static func applyBrightnessContrast(
        _ value: Double, brightness: Double, contrast: Double
    ) -> Double {
        var result = value + brightness
        result = (result - 0.5) * contrast + 0.5
        return result
    }

    // MARK: - Floyd–Steinberg dithering

    /// Applies Floyd–Steinberg error diffusion dithering to the luminance grid.
    static func applyFloydSteinbergDither(
        to luminances: [Double], width: Int, height: Int, rampCount: Int
    ) -> [Double] {
        var dithered = luminances
        let levels = Double(rampCount - 1)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let oldPixel = dithered[i]
                let newPixel = round(oldPixel * levels) / levels
                dithered[i] = newPixel
                let quantError = oldPixel - newPixel

                if x + 1 < width {
                    dithered[y * width + (x + 1)] += quantError * (7.0 / 16.0)
                }
                if y + 1 < height {
                    if x > 0 {
                        dithered[(y + 1) * width + (x - 1)] += quantError * (3.0 / 16.0)
                    }
                    dithered[(y + 1) * width + x] += quantError * (5.0 / 16.0)
                    if x + 1 < width {
                        dithered[(y + 1) * width + (x + 1)] += quantError * (1.0 / 16.0)
                    }
                }
            }
        }

        return dithered
    }

    // MARK: - Bayer 4×4 ordered dithering

    /// Applies Bayer 4×4 ordered dithering in-place to the luminance grid.
    ///
    /// Each pixel has a threshold (0…15 mapped to 0…1) added before quantisation,
    /// producing a regular cross-hatched pattern distinct from Floyd–Steinberg.
    static func applyBayerDither(to pixels: inout [Double], width: Int, height: Int) {
        // Standard 4×4 Bayer matrix (threshold values 0…15).
        let bayer: [[Double]] = [
            [ 0, 8, 2, 10],
            [12, 4, 14,  6],
            [ 3, 11, 1,  9],
            [15,  7, 13,  5]
        ]
        let scale = 1.0 / 16.0

        for y in 0..<height {
            for x in 0..<width {
                let threshold = bayer[y % 4][x % 4] * scale
                let i = y * width + x
                pixels[i] = max(0.0, min(1.0, pixels[i] + threshold - 0.5))
            }
        }
    }
}
