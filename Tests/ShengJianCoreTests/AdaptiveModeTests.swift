import XCTest
@testable import ShengJianCore

final class AdaptiveModeTests: XCTestCase {
    private func note(mode: NoteMode = .study) throws -> Recording {
        var note = Recording(); note.mode = mode; note.subject = mode == .study ? "物理" : "讨论"; note.title = "主题"
        note.segments = [.init(start: 0, end: 5, text: "先讨论实验的变量，再决定怎样分工。", id: "source")]
        note.transcriptComplete = true
        note.analysis = try JSONDecoder().decode(Analysis.self, from: Data(###"{"title":"主题","subject":"物理","confidence":0.9,"abstract":"讨论变量与分工","keyPoints":[],"concepts":[],"questions":[],"tags":["变量"],"organizedMarkdown":"## 共识\n\n先确认变量。","uncertainties":[],"context":"discussion","suggestedFolder":"讨论","learning":{"goals":["不应出现在其他模式的目标"],"aliases":[],"keyTerms":[],"sectionSources":[{"heading":"共识","evidenceSegmentIDs":["source"]}]}}"###.utf8))
        note.analyzedTranscriptHash = digest(note.transcript)
        return note
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    func testRawTranscriptShowsLearningAndAutomaticOtherLabel() throws {
        let root = try directory()
        var study = try note(); study.analysis = nil
        let raw = try String(contentsOf: RawTranscriptStore.save(study, root: root).manuscript)
        XCTAssertTrue(raw.contains("recording_label: \"学习\"")); XCTAssertTrue(raw.contains("note_mode: study"))
        let other = try note(mode: .other)
        let text = try String(contentsOf: RawTranscriptStore.save(other, root: root).manuscript)
        XCTAssertTrue(text.contains("recording_label: \"讨论\"")); XCTAssertTrue(text.contains("note_mode: other"))
    }
    func testOtherHarnessUsesSceneFolderAndRemovesLearningGoals() async throws {
        let root = try directory(), sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel(); StubProtocol.handler = nil }
        let note = try note(mode: .other), analysis = try JSONEncoder().encode(note.analysis!)
        StubProtocol.handler = { request in
            let bytes: Data
            if let body = request.httpBody { bytes = body }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }; bytes = data
            } else { throw AppError.message("Missing request body") }
            let body = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            let prompt = (body["messages"] as! [[String: String]])[0]["content"]!
            XCTAssertTrue(prompt.contains("个人录音记录的编辑")); XCTAssertTrue(prompt.contains("场景标签为归档首要依据"))
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": String(decoding: analysis, as: UTF8.self)]]]]))
        }
        let harness = DeepSeekHarness(configuration: .init(apiKey: "fixture", folders: ["讨论", "物理"]), session: session, cacheDirectory: root)
        let result = try await harness.run(recording: note) { _ in }
        XCTAssertEqual(result.mode, .other); XCTAssertEqual(result.subject, "讨论"); XCTAssertEqual(result.suggestedFolder, "讨论")
        XCTAssertTrue(result.tags.contains("讨论"))
        XCTAssertEqual(result.learning?.goals, []); XCTAssertFalse(result.documentBody.contains("本篇要掌握"))
    }
    func testOtherSceneDoesNotFileIntoLearningSubjectFolder() {
        XCTAssertFalse(RecordingContext.discussion.matches(folder: "课程/物理"))
        XCTAssertTrue(RecordingContext.discussion.matches(folder: "生活/交流记录"))
        XCTAssertTrue(RecordingContext.lecture.matches(folder: "讲座/科技"))
        XCTAssertFalse(RecordingContext.other.matches(folder: "其他"))
    }
    func testUnclassifiedReminderClearsAfterManualMoveAndManifestSurvivesCatalogLoss() async throws {
        let root = try directory(), raw = try directory(), writer = ArchiveWriter()
        var first = try await writer.export(note(mode: .other), root: root, subfolder: "", rawRoot: raw)
        XCTAssertEqual(first.needsClassification, true)
        XCTAssertTrue(first.exportNote!.hasPrefix("未分类/"))
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("_声笺/索引.md")).contains("待手动分类"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("讨论"), withIntermediateDirectories: true)
        first.folderEdited = true
        let moved = try await writer.export(first, root: root, subfolder: "讨论", rawRoot: raw)
        XCTAssertEqual(moved.needsClassification, false); XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(first.exportNote!).path))
        try Data().write(to: root.appendingPathComponent("_声笺/agent/catalog.jsonl"))
        var second = try note(); second.title = "另一篇"
        _ = try await writer.export(second, root: root, subfolder: "", rawRoot: raw)
        let rows = try String(contentsOf: root.appendingPathComponent("_声笺/agent/catalog.jsonl")).split(separator: "\n")
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("_声笺/agent/sections/\(moved.id).jsonl").path))
    }
    func testManualRootChoiceIsRespected() async throws {
        let root = try directory(), raw = try directory(); var note = try note(); note.folderEdited = true
        let exported = try await ArchiveWriter().export(note, root: root, subfolder: "", rawRoot: raw)
        XCTAssertEqual(exported.needsClassification, false); XCTAssertFalse(exported.exportNote!.contains("/"))
    }
    func testObsidianLinksCanUseVaultNameInsteadOfAbsolutePath() {
        let text = KnowledgeLinks.previewMarkdown("查看[[讨论/产品方向|产品方向]]。", vaultPath: nil, vaultName: "示例仓库")
        XCTAssertTrue(text.contains("obsidian://open?vault=")); XCTAssertTrue(text.contains("&file=")); XCTAssertFalse(text.contains("path="))
        XCTAssertTrue(text.contains("[产品方向]"))
    }
}
