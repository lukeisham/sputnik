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

    func webView(_ webView: WKWebView, start urlRequest: URLRequest) {
        guard let url = urlRequest.url else {
            respondWithError(to: urlRequest)
            return
        }

        // Extract the percent-encoded path from sputnik-img://host/<path>
        guard let encodedPath = url.host.flatMap({ _ in url.path }),
            !encodedPath.isEmpty
        else {
            respondWithError(to: urlRequest)
            return
        }

        // Decode percent-encoding
        guard let relativePath = encodedPath.removingPercentEncoding else {
            respondWithError(to: urlRequest)
            return
        }

        // Resolve against the coordinator's base directory
        guard let baseDir = coordinator?.currentBaseURL else {
            respondWithPlaceholder(to: urlRequest)
            return
        }

        // Fetch the image via the shared cache (avoids redundant decode — SR-3)
        Task(priority: .utility) { [weak self, weak urlRequest] in
            guard let self, let urlRequest else { return }

            let fileURL = baseDir.appendingPathComponent(relativePath)
            let cachedImage = await PreviewImageCache.shared.image(for: fileURL) {
                let resolver = PreviewImageResolver()
                let resolved = await resolver.resolve(reference: relativePath, relativeTo: baseDir)
                if case .image(let data, _, _) = resolved {
                    return NSImage(data: data)
                }
                return nil
            }

            await MainActor.run {
                if let cachedImage, let tiffData = cachedImage.tiffRepresentation {
                    self.respond(to: urlRequest, data: tiffData, mimeType: "image/tiff")
                } else {
                    // Serve a 1×1 transparent PNG placeholder
                    self.respondWithPlaceholder(to: urlRequest)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlRequest: URLRequest) {
        // No-op; task cancellation is handled by task scope cleanup
    }

    // MARK: - Response helpers

    /// Responds with the image data and MIME type.
    private func respond(to urlRequest: URLRequest, data: Data, mimeType: String) {
        guard let handler = urlRequest.mainDocumentURL else { return }

        let response = URLResponse(
            url: urlRequest.url ?? handler,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        URLProtocol.webView(WKWebView(), didReceive: response, for: urlRequest)
        URLProtocol.webView(WKWebView(), didLoad: data, for: urlRequest)
        URLProtocol.webViewDidFinishLoad(for: urlRequest)
    }

    /// Serves a 1×1 transparent PNG placeholder.
    private func respondWithPlaceholder(to urlRequest: URLRequest) {
        // 1×1 transparent PNG (base64)
        let pngBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        guard let data = Data(base64Encoded: pngBase64) else {
            respondWithError(to: urlRequest)
            return
        }
        respond(to: urlRequest, data: data, mimeType: "image/png")
    }

    /// Responds with an HTTP error.
    private func respondWithError(to urlRequest: URLRequest) {
        guard let url = urlRequest.url else { return }
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)
        URLProtocol.webView(WKWebView(), didFailWithError: error, for: urlRequest)
    }
}
