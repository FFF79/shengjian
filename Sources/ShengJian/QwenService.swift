import Foundation
import ShengJianCore

enum QwenRuntime {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/声笺/ASR")
    static let modelDirectory = directory.appendingPathComponent("models/Qwen3-ASR-1.7B-8bit")
    static let python = directory.appendingPathComponent("runtime/bin/python")
    static var worker: URL { Bundle.main.resourceURL!.appendingPathComponent("qwen_worker.py") }
    static func isAvailable(modelPath: String) -> Bool {
        let folder = URL(fileURLWithPath: modelPath)
        return FileManager.default.isExecutableFile(atPath: python.path)
            && ["config.json", "model.safetensors", "tokenizer_config.json", "vocab.json", "merges.txt", "preprocessor_config.json"].allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
            && FileManager.default.fileExists(atPath: worker.path)
    }
}

actor QwenService {
    private let worker = LocalASRWorker(python: QwenRuntime.python, script: QwenRuntime.worker)
    func load(path: String) async throws { try await worker.load(modelPath: path) }
    func unload() async { await worker.unload() }
    func transcribe(_ chunk: AudioChunk, prompt: String, modelPath: String) async throws -> [TranscriptSegment] {
        guard !chunk.samples.isEmpty else { return [] }
        let rms = sqrt(chunk.samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.samples.count))
        guard rms >= 0.0003 else { return [] }
        let pcm = chunk.samples.withUnsafeBytes { Data($0) }
        let text = try await worker.transcribe(pcm: pcm, sampleCount: chunk.samples.count, modelPath: modelPath, prompt: prompt)
        guard !text.isEmpty else { return [] }
        // Qwen ASR returns chunk boundaries, not word-level alignment. Preserve the actual capture interval.
        return [TranscriptSegment(start: chunk.start, end: chunk.end, text: text)]
    }
}
