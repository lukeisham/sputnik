import AppKit
import Foundation
import FoundationModule
import ResourcesModule
import WebKit

/// A `WKURLSchemeHandler` that streams downsampled image bytes for the `sputnik-img` scheme.
///
/// Usage: register on `WKWebViewConfiguration` and rewrite local `<img src>` values to
/// `sputnik-img://host/<percent-encoded-relative-path>` in the HTML preprocessing step.
///
/// This handler:
/// - Decodes the percent-encoded path component
/// - Resolves it against the coordinator's `currentBaseURL`
/// - Streams the downsampled bytes (or a 1×1 placeholder for too-large/not-found)
/// - Never grants broad file access; keeps HTML string small (SR-3)
/// - Never re-enables JavaScript (ISS-010 unaffected)
final class SputnikImageSchemeHandler: NSObject, WKURLSchemeHandler {

    weak var coordinator: HTMLPreviewCoordinator?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let urlRequest = urlSchemeTask.request

        guard let url = urlRequest.url else {
            respondWithError(urlSchemeTask)
            return
        }

        // Extract the percent-encoded path from sputnik-img://host/<path>
        guard let encodedPath = url.host.flatMap({ _ in url.path }),
            !encodedPath.isEmpty
        else {
            respondWithError(urlSchemeTask)
            return
        }

        // Decode percent-encoding
        guard let relativePath = encodedPath.removingPercentEncoding else {
            respondWithError(urlSchemeTask)
            return
        }

        // Resolve against the coordinator's base directory
        guard let baseDir = coordinator?.currentBaseURL else {
            respondWithPlaceholder(urlSchemeTask)
            return
        }

        // Fetch the image via the shared cache (avoids redundant decode — SR-3)
        Task(priority: .utility) { [weak self] in
            guard let self else { return }

            let resolver = PreviewImageResolver()
            let resolved = await resolver.resolve(reference: relativePath, relativeTo: baseDir)

            var cachedImage: NSImage?
            if case .image(let data, _, _) = resolved {
                cachedImage = NSImage(data: data)
            }

            await MainActor.run {
                if let cachedImage, let tiffData = cachedImage.tiffRepresentation {
                    self.respond(urlSchemeTask, data: tiffData, mimeType: "image/tiff")
                } else {
                    // Serve a 1×1 transparent PNG placeholder
                    self.respondWithPlaceholder(urlSchemeTask)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No-op; task cancellation is handled by task scope cleanup
    }

    // MARK: - Response helpers

    /// Responds with the image data and MIME type.
    private func respond(_ task: WKURLSchemeTask, data: Data, mimeType: String) {
        let response = URLResponse(
            url: task.request.url ?? URL(fileURLWithPath: "/"),
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// Serves a 1×1 transparent PNG placeholder.
    private func respondWithPlaceholder(_ task: WKURLSchemeTask) {
        let pngBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let data = Data(base64Encoded: pngBase64) else {
            respondWithError(task)
            return
        }
        respond(task, data: data, mimeType: "image/png")
    }

    /// Responds with an HTTP error.
    private func respondWithError(_ task: WKURLSchemeTask) {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)
        task.didFailWithError(error)
    }
}
