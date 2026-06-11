import Foundation
import FoundationModule
import Observation
import PDFKit
import ResourcesModule

/// Observable view model that owns the loaded `PDFDocument` and all UI state for the
/// PDF Viewer panel. All mutations are `@MainActor`-isolated; heavy file I/O runs on
/// background `Task` priorities and publishes results back to the main actor (SR-4, SW-1).
@Observable
@MainActor
public final class PDFViewerViewModel {

    // MARK: - Document state

    /// The currently loaded PDF document. `nil` when nothing is open.
    public var document: PDFDocument?

    /// Zero-based index of the currently visible page.
    public var currentPageIndex: Int = 0

    /// Total number of pages in the current document.
    public var totalPageCount: Int { document?.pageCount ?? 0 }

    // MARK: - View state

    /// Zoom scale applied to the `PDFView` (range 0.25…4.0). Ignored when `isFitToWidth`.
    public var scaleFactor: CGFloat = 1.0

    /// When `true`, the `PDFView` auto-scales to fill the available width.
    public var isFitToWidth: Bool = true

    /// Last manual scale factor saved before toggling fit-to-width, so the value can
    /// be restored when the user toggles back.
    private var savedScaleFactor: CGFloat = 1.0

    /// Cumulative clockwise rotation in degrees (0, 90, 180, or 270).
    public var rotation: Int = 0

    // MARK: - Sidebar state

    /// Whether the Table of Contents sidebar is shown.
    public var isTOCVisible: Bool = false

    /// Whether the Thumbnails sidebar is shown.
    public var isThumbnailsVisible: Bool = false

    // MARK: - Async / error state

    /// `true` while `PDFDocument(url:)` is in flight.
    public var isLoading: Bool = false

    /// Non-nil when the last load attempt failed.
    public var errorMessage: String?

    // MARK: - Load limits

    private let maxPages = 10_000
    private let maxFileSize: Int64 = 500 * 1_024 * 1_024  // 500 MB

    // MARK: - Last loaded URL (for retry)

    private var lastURL: URL?

    // MARK: - Thumbnail cache

    /// Cached thumbnails keyed by zero-based page index. Cleared on document change.
    public var thumbnailCache: [Int: NSImage] = [:]

    // MARK: - PDFView action bindings
    //
    // These closures are set by `PDFKitView.makeNSView` and let the view model drive
    // the underlying `PDFView` without holding a direct reference to it (avoids retain cycles).

    /// Navigates the `PDFView` to the given zero-based page index.
    var navigateAction: ((Int) -> Void)?

    /// Triggers the `PDFView` print dialog.
    var printAction: (() -> Void)?

    // MARK: - Init

    public init() {}

    // MARK: - Load

    /// Loads the PDF at `url` on a background task. Updates `document`, `totalPageCount`,
    /// `currentPageIndex`, and `errorMessage` on `@MainActor`. Enforces page and size limits.
    public func loadPDF(_ url: URL) async {
        guard !isLoading else { return }
        lastURL = url
        isLoading = true
        errorMessage = nil
        thumbnailCache.removeAll()
        currentPageIndex = 0
        rotation = 0

        // File size check before loading — avoids reading a rejected file into RAM.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? Int64, size > maxFileSize
        {
            isLoading = false
            let mb = size / (1024 * 1024)
            errorMessage = "This PDF is \(mb) MB, which exceeds the 500 MB limit."
            return
        }

        let result = await Task(priority: .utility) {
            PDFDocument(url: url)
        }.value

        isLoading = false

        guard let loaded = result else {
            errorMessage = "Cannot open \"\(url.lastPathComponent)\" — not a valid PDF file."
            return
        }

        // Page count check
        guard loaded.pageCount > 0 else {
            errorMessage = "This PDF appears to be corrupted (zero pages)."
            return
        }
        if loaded.pageCount > maxPages {
            errorMessage = "This PDF has \(loaded.pageCount) pages (limit: \(maxPages))."
            return
        }

        document = loaded
    }

    /// Re-attempts loading the last URL. No-ops if no URL was previously attempted.
    public func retryLoad() async {
        guard let url = lastURL else { return }
        await loadPDF(url)
    }

