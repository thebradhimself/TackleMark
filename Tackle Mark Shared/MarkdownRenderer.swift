import Foundation

/// Converts a safe, deliberately scoped Markdown subset into a complete HTML document.
///
/// The source is never emitted as raw HTML. This keeps the same renderer safe to use in
/// both the app and the out-of-process Quick Look extension.
enum MarkdownRenderer {
    static func render(document: MarkdownDocument) -> String {
        render(source: document.source, title: document.url.deletingPathExtension().lastPathComponent)
    }

    static func render(source: String, title: String = "Markdown") -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'">
        <title>\(escapeHTML(title))</title>
        <style>\(stylesheet)</style>
        </head>
        <body><main class="markdown-body">\(renderBlocks(source))</main></body>
        </html>
        """
    }

    static func errorPage(title: String, message: String) -> String {
        """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'">
        <title>\(escapeHTML(title))</title><style>\(stylesheet)</style></head>
        <body><main class="markdown-body"><h1>\(escapeHTML(title))</h1><p>\(escapeHTML(message))</p></main></body></html>
        """
    }

    private static func renderBlocks(_ source: String) -> String {
        let lines = source.components(separatedBy: .newlines)
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            } else if let fence = fenceStart(line) {
                let code = consumeFence(lines, from: index, marker: fence.marker)
                output.append("<pre><code\(fence.language.map { " class=\"language-\(escapeHTML($0))\"" } ?? "")>\(escapeHTML(code.content))</code></pre>")
                index = code.nextIndex
            } else if let heading = heading(line) {
                output.append("<h\(heading.level)>\(renderInline(heading.content))</h\(heading.level)>")
                index += 1
            } else if isHorizontalRule(line) {
                output.append("<hr>")
                index += 1
            } else if isTableSeparator(index + 1 < lines.count ? lines[index + 1] : ""), line.contains("|") {
                let table = consumeTable(lines, from: index)
                output.append(table.html)
                index = table.nextIndex
            } else if isQuote(line) {
                let quote = consumeQuote(lines, from: index)
                output.append("<blockquote><p>\(renderInline(quote.content))</p></blockquote>")
                index = quote.nextIndex
            } else if unorderedItem(line) != nil {
                let list = consumeList(lines, from: index, ordered: false)
                output.append(list.html)
                index = list.nextIndex
            } else if orderedItem(line) != nil {
                let list = consumeList(lines, from: index, ordered: true)
                output.append(list.html)
                index = list.nextIndex
            } else {
                let paragraph = consumeParagraph(lines, from: index)
                output.append("<p>\(paragraph.lines.map(renderInline).joined(separator: "<br>"))</p>")
                index = paragraph.nextIndex
            }
        }

        return output.isEmpty ? "<p class=\"empty\">This Markdown file is empty.</p>" : output.joined(separator: "\n")
    }

    private static func consumeParagraph(_ lines: [String], from start: Int) -> (lines: [String], nextIndex: Int) {
        var result: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  fenceStart(line) == nil,
                  heading(line) == nil,
                  !isHorizontalRule(line),
                  !isQuote(line),
                  unorderedItem(line) == nil,
                  orderedItem(line) == nil,
                  !(line.contains("|") && index + 1 < lines.count && isTableSeparator(lines[index + 1]))
            else { break }
            result.append(line)
            index += 1
        }
        return (result, index)
    }

    private static func consumeFence(_ lines: [String], from start: Int, marker: String) -> (content: String, nextIndex: Int) {
        var code: [String] = []
        var index = start + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                return (code.joined(separator: "\n"), index + 1)
            }
            code.append(lines[index])
            index += 1
        }
        return (code.joined(separator: "\n"), index)
    }

    private static func consumeQuote(_ lines: [String], from start: Int) -> (content: String, nextIndex: Int) {
        var quote: [String] = []
        var index = start
        while index < lines.count, isQuote(lines[index]) {
            let content = lines[index].trimmingCharacters(in: .whitespaces).dropFirst()
            quote.append(content.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return (quote.joined(separator: " "), index)
    }

    private static func consumeList(_ lines: [String], from start: Int, ordered: Bool) -> (html: String, nextIndex: Int) {
        var items: [String] = []
        var index = start
        while index < lines.count {
            let item = ordered ? orderedItem(lines[index]) : unorderedItem(lines[index])
            guard let item else { break }

            if !ordered && (item.hasPrefix("[ ] ") || item.hasPrefix("[x] ") || item.hasPrefix("[X] ")) {
                let checked = item.lowercased().hasPrefix("[x] ") ? " checked" : ""
                let content = String(item.dropFirst(4))
                items.append("<li class=\"task\"><input type=\"checkbox\" disabled\(checked)>\(renderInline(content))</li>")
            } else {
                items.append("<li>\(renderInline(item))</li>")
            }
            index += 1
        }
        let tag = ordered ? "ol" : "ul"
        return ("<\(tag)>\(items.joined())</\(tag)>", index)
    }

    private static func consumeTable(_ lines: [String], from start: Int) -> (html: String, nextIndex: Int) {
        let headerCells = tableCells(lines[start])
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            rows.append(tableCells(lines[index]))
            index += 1
        }
        let header = headerCells.map { "<th>\(renderInline($0))</th>" }.joined()
        let body = rows.map { row in "<tr>\(row.map { "<td>\(renderInline($0))</td>" }.joined())</tr>" }.joined()
        return ("<div class=\"table-wrap\"><table><thead><tr>\(header)</tr></thead><tbody>\(body)</tbody></table></div>", index)
    }

    private static func tableCells(_ line: String) -> [String] {
        var cells = line.trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells
    }

    private static func renderInline(_ text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix("!["), let image = bracketedLink(in: text, from: index, image: true) {
                // Image data and local-file attachment handling are intentionally deferred. Alt text
                // remains visible and untrusted URLs cannot trigger network access in a preview.
                output += "<span class=\"image-alt\">[image: \(renderInline(image.label))]</span>"
                index = image.nextIndex
            } else if text[index] == "[", let link = bracketedLink(in: text, from: index, image: false) {
                let label = renderInline(link.label)
                if let href = safeLinkURL(link.destination) {
                    output += "<a href=\"\(escapeHTML(href))\">\(label)</a>"
                } else {
                    output += label
                }
                index = link.nextIndex
            } else if text[index] == "`", let close = text[text.index(after: index)...].firstIndex(of: "`") {
                output += "<code>\(escapeHTML(String(text[text.index(after: index)..<close])))</code>"
                index = text.index(after: close)
            } else if text[index...].hasPrefix("**"), let close = text[text.index(index, offsetBy: 2)...].range(of: "**")?.lowerBound {
                let contentStart = text.index(index, offsetBy: 2)
                output += "<strong>\(renderInline(String(text[contentStart..<close])))</strong>"
                index = text.index(close, offsetBy: 2)
            } else if text[index...].hasPrefix("~~"), let close = text[text.index(index, offsetBy: 2)...].range(of: "~~")?.lowerBound {
                let contentStart = text.index(index, offsetBy: 2)
                output += "<del>\(renderInline(String(text[contentStart..<close])))</del>"
                index = text.index(close, offsetBy: 2)
            } else if text[index] == "*" || text[index] == "_", let close = text[text.index(after: index)...].firstIndex(of: text[index]) {
                output += "<em>\(renderInline(String(text[text.index(after: index)..<close])))</em>"
                index = text.index(after: close)
            } else {
                output += escapeHTML(String(text[index]))
                index = text.index(after: index)
            }
        }
        return output
    }

    private static func bracketedLink(in text: String, from start: String.Index, image: Bool) -> (label: String, destination: String, nextIndex: String.Index)? {
        let labelStart = image ? text.index(start, offsetBy: 2) : text.index(after: start)
        guard let closeBracket = text[labelStart...].firstIndex(of: "]") else { return nil }
        let openParen = text.index(after: closeBracket)
        guard openParen < text.endIndex, text[openParen] == "(", let closeParen = text[text.index(after: openParen)...].firstIndex(of: ")") else { return nil }
        return (
            String(text[labelStart..<closeBracket]),
            String(text[text.index(after: openParen)..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines),
            text.index(after: closeParen)
        )
    }

    private static func safeLinkURL(_ value: String) -> String? {
        guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else {
            return nil
        }
        return value
    }

    private static func fenceStart(_ line: String) -> (marker: String, language: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let marker: String
        if trimmed.hasPrefix("```") { marker = "```" }
        else if trimmed.hasPrefix("~~~") { marker = "~~~" }
        else { return nil }
        let language = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func heading(_ line: String) -> (level: Int, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6, trimmed.dropFirst(hashes.count).first == " " else { return nil }
        return (hashes.count, String(trimmed.dropFirst(hashes.count)).trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.filter { !$0.isWhitespace }
        guard stripped.count >= 3, let first = stripped.first, ["-", "*", "_"].contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let core = cell.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
            return core.isEmpty && cell.filter { $0 == "-" }.count >= 3
        }
    }

    private static func isQuote(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private static func unorderedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: "."), dot > trimmed.startIndex,
              trimmed[..<dot].allSatisfy({ $0.isNumber }), trimmed.index(after: dot) < trimmed.endIndex,
              trimmed[trimmed.index(after: dot)] == " " else { return nil }
        return String(trimmed[trimmed.index(dot, offsetBy: 2)...])
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let stylesheet = """
    :root { color-scheme: light dark; }
    body { margin: 0; overflow-x: hidden; color: light-dark(#1f2328, #f0f6fc); background: light-dark(#fff, #0d1117); font: -apple-system-body; line-height: 1.55; }
    .markdown-body { box-sizing: border-box; width: 100%; max-width: none; margin: 0; padding: 28px; overflow-wrap: anywhere; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.4em 0 .65em; }
    h1 { font-size: 2em; border-bottom: 1px solid light-dark(#d1d9e0, #30363d); padding-bottom: .3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid light-dark(#d1d9e0, #30363d); padding-bottom: .25em; }
    p, ul, ol, blockquote, pre, .table-wrap { margin: 0 0 1em; }
    ul, ol { padding-left: 2em; } li + li { margin-top: .25em; }
    a { color: light-dark(#0969da, #58a6ff); } code { font: .88em ui-monospace, SFMono-Regular, Menlo, monospace; background: light-dark(#eff1f3, #161b22); padding: .15em .3em; border-radius: 4px; }
    pre { box-sizing: border-box; max-width: 100%; background: light-dark(#f6f8fa, #161b22); padding: 1em; border-radius: 7px; overflow-x: auto; } pre code { padding: 0; background: transparent; }
    blockquote { margin-left: 0; padding: .1em 1em; color: light-dark(#59636e, #8b949e); border-left: .25em solid light-dark(#d1d9e0, #30363d); }
    table { border-spacing: 0; border-collapse: collapse; width: 100%; table-layout: auto; } th, td { padding: .45em .7em; border: 1px solid light-dark(#d1d9e0, #30363d); text-align: left; vertical-align: top; overflow-wrap: anywhere; } th { background: light-dark(#f6f8fa, #161b22); }
    .table-wrap { width: 100%; max-width: 100%; min-width: 0; overflow-x: auto; } .task { list-style: none; margin-left: -1.5em; } .task input { margin-right: .45em; } .image-alt, .empty { color: light-dark(#59636e, #8b949e); }
    """
}
