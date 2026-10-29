import XCTest
@testable import ShengJianCore

final class LocalASRWorkerTests: XCTestCase {
    private func fixture(_ behavior: String, timeout: TimeInterval = 15) throws -> (URL, LocalASRWorker) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("worker.py")
        let source = """
        import json, sys, struct, time
        print(json.dumps({"event":"ready", "sample_rate":16000}), flush=True)
        while True:
            line = sys.stdin.buffer.readline()
            if not line: break
            request = json.loads(line)
            pcm = sys.stdin.buffer.read(request['sample_count'] * 4)
            \(behavior)
        """
        try Data(source.utf8).write(to: script)
        let python = ["/opt/homebrew/bin/python3.12", "/usr/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) }!
        return (root, LocalASRWorker(python: URL(fileURLWithPath: python), script: script, timeout: timeout))
    }
    func testBinaryPCMRoundsRemainIndependentAndUseOfflineEnvironment() async throws {
        let (root, worker) = try fixture("print(json.dumps({'event':'result','request_id':request['request_id'],'text':request['prompt'] + ':' + str(struct.unpack('<f', pcm[:4])[0]) + ':' + __import__('os').environ['HF_HUB_OFFLINE']}), flush=True)")
        defer { try? FileManager.default.removeItem(at: root) }
        let samples: [Float] = [0.25, -0.5]
        let pcm = samples.withUnsafeBytes { Data($0) }
        let first = try await worker.transcribe(pcm: pcm, sampleCount: 2, modelPath: "fixture", prompt: "第一轮")
        let second = try await worker.transcribe(pcm: pcm, sampleCount: 2, modelPath: "fixture", prompt: "第二轮")
        XCTAssertEqual(first, "第一轮:0.25:1"); XCTAssertEqual(second, "第二轮:0.25:1")
        await worker.unload()
    }
    func testConcurrentRoundsAreSerialized() async throws {
        let (root, worker) = try fixture("time.sleep(0.05); print(json.dumps({'event':'result','request_id':request['request_id'],'text':request['prompt']}), flush=True)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pcm = [Float(0.1)].withUnsafeBytes { Data($0) }
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<5 { group.addTask { try await worker.transcribe(pcm: pcm, sampleCount: 1, modelPath: "fixture", prompt: "round-\(i)") } }
            var values: [String] = []; for try await value in group { values.append(value) }; return values
        }
        XCTAssertEqual(Set(results), Set((0..<5).map { "round-\($0)" }))
        await worker.unload()
    }
    func testWorkerExitIsRecoverable() async throws {
        let (root, worker) = try fixture("sys.exit(1)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pcm = [Float(0.1)].withUnsafeBytes { Data($0) }
        for _ in 0..<2 {
            do { _ = try await worker.transcribe(pcm: pcm, sampleCount: 1, modelPath: "fixture", prompt: ""); XCTFail("Expected worker exit") }
            catch { XCTAssertTrue(error.localizedDescription.contains("退出")) }
        }
        await worker.unload()
    }
    func testInvalidPCMIsRejectedBeforeStartingWorker() async throws {
        let worker = LocalASRWorker(python: URL(fileURLWithPath: "/missing"), script: URL(fileURLWithPath: "/missing"))
        do { _ = try await worker.transcribe(pcm: Data(), sampleCount: 1, modelPath: "fixture", prompt: ""); XCTFail("Expected length validation") }
        catch { XCTAssertTrue(error.localizedDescription.contains("长度")) }
    }
    func testUnresponsiveWorkerTimesOutAndCanBeUnloaded() async throws {
        let (root, worker) = try fixture("time.sleep(30)", timeout: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let pcm = [Float(0.1)].withUnsafeBytes { Data($0) }, start = Date()
        do { _ = try await worker.transcribe(pcm: pcm, sampleCount: 1, modelPath: "fixture", prompt: ""); XCTFail("Expected timeout") }
        catch { XCTAssertLessThan(Date().timeIntervalSince(start), 6) }
        await worker.unload()
    }
}