    /// Loads an image file (PNG, JPEG) as a single-page `PDFDocument` so the viewer's
    /// zoom, rotate, fit, and print controls work with images. The resolver enforces a
    /// 20 MB byte cap and 2000 px pixel cap (downsamples on load).
    public func loadImage(_ url: URL) async {
        guard !isLoading else { return }
        lastURL = url
        isLoading = true
        errorMessage = nil
        thumbnailCache.removeAll()
        currentPageIndex = 0
        rotation = 0

        // File size check before loading — avoids reading a rejected file into RAM.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? Int64, size > maxFileSize
        {
            isLoading = false
            let mb = size / (1024 * 1024)
            errorMessage = "This image is \(mb) MB, which exceeds the 500 MB limit."
            return
        }

        let resolver = PreviewImageResolver()
        let baseDir = url.deletingLastPathComponent()
        let filename = url.lastPathComponent
        let resolved = await resolver.resolve(reference: filename, relativeTo: baseDir)

        let result = await Task(priority: .utility) -> PDFDocument? {
            let img = await PreviewImageCache.shared.image(for: url) {
                if case .image(let data, _, _) = resolved {
                    return NSImage(data: data)
                }
                return nil
            }
            guard let image = img else { return nil }
            let page = PDFPage(image: image)
            let doc = PDFDocument()
            doc.insert(page, at: 0)
            return doc
        }.value

        isLoading = false

        guard let loaded = result else {
            errorMessage =
                "Cannot open \"\(url.lastPathComponent)\" — not a valid PNG or JPEG file."
            return
        }

        document = loaded
    }

    // MARK: - Navigation

    /// Navigates to `index` (zero-based), clamped to valid bounds.
    public func navigateTo(page index: Int) {
        guard let doc = document, doc.pageCount > 0 else { return }
        let clamped = min(max(0, index), doc.pageCount - 1)
        navigateAction?(clamped)
        currentPageIndex = clamped
    }

    /// Navigates to the next page, stopping at the last page.
    public func navigateNext() {
        navigateTo(page: currentPageIndex + 1)
    }

    /// Navigates to the previous page, stopping at the first page.
    public func navigatePrevious() {
        navigateTo(page: currentPageIndex - 1)
    }

    // MARK: - Zoom

    /// Increases zoom by 0.25, capped at 4.0.
    public func zoomIn() {
        isFitToWidth = false
        scaleFactor = min(4.0, scaleFactor + 0.25)
    }

    /// Decreases zoom by 0.25, floored at 0.25.
    public func zoomOut() {
        isFitToWidth = false
        scaleFactor = max(0.25, scaleFactor - 0.25)
    }

    /// Toggles between fit-to-width mode and the last manual scale factor.
    public func toggleFitToWidth() {
        if isFitToWidth {
            isFitToWidth = false
            scaleFactor = savedScaleFactor
        } else {
            savedScaleFactor = scaleFactor
            isFitToWidth = true
        }
    }

    // MARK: - Rotation

    /// Adds 90° clockwise, wrapping at 360°.
    public func rotateClockwise() {
        rotation = (rotation + 90) % 360
    }

    // MARK: - Error / close

    /// Clears the current error message.
    public func clearError() {
        errorMessage = nil
    }

    /// Closes the current document and resets all state to defaults.
    public func closeDocument() {
        document = nil
        currentPageIndex = 0
        scaleFactor = 1.0
        savedScaleFactor = 1.0
        isFitToWidth = true
        rotation = 0
        isTOCVisible = false
        isThumbnailsVisible = false
        isLoading = false
        errorMessage = nil
        thumbnailCache.removeAll()
        lastURL = nil
    }

    // MARK: - Thumbnail generation

    /// Generates and caches the thumbnail for `pageIndex` if not already cached.
    /// Runs on a background task; no-ops silently on failure.
    public func generateThumbnail(for pageIndex: Int) {
        guard thumbnailCache[pageIndex] == nil,
            let page = document?.page(at: pageIndex)
        else { return }

        Task(priority: .background) { [weak self] in
            let size = CGSize(width: 120, height: 160)
            let image = page.thumbnail(of: size, for: .mediaBox)
            await MainActor.run {
                self?.thumbnailCache[pageIndex] = image
            }
        }
    }
}
