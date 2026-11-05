import CoreGraphics
import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let html: String
        let title = request.fileURL.lastPathComponent

        do {
            let document = try MarkdownDocument(url: request.fileURL)
            html = MarkdownRenderer.render(document: document)
        } catch {
            html = MarkdownRenderer.errorPage(
                title: title,
                message: error.localizedDescription
            )
        }

        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 800, height: 600)
        ) { _ in
            Data(html.utf8)
        }

        reply.title = "Tackle Mark — \(title)"
        reply.stringEncoding = .utf8
        return reply
    }
}
