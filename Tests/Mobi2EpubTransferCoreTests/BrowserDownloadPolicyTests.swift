import Foundation
import Testing
@testable import Mobi2EpubTransferCore

struct BrowserDownloadPolicyTests {
    @Test
    func downloadsMainFramePDFByMIMETypeEvenWithoutFileExtension() {
        let response = info(
            url: "https://example.test/download/temporary-token",
            mimeType: "application/pdf",
            suggestedFilename: "One Piece.pdf"
        )

        #expect(BrowserDownloadPolicy.shouldDownload(response, automaticallyDownloadsPDFs: true))
    }

    @Test
    func previewPreferenceAllowsInlinePDFs() {
        let response = info(url: "https://example.test/book.pdf", mimeType: "application/pdf")

        #expect(!BrowserDownloadPolicy.shouldDownload(response, automaticallyDownloadsPDFs: false))
    }

    @Test
    func doesNotInterceptPDFInAnEmbeddedFrame() {
        let response = info(
            url: "https://example.test/book.pdf",
            mimeType: "application/pdf",
            isForMainFrame: false
        )

        #expect(!BrowserDownloadPolicy.shouldDownload(response, automaticallyDownloadsPDFs: true))
    }

    @Test
    func respectsAttachmentDispositionEvenForPreviewPreference() {
        let response = info(
            url: "https://example.test/download",
            mimeType: "application/pdf",
            contentDisposition: "attachment; filename=book.pdf"
        )

        #expect(BrowserDownloadPolicy.shouldDownload(response, automaticallyDownloadsPDFs: false))
    }

    @Test
    func downloadsKnownBookResponsesAndUnsupportedMIMETypes() {
        let epub = info(url: "https://example.test/book", mimeType: "application/epub+zip")
        let unsupported = info(
            url: "https://example.test/download",
            mimeType: "application/octet-stream",
            canShowMIMEType: false
        )

        #expect(BrowserDownloadPolicy.shouldDownload(epub, automaticallyDownloadsPDFs: true))
        #expect(BrowserDownloadPolicy.shouldDownload(unsupported, automaticallyDownloadsPDFs: true))
    }

    @Test
    func allowsOrdinaryHTMLNavigation() {
        let response = info(url: "https://example.test/library", mimeType: "text/html")

        #expect(!BrowserDownloadPolicy.shouldDownload(response, automaticallyDownloadsPDFs: true))
    }

    private func info(
        url: String,
        mimeType: String,
        suggestedFilename: String? = nil,
        contentDisposition: String? = nil,
        isForMainFrame: Bool = true,
        canShowMIMEType: Bool = true
    ) -> BrowserNavigationResponseInfo {
        BrowserNavigationResponseInfo(
            url: URL(string: url),
            mimeType: mimeType,
            suggestedFilename: suggestedFilename,
            contentDisposition: contentDisposition,
            isForMainFrame: isForMainFrame,
            canShowMIMEType: canShowMIMEType
        )
    }
}
