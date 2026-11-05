import Foundation
import XCTest

final class MarkdownRendererTests: XCTestCase {
    func testRendersCoreMarkdown() {
        let html = MarkdownRenderer.render(source: """
        # Welcome

        - [x] Shipped
        - [ ] Review

        | Name | Value |
        | --- | --- |
        | Tackle | Mark |

        ```swift
        let preview = true
        ```
        """)

        XCTAssertTrue(html.contains("<h1>Welcome</h1>"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked>Shipped"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<td>Mark</td>"))
        XCTAssertTrue(html.contains("<code class=\"language-swift\">let preview = true</code>"))
    }

    func testEscapesUnsafeContentAndRejectsUnsafeURLs() {
        let html = MarkdownRenderer.render(source: """
        <script>alert('no')</script>
        [unsafe](javascript:alert(1))
        [safe](https://example.com/docs)
        ![remote image](https://example.com/pixel.png)
        """)

        XCTAssertTrue(html.contains("&lt;script&gt;alert(&#39;no&#39;)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("href=\"javascript:"))
        XCTAssertTrue(html.contains("href=\"https://example.com/docs\""))
        XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("default-src 'none'"))

        let schemeHTML = MarkdownRenderer.render(source: "[mail](mailto:person@example.com) [file](file:///etc/passwd) [data](data:text/plain,hello)")
        XCTAssertTrue(schemeHTML.contains("href=\"mailto:person@example.com\""))
        XCTAssertFalse(schemeHTML.contains("href=\"file:"))
        XCTAssertFalse(schemeHTML.contains("href=\"data:"))
    }

    func testUsesAvailableReaderWidthAndWrapsTableCells() {
        let html = MarkdownRenderer.render(source: """
        | Task | Done when |
        | --- | --- |
        | A very long task | A very long completion condition |
        """)

        XCTAssertTrue(html.contains("width: 100%; max-width: none"))
        XCTAssertTrue(html.contains("table-layout: auto"))
        XCTAssertTrue(html.contains("overflow-wrap: anywhere"))
    }

    func testRejectsOversizedFiles() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data(repeating: 0x61, count: MarkdownDocument.maximumByteCount + 1).write(to: fileURL)

        XCTAssertThrowsError(try MarkdownDocument(url: fileURL)) { error in
            XCTAssertEqual(error as? MarkdownDocumentError, .tooLarge(maximumByteCount: MarkdownDocument.maximumByteCount))
        }
    }

    func testRejectsNonUTF8Markdown() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data([0xFF, 0xFE]).write(to: fileURL)

        XCTAssertThrowsError(try MarkdownDocument(url: fileURL)) { error in
            XCTAssertEqual(error as? MarkdownDocumentError, .unsupportedEncoding)
        }
    }
}
