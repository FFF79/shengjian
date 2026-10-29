import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    case heading(Int, String)
    case paragraph(String)
    case quote(String)
    case callout(kind: String, title: String, body: String, collapsed: Bool)
    case listItem(String, String)
    case code(String)
    case table([String], [[String]])
    case rule
}

public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var result: [MarkdownBlock] = [], i = 0
        func trimmed(_ n: Int) -> String { lines[n].trimmingCharacters(in: .whitespaces) }
        while i < lines.count {
            let line = trimmed(i)
            if line.isEmpty { i += 1; continue }
            if line.hasPrefix("```") {
                i += 1; var code: [String] = []
                while i < lines.count, !trimmed(i).hasPrefix("```") { code.append(lines[i]); i += 1 }
                if i < lines.count { i += 1 }
                result.append(.code(code.joined(separator: "\n"))); continue
            }
            if i + 1 < lines.count, line.contains("|"), isTableDivider(trimmed(i + 1)) {
                let header = cells(line); var rows: [[String]] = []; i += 2
                while i < lines.count, !trimmed(i).isEmpty, trimmed(i).contains("|") {
                    var row = cells(trimmed(i)); row += Array(repeating: "", count: max(0, header.count - row.count))
                    rows.append(Array(row.prefix(header.count))); i += 1
                }
                result.append(.table(header, rows)); continue
            }
            if line.hasPrefix(">") {
                var quote: [String] = []
                while i < lines.count, trimmed(i).hasPrefix(">") {
                    quote.append(String(trimmed(i).dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                let first = quote.first ?? ""
                if first.hasPrefix("[!"), let close = first.firstIndex(of: "]") {
                    let kind = String(first[first.index(first.startIndex, offsetBy: 2)..<close])
                    var title = String(first[first.index(after: close)...])
                    let collapsed = title.hasPrefix("-")
                    if title.hasPrefix("-") || title.hasPrefix("+") { title.removeFirst() }
                    result.append(.callout(kind: kind, title: title.trimmingCharacters(in: .whitespaces), body: quote.dropFirst().joined(separator: "\n"), collapsed: collapsed))
                } else { result.append(.quote(quote.joined(separator: "\n"))) }
                continue
            }
            if line == "---" || line == "***" { result.append(.rule); i += 1; continue }
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") {
                result.append(.heading(hashes, String(line.dropFirst(hashes + 1)))); i += 1; continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { result.append(.listItem("•", String(line.dropFirst(2)))); i += 1; continue }
            if let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                result.append(.listItem(String(line[range]).trimmingCharacters(in: .whitespaces), String(line[range.upperBound...]))); i += 1; continue
            }
            // Keep paragraphs separate from surrounding structural blocks, including formulas and tables.
            var paragraph = [lines[i]]; i += 1
            while i < lines.count, !trimmed(i).isEmpty {
                let next = trimmed(i)
                if next.hasPrefix("#") || next.hasPrefix(">") || next.hasPrefix("```") || next.hasPrefix("- ") || next.hasPrefix("* ") || next == "---" || next.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil { break }
                if i + 1 < lines.count, next.contains("|"), isTableDivider(trimmed(i + 1)) { break }
                paragraph.append(lines[i]); i += 1
            }
            result.append(.paragraph(paragraph.joined(separator: "\n")))
        }
        return result
    }
    public static func cells(_ line: String) -> [String] {
        var line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") { line.removeLast() }
        var result: [String] = [], current = "", escaped = false, inlineCode = false
        for char in line {
            if escaped { current.append(char); escaped = false; continue }
            if char == "\\" { escaped = true; continue }
            if char == "`" { inlineCode.toggle() }
            if char == "|", !inlineCode { result.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
            else { current.append(char) }
        }
        if escaped { current.append("\\") }
        result.append(current.trimmingCharacters(in: .whitespaces)); return result
    }
    private static func isTableDivider(_ text: String) -> Bool {
        let values = cells(text)
        return !values.isEmpty && values.allSatisfy { $0.range(of: #"^:?-{2,}:?$"#, options: .regularExpression) != nil }
    }
}
