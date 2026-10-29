import Foundation

public struct LearningSupport: Codable, Equatable, Sendable {
    public struct SectionSource: Codable, Equatable, Sendable {
        public var heading: String
        public var evidenceSegmentIDs: [String]
    }
    public var goals: [String]
    public var aliases: [String]
    public var keyTerms: [String]?
    public var relatedNotePaths: [String]?
    public var unresolvedLinks: [String]?
    public var sectionSources: [SectionSource]

    public func grounded(in segmentIDs: Set<String>) -> LearningSupport {
        var result = self
        // Model-created references never become trusted source IDs.
        result.sectionSources = sectionSources.compactMap { source in
            var source = source
            source.evidenceSegmentIDs = source.evidenceSegmentIDs.filter { segmentIDs.contains($0) }
            return source.evidenceSegmentIDs.isEmpty ? nil : source
        }
        result.goals = Array(goals.filter { !$0.isEmpty }.prefix(5))
        result.aliases = Array(Set(aliases.filter { !$0.isEmpty })).sorted()
        return result
    }
}

public struct NoteSection: Codable, Equatable, Sendable {
    public var id: String
    public var heading: String
    public var text: String
}

public enum NoteSections {
    public static func parse(_ markdown: String, recordingID: String) -> [NoteSection] {
        var result: [NoteSection] = []
        var heading = "概览", content: [String] = []
        var fenced = false
        func flush() {
            let text = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(NoteSection(id: recordingID + "-" + String(digest(heading + "-\(result.count)").prefix(12)), heading: heading, text: text)) }
        }
        for line in markdown.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle() }
            if !fenced, line.hasPrefix("## ") { flush(); content = []; heading = String(line.dropFirst(3)) }
            else { content.append(line) }
        }
        flush()
        return result
    }
}
