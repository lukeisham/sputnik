import AppKit
import SwiftUI

public enum Tab: String, CaseIterable {
    case imageToASCII = "Image → ASCII"
    case library = "Library"
}

@MainActor
@Observable
public final class ASCIIStudioModel {
    var selectedTab: Tab = .imageToASCII
    var selectedImage: NSImage? = nil
    var asciiPreview: String = ""
    var isConverting: Bool = false

    // Conversion settings
    var targetWidth: Double = 80
    var invert: Bool = false
    var rampStyle: ImageToASCIIConverter.RampStyle = .block
    var customRampString: String = ""
    var conversionMode: ImageToASCIIConverter.Mode = .luminance
    var brightness: Double = 0.0
    var contrast: Double = 1.0
    var ditherMode: ImageToASCIIConverter.DitherMode = .none
    var edgeStyle: ASCIIEdgeDetector.EdgeStyle = .simple
    var lightThreshold: Double = 1.0

    var adjustmentsExpanded: Bool = false
    var selectedCategory: ASCIILibraryBrowser.Category = .frames
    var showEditTools: Bool = false
    var replaceChar: String = ""
    var fillChar: String = ""
    var insertChar: String = " "
    var librarySearchQuery: String = ""
    var sourceImageName: String = ""
    var hasKnownEditor: Bool = false

    // Alert state — owned here so coordinator can bind to them
    var showDiscardWarning: Bool = false
    var pendingAction: (() -> Void)? = nil
    var showNoImageAlert: Bool = false

    let library = ASCIILibraryBrowser()
}
