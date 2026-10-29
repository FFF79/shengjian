import Foundation

public struct KnowledgeNoteReference: Codable, Equatable, Sendable {
    public var path: String
    public var title: String
    public var aliases: [String]
    public init(path: String, title: String, aliases: [String] = []) { self.path = path; self.title = title; self.aliases = aliases }
}

public enum KnowledgeNoteIndex {
    public static func candidates(root: URL, transcript: String, excluding: String? = nil) throws -> [KnowledgeNoteReference] {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, error in traversalError = error; return false }) else { return [] }
        var ranked: [(KnowledgeNoteReference, Int)] = [], count = 0
        let source = transcript.lowercased()
        for case let file as URL in enumerator {
            if file.lastPathComponent == "_声笺" { enumerator.skipDescendants(); continue }
            let info = try file.resourceValues(forKeys: Set(keys))
            if info.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard file.pathExtension.lowercased() == "md", info.isDirectory != true else { continue }
            count += 1; if count > 5000 { break }
            let canonical = file.standardizedFileURL.resolvingSymlinksInPath()
            guard canonical.path.hasPrefix(root.path + "/") else { continue }
            let path = canonical.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            guard path != excluding, path.rangeOfCharacter(from: CharacterSet(charactersIn: "#|^[]\n\r")) == nil else { continue }
            var title = file.deletingPathExtension().lastPathComponent, aliases: [String] = []
            // Do not trigger downloads for every note in a large iCloud vault. Read only a local frontmatter prefix.
            if info.isUbiquitousItem != true || info.ubiquitousItemDownloadingStatus == .current,
               let handle = try? FileHandle(forReadingFrom: file) {
                let data = try? handle.read(upToCount: 8192); try? handle.close()
                if let data, let prefix = String(data: data, encoding: .utf8), prefix.hasPrefix("---") {
                    var readingAliases = false
                    for line in prefix.components(separatedBy: .newlines).dropFirst() {
                        if line.trimmingCharacters(in: .whitespaces) == "---" { break }
                        if line.hasPrefix("title:") { title = scalar(String(line.dropFirst(6))) }
                        if line.hasPrefix("aliases:") {
                            readingAliases = true
                            let value = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                            if let array = try? JSONDecoder().decode([String].self, from: Data(value.utf8)) { aliases += array }
                            else if value.hasPrefix("["), value.hasSuffix("]") { aliases += value.dropFirst().dropLast().split(separator: ",").map { scalar(String($0)) } }
                            else if !value.isEmpty { aliases.append(scalar(value)) }
                        } else if readingAliases, line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") { aliases.append(scalar(String(line.trimmingCharacters(in: .whitespaces).dropFirst(2)))) }
                        else if !line.isEmpty { readingAliases = false }
                    }
                }
            }
            let labels = [title] + aliases
            var score = 0
            for label in labels where label.count >= 2 {
                if source.contains(label.lowercased()) { score += 20 + min(20, label.count) }
                else {
                    let chars = Array(label.lowercased())
                    if chars.count > 2 { score += (0..<(chars.count - 1)).filter { source.contains(String(chars[$0...($0 + 1)])) }.count }
                }
            }
            if score >= 2 { ranked.append((KnowledgeNoteReference(path: path, title: title, aliases: aliases), score)) }
        }
        if let traversalError { throw traversalError }
        return ranked.sorted { $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1 }.prefix(64).map(\.0)
    }
    private static func scalar(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) { return decoded }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}

