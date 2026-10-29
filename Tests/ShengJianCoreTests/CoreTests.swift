import XCTest
@testable import ShengJianCore

final class CoreTests: XCTestCase {
    var rawRoot: URL!
    override func setUpWithError() throws { rawRoot = try folder() }
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shengjian-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func vault() throws -> URL {
        let root = try folder()
        for path in ["课程/物理", "课程/数学"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        return root
    }
    func recording() throws -> Recording {
        var note = Recording(); note.title = "牛顿第二定律与 acceleration"; note.subject = "物理"; note.duration = 18
        note.segments = [.init(start: 0, end: 8, text: "raw-only-phrase：force equals mass times acceleration。"), .init(start: 8, end: 18, text: "注意受力分析中的矢量方向。")]
        note.transcriptComplete = true
        let json = #"{"title":"牛顿第二定律","subject":"物理","confidence":0.95,"abstract":"研究力与加速度的关系。","keyPoints":["受力分析"],"concepts":[],"questions":[],"tags":["力学"],"organizedMarkdown":"[00:00] 牛顿第二定律描述力和加速度的关系。","uncertainties":[],"suggestedFolder":"课程/物理"}"#
        note.analysis = try JSONDecoder().decode(Analysis.self, from: Data(json.utf8))
        note.analyzedTranscriptHash = digest(note.transcript); return note
    }
    func catalog(_ root: URL) throws -> [CatalogEntry] {
        try String(contentsOf: root.appendingPathComponent("_声笺/agent/catalog.jsonl"), encoding: .utf8).split(separator: "\n").map { try JSONDecoder().decode(CatalogEntry.self, from: Data($0.utf8)) }
    }
    func testOnlyFinishedWorkAndCompactIndexesEnterObsidian() async throws {
        let root = try vault(); let writer = ArchiveWriter()
        let item = try await writer.export(recording(), root: root, subfolder: "课程/物理", rawRoot: rawRoot)
        XCTAssertTrue(item.exportNote!.hasPrefix("课程/物理/")); XCTAssertTrue(item.exportNote!.contains("｜物理｜牛顿第二定律与 acceleration.md"))
        let entry = try XCTUnwrap(catalog(root).first)
        XCTAssertTrue(entry.rawPath.hasPrefix(rawRoot.path)); XCTAssertTrue(entry.chunksPath.hasPrefix(rawRoot.path))
        let raw = try String(contentsOfFile: entry.rawPath, encoding: .utf8)
        XCTAssertTrue(raw.contains("raw-only-phrase")); XCTAssertTrue(raw.contains("^seg-"))
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!.allObjects as! [URL]
        for file in files where file.pathExtension == "md" || file.pathExtension == "jsonl" {
            XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("raw-only-phrase"), "Raw transcript leaked into vault")
        }
        XCTAssertFalse(files.contains { ["wav", "caf", "mp3", "m4a"].contains($0.pathExtension) })
    }
    func testRenameAndFolderChangeUpdateIndexesWithoutDuplicatingOriginal() async throws {
        let root = try vault(); let writer = ArchiveWriter()
        let first = try await writer.export(recording(), root: root, subfolder: "课程/物理", rawRoot: rawRoot)
        var edited = first; edited.title = "矩阵与线性变换"; edited.subject = "数学"
        let second = try await writer.export(edited, root: root, subfolder: "课程/数学", rawRoot: rawRoot)
        XCTAssertEqual(first.id, second.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(first.exportNote!).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(second.exportNote!).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("_声笺/学科索引/物理.md").path))
        XCTAssertEqual(try catalog(root).count, 1); XCTAssertEqual(try catalog(root).first?.subject, "数学")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: rawRoot, includingPropertiesForKeys: nil).filter { $0.pathExtension == "md" }.count, 1)
    }
    func testMissingSubjectFolderIsNeverCreatedAutomatically() async throws {
        let root = try vault(); let writer = ArchiveWriter()
        let missing = try await writer.export(recording(), root: root, subfolder: "新学科", rawRoot: rawRoot)
        XCTAssertEqual(missing.destinationFolder, "未分类")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("新学科").path))
        let fallback = try await writer.export(recording(), root: root, subfolder: "", rawRoot: rawRoot)
        XCTAssertTrue(fallback.exportNote!.hasPrefix("未分类/")); XCTAssertEqual(fallback.needsClassification, true)
    }
    func testRawManuscriptCanBeSavedBeforeAnyAnalysis() async throws {
        let root = try vault(); var note = try recording(); note.analysis = nil; note.transcriptComplete = false
        let reference = try RawTranscriptStore.save(note, root: rawRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reference.manuscript.path))
        do { _ = try await ArchiveWriter().export(note, root: root, subfolder: "", rawRoot: rawRoot); XCTFail("Unprocessed text entered Obsidian") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("_声笺").path))
    }
    func testMovingVaultPreservesIndependentRawAndUpdatesBothCatalogs() async throws {
        let rootA = try vault(); let rootB = try vault(); let writer = ArchiveWriter()
        let first = try await writer.export(recording(), root: rootA, subfolder: "课程/物理", rawRoot: rawRoot)
        let original = try XCTUnwrap(catalog(rootA).first?.rawPath)
        _ = try await writer.export(first, root: rootB, subfolder: "课程/物理", rawRoot: rawRoot)
        XCTAssertTrue(try catalog(rootA).isEmpty); XCTAssertEqual(try catalog(rootB).first?.rawPath, original)
    }
    func testTraversalSymlinkAndRawFolderInsideVaultAreRejected() async throws {
        let root = try vault(); let outside = try folder(); let writer = ArchiveWriter()
        for bad in ["../escape", "/tmp/escape", ".obsidian", "foo/../../escape", "foo//bar"] {
            do { _ = try await writer.export(recording(), root: root, subfolder: bad, rawRoot: rawRoot); XCTFail("Accepted \(bad)") } catch {}
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        do { _ = try await writer.export(recording(), root: root, subfolder: "link", rawRoot: rawRoot); XCTFail("Escaped") } catch {}
        do { _ = try await writer.export(recording(), root: root, subfolder: "课程/物理", rawRoot: root.appendingPathComponent("原稿")); XCTFail("Raw inside vault") } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }
    func testExternalEditsAndMalformedIndexArePreserved() async throws {
        let root = try vault(); let writer = ArchiveWriter()
        let first = try await writer.export(recording(), root: root, subfolder: "课程/物理", rawRoot: rawRoot)
        let file = root.appendingPathComponent(first.exportNote!); try Data("my edits".utf8).write(to: file)
        do { _ = try await writer.export(first, root: root, subfolder: "课程/物理", rawRoot: rawRoot); XCTFail("Overwrote external edit") } catch {}
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "my edits")
        let index = root.appendingPathComponent("_声笺/agent/catalog.jsonl"); try Data("preserve broken index".utf8).write(to: index)
        do { _ = try await writer.export(recording(), root: root, subfolder: "课程/物理", rawRoot: rawRoot); XCTFail("Overwrote broken index") } catch {}
        XCTAssertEqual(try String(contentsOf: index, encoding: .utf8), "preserve broken index")
    }
    func testDirectoryDiscoveryOnlyOffersExistingVisibleFolders() throws {
        let root = try vault(); let outside = try folder()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("_声笺/agent"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("symlink"), withDestinationURL: outside)
        XCTAssertEqual(try VaultFolders.list(at: root), ["课程", "课程/数学", "课程/物理"])
    }
    func testParallelRoundsHaveSeparateOriginalsAndCatalogEntries() async throws {
        let root = try vault(); let writer = ArchiveWriter()
        let first = try recording(); var second = try recording(); second.title = "第二轮主题"; second.subject = "数学"
        second.segments = [.init(start: 0, end: 2, text: "second-round-only")]; second.analyzedTranscriptHash = digest(second.transcript)
        let saved = try await withThrowingTaskGroup(of: Recording.self) { group in
            group.addTask { try await writer.export(first, root: root, subfolder: "课程/物理", rawRoot: self.rawRoot) }
            group.addTask { try await writer.export(second, root: root, subfolder: "课程/数学", rawRoot: self.rawRoot) }
            var values: [Recording] = []; for try await value in group { values.append(value) }; return values
        }
        XCTAssertEqual(saved.count, 2); XCTAssertEqual(try catalog(root).count, 2)
        let paths = try catalog(root).map(\.rawPath); XCTAssertEqual(Set(paths).count, 2)
        let a = try String(contentsOfFile: paths[0], encoding: .utf8), b = try String(contentsOfFile: paths[1], encoding: .utf8)
        XCTAssertNotEqual(a.contains("second-round-only"), b.contains("second-round-only"))
    }
    func testConservativeClassificationAndUnicodeChunking() {
        XCTAssertEqual(LocalClassifier.classify("我们今天聊聊天。"), "待分类")
        XCTAssertEqual(LocalClassifier.classify("牛顿与 momentum，动量守恒。"), "物理")
        let text = String(repeating: "中英🙂calculus", count: 5000)
        let parts = DeepSeekHarness.split(text, limit: 14000)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 14000 }); XCTAssertEqual(parts.joined(), text)
    }
}

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class HarnessTests: XCTestCase {
    private let valid = #"""
    {"title":"微积分的变化率","subject":"数学","confidence":0.95,"abstract":"导数描述变化率。","keyPoints":["导数"],"concepts":[],"questions":[],"tags":["微积分"],"organizedMarkdown":"## 导数\n\n导数 derivative 描述变化率。","uncertainties":[],"learning":{"goals":[],"aliases":[],"reviewQuestions":[],"sectionSources":[]}}
    """#
    func setupHarness(folders: [String] = [], inputWindow: Int = 60000) throws -> (DeepSeekHarness, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel(); StubProtocol.handler = nil; try? FileManager.default.removeItem(at: root) }
        return (DeepSeekHarness(configuration: HarnessConfiguration(apiKey: "test-not-a-secret", folders: folders), session: session, cacheDirectory: root, inputWindow: inputWindow), root)
    }
    func envelope(_ content: String) throws -> Data { try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": content]]]]) }
    func note() -> Recording { var item = Recording(); item.segments = [.init(start: 0, end: 5, text: "derivative 描述变化率。")]; return item }
    func testStructuredResultAndCheckpointAvoidRepeatedAPIRequests() async throws {
        let (harness, _) = try setupHarness(); let data = try envelope(valid); var requests = 0
        StubProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.host, "api.deepseek.com")
            XCTAssertEqual(request.httpMethod, "POST")
            return (200, data)
        }
        let item = note()
        let a = try await harness.run(recording: item) { _ in }
        let b = try await harness.run(recording: item) { _ in }
        XCTAssertEqual(a, b); XCTAssertEqual(a.subject, "数学"); XCTAssertEqual(requests, 1)
    }
    func testMalformedOutputIsRetriedAndAuthenticationFailureIsNot() async throws {
        let (harness, _) = try setupHarness(); let good = try envelope(valid); let bad = try envelope("{}"); var count = 0
        StubProtocol.handler = { _ in count += 1; return (200, count < 3 ? bad : good) }
        _ = try await harness.run(recording: note()) { _ in }
        XCTAssertEqual(count, 3)
        count = 0; StubProtocol.handler = { _ in count += 1; return (401, Data()) }
        var uncached = note(); uncached.segments.append(.init(start: 5, end: 9, text: "积分对应积累。"))
        do { _ = try await harness.run(recording: uncached) { _ in }; XCTFail("Accepted 401") } catch {}
        XCTAssertEqual(count, 1)
    }
    func testLowConfidenceClassificationFallsBack() throws {
        let value = try JSONDecoder().decode(Analysis.self, from: Data(valid.replacingOccurrences(of: "0.95", with: "0.3").utf8))
        XCTAssertEqual(try value.validated().subject, "待分类")
    }
    func testSuggestedFolderMustExactlyMatchAnExistingDirectory() async throws {
        let (first, _) = try setupHarness(folders: ["课程/数学"])
        let invalid = try envelope(valid.replacingOccurrences(of: "\"uncertainties\":[]", with: "\"uncertainties\":[],\"suggestedFolder\":\"../escape\""))
        StubProtocol.handler = { _ in (200, invalid) }
        let rejected = try await first.run(recording: note()) { _ in }
        XCTAssertEqual(rejected.suggestedFolder, "")
        let (second, _) = try setupHarness(folders: ["课程/数学"])
        let good = try envelope(valid.replacingOccurrences(of: "\"uncertainties\":[]", with: "\"uncertainties\":[],\"suggestedFolder\":\"课程/数学\""))
        StubProtocol.handler = { _ in (200, good) }
        let accepted = try await second.run(recording: note()) { _ in }
        XCTAssertEqual(accepted.suggestedFolder, "课程/数学")
    }
    private func body(_ request: URLRequest) throws -> String {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }
        }
        let value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let messages = value["messages"] as! [[String: String]]
        return messages.last!["content"]!
    }
    func testLongRecordingSynthesizesFullDetailsInsteadOfConcatenatingChunks() async throws {
        let (harness, _) = try setupHarness(inputWindow: 2000)
        var transcript = note(); transcript.segments[0].text = String(repeating: "课程内容", count: 650)
        var extractionCount = 0, synthesisInput = ""
        StubProtocol.handler = { request in
            let input = try self.body(request)
            var analysis = try JSONDecoder().decode(Analysis.self, from: Data(self.valid.utf8))
            if input.contains("以下资料来自同一场录音") {
                synthesisInput = input
                analysis.organizedMarkdown = "## 统一的知识主线\n\n跨片段整合后的主题关系。"
            } else {
                extractionCount += 1
                analysis.organizedMarkdown = "## 资料\n\n独特细节-\(extractionCount)"
            }
            return (200, try self.envelope(String(decoding: JSONEncoder().encode(analysis), as: UTF8.self)))
        }
        let result = try await harness.run(recording: transcript) { _ in }
        XCTAssertGreaterThan(extractionCount, 1)
        XCTAssertTrue(synthesisInput.contains("独特细节-1"))
        XCTAssertTrue(synthesisInput.contains("独特细节-\(extractionCount)"))
        XCTAssertEqual(result.organizedMarkdown, "## 统一的知识主线\n\n跨片段整合后的主题关系。")
        XCTAssertEqual(result.noteFormatVersion, 3)
    }
    func testSentenceTimelineIsRejectedAndRewritten() async throws {
        let (harness, _) = try setupHarness(); var count = 0
        StubProtocol.handler = { _ in
            count += 1
            var analysis = try JSONDecoder().decode(Analysis.self, from: Data(self.valid.utf8))
            if count == 1 { analysis.organizedMarkdown = "## 内容\n[00:00] 第一条。\n[00:10] 第二条。\n[00:20] 第三条。" }
            return (200, try self.envelope(String(decoding: JSONEncoder().encode(analysis), as: UTF8.self)))
        }
        let result = try await harness.run(recording: note()) { _ in }
        XCTAssertEqual(count, 2); XCTAssertFalse(result.organizedMarkdown.contains("[00:20]"))
    }
}

final class LearningDocumentTests: XCTestCase {
    func analysis() throws -> Analysis {
        try JSONDecoder().decode(Analysis.self, from: Data(###"{"title":"概念辨析","subject":"物理","confidence":0.9,"abstract":"索引摘要","keyPoints":[],"concepts":[],"questions":[],"tags":["实验"],"organizedMarkdown":"## 一、概念辨析\n\n|维度|A|B|\n|---|---|---|\n|含义|解释A|解释B|","uncertainties":[],"learning":{"goals":["区分A和B"],"aliases":["A与B"],"sectionSources":[{"heading":"一、概念辨析","evidenceSegmentIDs":["known","invented"]}],"keyTerms":["概念A","概念B"]}}"###.utf8))
    }
    func testLearningSourcesAreVerifiedAndNoSelfTestIsGenerated() throws {
        var a = try analysis(); a.learning = a.learning?.grounded(in: ["known"])
        XCTAssertEqual(a.learning?.sectionSources.first?.evidenceSegmentIDs, ["known"])
        XCTAssertTrue(a.documentBody.contains("本篇要掌握"))
        XCTAssertFalse(a.documentBody.contains("自测"))
        XCTAssertFalse(a.documentBody.contains("参考答案"))
    }
    func testMarkdownTableAndObsidianCalloutAreParsed() {
        let blocks = MarkdownBlocks.parse("## 概念\n\n| | A | B |\n|---|---|---|\n|对比|x\\|y|z|\n\n> [!question]- 为什么？\n> 因为原理。")
        XCTAssertTrue(blocks.contains(.table(["", "A", "B"], [["对比", "x|y", "z"]])))
        XCTAssertTrue(blocks.contains(.callout(kind: "question", title: "为什么？", body: "因为原理。", collapsed: true)))
    }
    func testExportUsesSingleAdaptiveBodyWithPropertiesAndSectionIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: raw) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var note = Recording(); note.title = "概念辨析"; note.subject = "物理"; note.segments = [.init(start: 0, end: 5, text: "原稿独立保存", id: "known")]
        var a = try analysis(); a.learning = a.learning?.grounded(in: ["known"]); a.noteFormatVersion = 3
        note.analysis = a; note.analyzedTranscriptHash = digest(note.transcript); note.transcriptComplete = true
        let exported = try await ArchiveWriter().export(note, root: root, subfolder: "", rawRoot: raw)
        let text = try String(contentsOf: root.appendingPathComponent(exported.exportNote!), encoding: .utf8)
        XCTAssertTrue(text.contains("type: learning-note")); XCTAssertTrue(text.contains("aliases:")); XCTAssertTrue(text.contains(a.documentBody))
        XCTAssertFalse(text.contains("## 整理稿")); XCTAssertFalse(text.contains("## 关键内容")); XCTAssertFalse(text.contains("索引摘要"))
        let rows = try String(contentsOf: root.appendingPathComponent("_声笺/agent/sections.jsonl"), encoding: .utf8).split(separator: "\n")
        let objects = try rows.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        let section = try XCTUnwrap(objects.first { $0["heading"] as? String == "一、概念辨析" })
        XCTAssertEqual(section["source_segment_ids"] as? [String], ["known"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("_声笺/agent/learning/\(note.id).json").path))
    }
}

final class KnowledgeLinkTests: XCTestCase {
    func testExistingNoteAliasProducesWikilinkWithoutLinkingInsideWordsOrCode() {
        let note = KnowledgeNoteReference(path: "概念/科学假说.md", title: "科学假说", aliases: ["Hypothesis", "假说"])
        let text = "Hyperhypothesis 不应被切开。Hypothesis 是解释。\n```text\nHypothesis\n```\n假说可检验。"
        let linked = KnowledgeLinks.apply(to: text, terms: ["Hypothesis"], notes: [note])
        XCTAssertTrue(linked.contains("Hyperhypothesis")); XCTAssertTrue(linked.contains("[[概念/科学假说|Hypothesis]]"))
        XCTAssertTrue(linked.contains("```text\nHypothesis\n```"))
    }
    func testTablePipesAreEscapedAndUnknownImportantConceptsRemainPlaceholders() {
        let note = KnowledgeNoteReference(path: "概念/假说.md", title: "假说", aliases: ["Hypothesis"])
        let linked = KnowledgeLinks.apply(to: "|术语|Hypothesis|\nPrediction 是可测预期。 [[../../bad|错误链接]]", terms: ["Prediction"], notes: [note])
        XCTAssertTrue(linked.contains("[[概念/假说\\|Hypothesis]]")); XCTAssertTrue(linked.contains("[[Prediction]]"))
        XCTAssertFalse(linked.contains("[[../../bad"))
        XCTAssertEqual(MarkdownBlocks.cells(linked.components(separatedBy: "\n")[0]).count, 2)
        let preview = KnowledgeLinks.previewMarkdown("[[概念/假说|Hypothesis]]", vaultPath: "/tmp/示例仓库")
        XCTAssertTrue(preview.contains("obsidian://open?path=%2F")); XCTAssertFalse(preview.contains("[["))
    }
    func testInventoryUsesNoteNamesAndFrontmatterAliasesAndExcludesCurrentNote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("概念"), withIntermediateDirectories: true)
        let note = root.appendingPathComponent("概念/科学假说.md")
        try Data("---\ntitle: 科学假说\naliases: [\"Hypothesis\",\"假说\"]\n---\n此处正文不应被当成别名：私有正文词".utf8).write(to: note)
        let candidates = try KnowledgeNoteIndex.candidates(root: root, transcript: "Hypothesis 和实验")
        XCTAssertEqual(candidates.count, 1); XCTAssertEqual(candidates[0].path, "概念/科学假说.md")
        XCTAssertTrue(candidates[0].aliases.contains("Hypothesis")); XCTAssertFalse(candidates[0].aliases.contains("私有正文词"))
        XCTAssertTrue(try KnowledgeNoteIndex.candidates(root: root, transcript: "Hypothesis", excluding: "概念/科学假说.md").isEmpty)
    }
}
