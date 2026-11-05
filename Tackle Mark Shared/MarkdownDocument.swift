import Foundation

enum MarkdownDocumentError: LocalizedError, Equatable {
    case notRegularFile
    case tooLarge(maximumByteCount: Int)
    case unsupportedEncoding

    var errorDescription: String? {
        switch self {
        case .notRegularFile:
            "Tackle Mark can only open regular Markdown files."
        case let .tooLarge(maximumByteCount):
            "This file is larger than the \(maximumByteCount / 1_000_000) MB preview limit."
        case .unsupportedEncoding:
            "This file is not valid UTF-8 Markdown."
        }
    }
}

/// The bounded file-loading boundary shared by the app and Quick Look extension.
struct MarkdownDocument: Sendable {
    static let maximumByteCount = 2_000_000

    let url: URL
    let source: String

    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw MarkdownDocumentError.notRegularFile }
        guard (values.fileSize ?? 0) <= Self.maximumByteCount else {
            throw MarkdownDocumentError.tooLarge(maximumByteCount: Self.maximumByteCount)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumByteCount + 1) ?? Data()
        guard data.count <= Self.maximumByteCount else {
            throw MarkdownDocumentError.tooLarge(maximumByteCount: Self.maximumByteCount)
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw MarkdownDocumentError.unsupportedEncoding
        }
        self.url = url
        self.source = source
    }
}
