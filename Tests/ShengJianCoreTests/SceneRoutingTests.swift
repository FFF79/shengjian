import XCTest
@testable import ShengJianCore

final class SceneRoutingTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func body(_ request: URLRequest) throws -> String {
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count)) }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    private func envelope(_ text: String) throws -> Data { try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": text]]]]) }
    private var document: String { ###"{"title":"设计取舍","subject":"模型试图改分类","confidence":0.99,"abstract":"讨论设计选择。","keyPoints":[],"concepts":[],"questions":[],"tags":["设计"],"organizedMarkdown":"## 评审结论\n\n保留操作入口。","uncertainties":[],"suggestedFolder":"../escape","context":"personal","learning":{"goals":["不该生成"],"aliases":[],"keyTerms":[],"sectionSources":[{"heading":"评审结论","evidenceSegmentIDs":["source"]}]}}"### }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel(); StubProtocol.handler = nil }; return session
    }
    private func note() -> Recording {
        var note = Recording(); note.segments = [.init(start: 0, end: 5, text: "评审设计方案和交互入口。", id: "source")]; note.transcriptComplete = true; return note
    }
    func testAutomaticPipelineClassifiesFirstAndLocksCustomBindingAndFormat() async throws {
        let root = try directory(), raw = try directory(), session = session()
        _ = try VaultFolders.create("工作/评审", at: root)
        let scene = SceneDefinition(id: "review", name: "产品评审", description: "评审设计", folder: "工作/评审", style: .discussion, format: "先结论再分歧")
        var requests = 0
        StubProtocol.handler = { request in
            requests += 1; let body = try self.body(request)
            if requests == 1 {
                XCTAssertTrue(body.contains("独立的录音分类阶段")); XCTAssertTrue(body.contains("评审设计方案"))
                return (200, try self.envelope(#"{"sceneID":"review","confidence":0.95,"style":"meeting"}"#))
            }
            XCTAssertTrue(body.contains("先结论再分歧")); XCTAssertFalse(body.contains("当前用户选择的整理模式"))
            return (200, try self.envelope(self.document))
        }
        let harness = DeepSeekHarness(configuration: .init(apiKey: "fixture", folders: ["工作", "工作/评审"], scenes: [scene]), session: session, cacheDirectory: root)
        var note = note(); let result = try await harness.run(recording: note) { _ in }
        XCTAssertEqual(result.scene?.name, "产品评审"); XCTAssertEqual(result.scene?.style, .discussion)
        XCTAssertEqual(result.subject, "产品评审"); XCTAssertEqual(result.suggestedFolder, "工作/评审")
        XCTAssertEqual(result.learning?.goals, []); XCTAssertEqual(result.mode, .automatic)
        let cached = try await harness.run(recording: note) { _ in }; XCTAssertEqual(cached, result); XCTAssertEqual(requests, 2)
        note.analysis = result; note.subject = result.subject; note.analyzedTranscriptHash = digest(note.transcript)
        let saved = try await ArchiveWriter().export(note, root: root, subfolder: result.suggestedFolder!, rawRoot: raw)
        let manifest = try String(contentsOf: root.appendingPathComponent("_声笺/agent/records/\(saved.id).json"))
        XCTAssertTrue(manifest.contains("产品评审")); XCTAssertTrue(manifest.contains("sceneStyle"))
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent(saved.exportNote!)).contains("scene_name:"))
    }
    func testFolderInferenceAndExplicitRootBindingAreSafe() {
        let scene = SceneDefinition(id: "root", name: "随记", folder: "", style: .personal)
        let candidates = SceneRouting.candidates(scenes: [scene], folders: ["物理", "未分类"])
        XCTAssertTrue(candidates.contains(where: { $0.id == "folder:物理" }))
        XCTAssertFalse(candidates.contains(where: { $0.folder == "未分类" }))
        let route = SceneRouting.resolve(id: "folder:物理", confidence: 0.9, detectedStyle: .topic, candidates: candidates, folders: ["物理"])
        XCTAssertEqual(route.folder, "物理")
        XCTAssertEqual(SceneRouting.resolve(id: "root", confidence: 0.9, detectedStyle: .meeting, candidates: candidates, folders: []).folder, "")
        XCTAssertNil(SceneRouting.resolve(id: "forged", confidence: 0.99, detectedStyle: .meeting, candidates: candidates, folders: []).folder)
        XCTAssertNil(SceneRouting.resolve(id: "folder:物理", confidence: 0.3, detectedStyle: .topic, candidates: candidates, folders: ["物理"]).id)
    }
    func testCustomSceneSuppressesImplicitSameFolderAndMissingBindingFallsBack() {
        let scene = SceneDefinition(id: "custom", name: "评审", folder: "工作", style: .discussion)
        let candidates = SceneRouting.candidates(scenes: [scene], folders: ["工作"])
        XCTAssertEqual(candidates.count, 1)
        let route = SceneRouting.resolve(id: "custom", confidence: 0.9, detectedStyle: .topic, candidates: candidates, folders: [])
        XCTAssertEqual(route.name, "评审"); XCTAssertNil(route.folder)
    }
    func testCreatingCategoryRejectsTraversalHiddenPathsAndSymlinks() throws {
        let root = try directory(), outside = try directory()
        XCTAssertEqual(try VaultFolders.create("工作/会议", at: root), "工作/会议")
        for bad in ["../escape", "/absolute", ".obsidian", "工作//会议", "_声笺", "a/b/c/d/e"] { XCTAssertThrowsError(try VaultFolders.create(bad, at: root)) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("别名"), withDestinationURL: outside)
        XCTAssertThrowsError(try VaultFolders.create("别名/逃逸", at: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("逃逸").path))
    }
    func testSceneExplicitRootBindingExportsToRootWhileUnboundGoesToUnclassified() async throws {
        let root = try directory(), raw = try directory(); var item = note()
        item.analysis = try JSONDecoder().decode(Analysis.self, from: Data(document.utf8))
        item.analysis?.scene = SceneRoute(id: "root", name: "随记", folder: "", style: .personal, confidence: 0.9)
        item.analyzedTranscriptHash = digest(item.transcript)
        let saved = try await ArchiveWriter().export(item, root: root, subfolder: "", rawRoot: raw)
        XCTAssertFalse(saved.exportNote!.contains("/")); XCTAssertEqual(saved.needsClassification, false)
        var second = note(); second.analysis = item.analysis; second.analysis?.scene?.folder = nil; second.analyzedTranscriptHash = digest(second.transcript)
        let fallback = try await ArchiveWriter().export(second, root: root, subfolder: "", rawRoot: raw)
        XCTAssertTrue(fallback.exportNote!.hasPrefix("未分类/"))
    }
    func testClassificationAuthenticationErrorDoesNotTriggerSummaryOrRetry() async throws {
        let root = try directory(), session = session(); var calls = 0
        StubProtocol.handler = { _ in calls += 1; return (401, Data()) }
        let harness = DeepSeekHarness(configuration: .init(apiKey: "fixture"), session: session, cacheDirectory: root)
        do { _ = try await harness.run(recording: note()) { _ in }; XCTFail("Accepted invalid credentials") } catch {}
        XCTAssertEqual(calls, 1)
    }
    func testLongClassificationReadsEveryChunkAndCachesTheDecision() async throws {
        let root = try directory(), session = session(); var calls = 0, sawEnd = false
        StubProtocol.handler = { request in
            calls += 1; let body = try self.body(request); sawEnd = sawEnd || body.contains("最后的原稿标记")
            return (200, try self.envelope(#"{"sceneID":"folder:工作","confidence":0.95,"style":"meeting"}"#))
        }
        let classifier = SceneClassifier(configuration: .init(apiKey: "fixture", folders: ["工作"]), session: session, cacheDirectory: root, inputWindow: 1000)
        let text = String(repeating: "讨论项目议题。", count: 500) + "最后的原稿标记"
        let first = try await classifier.classify(text) { _ in }
        XCTAssertGreaterThan(calls, 1); XCTAssertTrue(sawEnd); let initialCalls = calls
        let cached = try await classifier.classify(text) { _ in }
        XCTAssertEqual(cached, first); XCTAssertEqual(calls, initialCalls)
    }
    func testChangingSceneBindingInvalidatesClassificationCache() async throws {
        let root = try directory(), session = session(); var calls = 0
        StubProtocol.handler = { _ in calls += 1; return (200, try self.envelope(#"{"sceneID":"review","confidence":0.9,"style":"meeting"}"#)) }
        let first = SceneDefinition(id: "review", name: "评审", folder: "工作", style: .discussion)
        var second = first; second.folder = "归档"; second.format = "结论优先"
        let a = SceneClassifier(configuration: .init(apiKey: "fixture", folders: ["工作", "归档"], scenes: [first]), session: session, cacheDirectory: root, inputWindow: 1000)
        let b = SceneClassifier(configuration: .init(apiKey: "fixture", folders: ["工作", "归档"], scenes: [second]), session: session, cacheDirectory: root, inputWindow: 1000)
        let original = try await a.classify("一次评审") { _ in }, updated = try await b.classify("一次评审") { _ in }
        XCTAssertEqual(original.folder, "工作"); XCTAssertEqual(updated.folder, "归档"); XCTAssertEqual(updated.format, "结论优先"); XCTAssertEqual(calls, 2)
    }

    func testUnmatchedFolderStillUsesDetectedSceneStructure() async throws {
        let root = try directory(), session = session()
        StubProtocol.handler = { _ in (200, try self.envelope(#"{"sceneID":null,"confidence":0.2,"style":"lecture"}"#)) }
        let classifier = SceneClassifier(configuration: .init(apiKey: "fixture"), session: session, cacheDirectory: root, inputWindow: 1000)
        let result = try await classifier.classify("一次分享") { _ in }
        XCTAssertEqual(result.name, "未分类"); XCTAssertNil(result.folder); XCTAssertEqual(result.style, .lecture)
    }

}
