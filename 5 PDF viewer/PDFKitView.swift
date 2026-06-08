import SwiftUI
import PDFKit
import AppKit

/// `NSViewRepresentable` that wraps `PDFView` for hosting inside SwiftUI.
///
/// `PDFView` is a pure AppKit view with no SwiftUI equivalent, so `NSViewRepresentable`
/// is the correct interop path (SW-3). The coordinator receives page-change and scale-change
/// notifications from `PDFView` and propagates them back to the view model.
public struct PDFKitView: NSViewRepresentable {

    // MARK: - Bindings

    @Bindable var viewModel: PDFViewerViewModel

    // MARK: - NSViewRepresentable

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor.controlBackgroundColor
        pdfView.delegate = context.coordinator

        // Register for page-change notifications.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // Wire the navigate action so the view model can drive page jumps.
        viewModel.navigateAction = { [weak pdfView] index in
            guard let view = pdfView, let doc = view.document,
                  let page = doc.page(at: index) else { return }
            view.go(to: page)
        }

        // Wire the print action so the toolbar can trigger printing via the PDFView.
        viewModel.printAction = { [weak pdfView] in
            guard let view = pdfView else { return }
            view.print(with: .shared, autoRotate: true)
        }

        // Observe scale changes so the view model stays in sync when the user
        // pinches or uses the PDFView's built-in zoom gesture.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )

        return pdfView
    }

    public func updateNSView(_ pdfView: PDFView, context: Context) {
        // Sync document
        if pdfView.document !== viewModel.document {
            pdfView.document = viewModel.document
        }

        // Sync fit-to-width / manual scale
        if viewModel.isFitToWidth {
            pdfView.autoScales = true
        } else {
            pdfView.autoScales = false
            if pdfView.scaleFactor != viewModel.scaleFactor {
                pdfView.scaleFactor = viewModel.scaleFactor
            }
        }

        // Sync rotation — PDFView.rotation expects Int degrees but uses the same
        // 0/90/180/270 convention as our view model.
        // We apply rotation per-page to avoid PDFView's deprecated property.
        applyRotation(pdfView)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Rotation helper

    private func applyRotation(_ pdfView: PDFView) {
        guard let doc = pdfView.document else { return }
        let target = viewModel.rotation
        // PDFPage.rotation is the angle in degrees (multiple of 90) applied to each page.
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if page.rotation != target {
                page.rotation = target
            }
        }
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, PDFViewDelegate {

        private weak var viewModel: PDFViewerViewModel?

        init(viewModel: PDFViewerViewModel) {
            self.viewModel = viewModel
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document
            else { return }
            let index = doc.index(for: currentPage)
            Task { @MainActor [weak viewModel] in
                viewModel?.currentPageIndex = index
            }
        }

        @objc func scaleChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            let scale = pdfView.scaleFactor
            Task { @MainActor [weak viewModel] in
                guard viewModel?.isFitToWidth == false else { return }
                viewModel?.scaleFactor = scale
            }
        }
    }
}