public enum KnowledgeLinks {
    public static func apply(to markdown: String, terms: [String], notes: [KnowledgeNoteReference]) -> String {
        let knownPaths = Set(notes.map { $0.path.hasSuffix(".md") ? String($0.path.dropLast(3)) : $0.path })
        let allowedTerms = Set(terms)
        let wiki = try! NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        var markdown = markdown
        for match in wiki.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)).reversed() {
            guard let range = Range(match.range, in: markdown), let content = Range(match.range(at: 1), in: markdown) else { continue }
            let pieces = markdown[content].replacingOccurrences(of: "\\|", with: "|").split(separator: "|", maxSplits: 1).map(String.init)
            let target = pieces.first ?? ""
            let normalized = target.hasSuffix(".md") ? String(target.dropLast(3)) : target
            if !knownPaths.contains(normalized) && !allowedTerms.contains(target) { markdown.replaceSubrange(range, with: pieces.last ?? target) }
        }
        var targets: [String: String] = [:]
        for term in terms where (2...60).contains(term.count) && term.rangeOfCharacter(from: CharacterSet(charactersIn: "[]|#^\n\r")) == nil { targets[term] = term }
        for note in notes {
            for label in [note.title] + note.aliases where (2...100).contains(label.count) && label.rangeOfCharacter(from: CharacterSet(charactersIn: "[]|#^\n\r")) == nil { targets[label] = String(note.path.dropLast(note.path.hasSuffix(".md") ? 3 : 0)) }
        }
        let sorted = targets.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        var linked: Set<String> = [], fenced = false
        let protected = try! NSRegularExpression(pattern: #"\[\[[^\]]+\]\]|`[^`]*`|\[[^\]]*\]\([^)]*\)|https?://\S+"#)
        return markdown.components(separatedBy: .newlines).map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); return line }
            if fenced || line.hasPrefix("#") { return line }
            let matches = protected.matches(in: line, range: NSRange(line.startIndex..., in: line))
            var pieces: [(String, Bool)] = [], cursor = line.startIndex
            for match in matches {
                guard let range = Range(match.range, in: line) else { continue }
                pieces.append((String(line[cursor..<range.lowerBound]), false)); pieces.append((String(line[range]), true)); cursor = range.upperBound
            }
            pieces.append((String(line[cursor...]), false))
            let table = line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
            return pieces.map { text, skip -> String in
                guard !skip else { return text }
                var result = "", start = text.startIndex
                while start < text.endIndex {
                    if linked.count < 20, let term = sorted.first(where: { !linked.contains($0) && Self.matches($0, in: text, at: start) }) {
                        let target = targets[term]!
                        let separator = table ? "\\|" : "|"
                        result += target == term ? "[[\(term)]]" : "[[\(target)\(separator)\(term)]]"
                        linked.insert(term); start = text.index(start, offsetBy: term.count)
                    } else { result.append(text[start]); start = text.index(after: start) }
                }
                return result
            }.joined()
        }.joined(separator: "\n")
    }
    private static func matches(_ term: String, in text: String, at start: String.Index) -> Bool {
        let candidate = String(text[start...].prefix(term.count))
        guard candidate.caseInsensitiveCompare(term) == .orderedSame else { return false }
        let english = term.unicodeScalars.allSatisfy { $0.isASCII }
        if english {
            if start > text.startIndex { let previous = text[text.index(before: start)]; if previous.isLetter || previous.isNumber { return false } }
            let end = text.index(start, offsetBy: candidate.count)
            if end < text.endIndex, text[end].isLetter || text[end].isNumber { return false }
        }
        return true
    }
    public static func targets(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return text[range].replacingOccurrences(of: "\\|", with: "|").split(separator: "|", maxSplits: 1).first.map(String.init)
        }
    }
    public static func previewMarkdown(_ markdown: String, vaultPath: String?, vaultName: String? = nil) -> String {
        guard vaultPath != nil || vaultName != nil else { return markdown }
        let regex = try! NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        var result = markdown
        for match in regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)).reversed() {
            guard let contentRange = Range(match.range(at: 1), in: markdown), let fullRange = Range(match.range, in: result) else { continue }
            let parts = markdown[contentRange].replacingOccurrences(of: "\\|", with: "|").split(separator: "|", maxSplits: 1).map(String.init)
            guard let target = parts.first, !target.hasPrefix("/"), !target.split(separator: "/").contains("..") else { continue }
            var components = URLComponents(); components.scheme = "obsidian"; components.host = "open"
            if let vaultName {
                components.percentEncodedQuery = "vault=" + (vaultName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") + "&file=" + (target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
            } else if let vaultPath {
                let path = URL(fileURLWithPath: vaultPath).appendingPathComponent(target.hasSuffix(".md") ? target : target + ".md").path
                components.percentEncodedQuery = "path=" + (path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
            }
            if let url = components.url { result.replaceSubrange(fullRange, with: "[\(parts.last ?? target)](\(url.absoluteString))") }
        }
        return result
    }
}
