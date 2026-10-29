import Foundation
import CryptoKit

public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var start: Double
    public var end: Double
    public var text: String
    public init(start: Double, end: Double, text: String, id: String = UUID().uuidString) {
        self.id = id; self.start = start; self.end = end; self.text = text
    }
}

public struct Analysis: Codable, Equatable, Sendable {
    public struct Concept: Codable, Equatable, Sendable {
        public var term: String
        public var explanation: String
    }
    public var title: String
    public var subject: String
    public var confidence: Double
    public var abstract: String
    public var keyPoints: [String]
    public var concepts: [Concept]
    public var questions: [String]
    public var tags: [String]
    public var organizedMarkdown: String
    public var uncertainties: [String]
    public var suggestedFolder: String?
    public var noteFormatVersion: Int?
    public var learning: LearningSupport?
    public var mode: NoteMode?
    public var context: String?

    public var documentBody: String {
        var sections: [String] = []
        if mode != .other, let goals = learning?.goals, !goals.isEmpty {
            sections.append("> [!abstract] 本篇要掌握\n" + goals.map { "> - " + $0.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n"))
        }
        sections.append(organizedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines))
        if !uncertainties.isEmpty {
            sections.append("> [!warning] 原稿待核对\n" + uncertainties.map { "> - " + $0.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    public func validated() throws -> Analysis {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !abstract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              confidence.isFinite, (0...1).contains(confidence),
              title.count <= 150, subject.count <= 50,
              !organizedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw AppError.message("DeepSeek 的结果缺少必要字段或分类置信度无效，请重试。") }
        var value = self
        if confidence < 0.65 { value.subject = "待分类" }
        value.tags = Array(Set(tags.map { safeComponent($0).replacingOccurrences(of: " ", with: "-") }.filter { !$0.isEmpty })).sorted()
        return value
    }
}

public struct Recording: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var createdAt = Date()
    public var title = "新的录音"
    public var subject = "待分类"
    public var mode: NoteMode?
    public var needsClassification: Bool?
    public var resolvedMode: NoteMode { mode ?? .study }
    public var recordingLabel: String {
        resolvedMode == .study ? "学习" : analysis?.context.flatMap(RecordingContext.init(rawValue:))?.title ?? "待识别"
    }
    public var classificationDisplay: String {
        resolvedMode == .study ? "学习 · " + (subject == "待分类" ? "科目待识别" : subject) : "其他 · " + (recordingLabel == "待识别" ? "场景待识别" : recordingLabel)
    }
    public var archivedFolderDisplay: String? {
        guard let exportRoot, let exportNote else { return nil }
        let name = URL(fileURLWithPath: exportRoot).lastPathComponent
        let parent = (exportNote as NSString).deletingLastPathComponent
        return parent.isEmpty ? name : name + "/" + parent
    }
    public var titleEdited = false
    public var subjectEdited = false
    public var customRoot: String?
    public var destinationFolder: String?
    public var folderEdited: Bool? = false
    public var rawDirectory: String?
    public var needsArchiveUpdate: Bool? = false
    public var duration: Double = 0
    public var segments: [TranscriptSegment] = []
    public var analysis: Analysis?
    public var state = "draft"
    public var transcriberModel = "small"
    public var transcriberEngine: String?
    public var sourceDevice: String?
    public var isDemo: Bool?
    public var analysisModel: String?
    public var analyzedTranscriptHash: String?
    public var failedRanges: [String] = []
    public var exportRoot: String?
    public var exportNote: String?
    public var exportHash: String?
    public var transcriptComplete = false
    public init() {}
    public var transcript: String { segments.map { "[\(timestamp($0.start))] \($0.text)" }.joined(separator: "\n") }
    public var hasSpeech: Bool { !segments.isEmpty }
    public var summaryIsStale: Bool { analysis != nil && analyzedTranscriptHash != digest(transcript) }
}

public enum AppError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

public func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
public func timestamp(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    return value >= 3600 ? String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
}
public func safeComponent(_ value: String) -> String {
    let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|[]#^\n\r\t").union(.controlCharacters)
    let text = value.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: " ")
        .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    return String(text.prefix(100))
}

public enum LocalClassifier {
    public static let subjects = ["数学", "物理", "化学", "生物", "计算机科学", "经济学", "历史", "语言学习", "哲学", "心理学", "医学", "待分类"]
    public static func classify(_ text: String) -> String {
        let text = text.lowercased()
        let words: [(String, [String])] = [
            ("数学", ["导数", "积分", "矩阵", "微分", "方程", "derivative", "integral", "calculus", "eigenvalue"]),
            ("物理", ["动量", "电磁", "牛顿", "量子", "力学", "momentum", "quantum", "newton", "velocity"]),
            ("化学", ["化学", "化合物", "氧化", "化学键", "催化", "molecule", "chemical", "covalent"]),
            ("生物", ["细胞", "基因", "蛋白质", "光合作用", "cellular", "genome", "photosynthesis"]),
            ("计算机科学", ["算法", "编程", "神经网络", "数据结构", "程序", "algorithm", "python", "neural network", "gradient descent"]),
            ("经济学", ["经济", "通货膨胀", "供需", "边际", "elasticity", "inflation", "economics"]),
            ("历史", ["朝代", "历史", "殖民", "帝国", "dynasty", "empire", "historical"]),
            ("语言学习", ["语法", "词汇", "雅思", "托福", "grammar", "vocabulary", "ielts", "toefl"]),
            ("哲学", ["哲学", "认识论", "本体论", "形而上", "epistemology", "ontology", "philosophy"]),
            ("心理学", ["心理学", "认知偏差", "心理治疗", "psychology", "cognitive bias"]),
            ("医学", ["临床", "诊断", "病理", "药理", "diagnosis", "clinical", "pathology"])
        ]
        let scores = words.map { subject, terms in (subject, terms.filter { text.contains($0) }.count) }.sorted { $0.1 > $1.1 }
        guard let first = scores.first, first.1 >= 2, scores.count < 2 || first.1 > scores[1].1 else { return "待分类" }
        return first.0
    }
}

public enum SessionFiles {
    public static var base: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("声笺", isDirectory: true) }
    public static func directory(_ id: String) -> URL { base.appendingPathComponent("Sessions/\(id)", isDirectory: true) }
    public static func save(_ recording: Recording) throws {
        let folder = directory(recording.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recording).write(to: folder.appendingPathComponent("session.json"), options: .atomic)
    }
    public static func load() -> [Recording] {
        let folder = base.appendingPathComponent("Sessions")
        guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return children.compactMap { try? decoder.decode(Recording.self, from: Data(contentsOf: $0.appendingPathComponent("session.json"))) }.sorted { $0.createdAt > $1.createdAt }
    }
}
