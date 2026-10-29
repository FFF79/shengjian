#if os(macOS)
import Foundation
import Darwin

/// One persistent inference process. Synchronous actor methods serialize requests across recording rounds.
/// The pipe carries a JSON header followed by raw mono float32 PCM; no audio file or local server is used.
public actor LocalASRWorker {
    private final class Connection {
        let process: Process
        let input: FileHandle
        let output: FileHandle
        let modelPath: String
        init(process: Process, input: FileHandle, output: FileHandle, modelPath: String) {
            self.process = process; self.input = input; self.output = output; self.modelPath = modelPath
        }
        deinit {
            try? input.close(); try? output.close()
            if process.isRunning { process.terminate() }
        }
    }
    private let python: URL
    private let script: URL
    private let timeout: TimeInterval
    private var connection: Connection?
    public init(python: URL, script: URL, timeout: TimeInterval = 120) {
        self.python = python; self.script = script; self.timeout = timeout
    }
    public func unload() { connection = nil }
    public func load(modelPath: String) throws {
        if let connection, connection.process.isRunning, connection.modelPath == modelPath { return }
        connection = nil
        guard FileManager.default.isExecutableFile(atPath: python.path), FileManager.default.fileExists(atPath: script.path) else {
            throw AppError.message("千问本地运行组件缺失，请重新安装声笺的转写组件。")
        }
        // A closed worker must produce a recoverable error, not SIGPIPE termination of the recorder.
        signal(SIGPIPE, SIG_IGN)
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = python; process.arguments = ["-u", script.path, "--model", modelPath]
        var env = ProcessInfo.processInfo.environment
        for name in ["PYTHONPATH", "PYTHONHOME", "PYTHONSTARTUP"] { env.removeValue(forKey: name) }
        env["HF_HUB_OFFLINE"] = "1"; env["TRANSFORMERS_OFFLINE"] = "1"; env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"; env["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = env
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw AppError.message("千问本地组件无法启动，请检查运行环境。") }
        try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        let active = Connection(process: process, input: input.fileHandleForWriting, output: output.fileHandleForReading, modelPath: modelPath)
        do {
            try withDeadline(active) {
                let response = try readResponse(active)
                guard response["event"] as? String == "ready", response["sample_rate"] as? Int == 16000 else {
                    throw AppError.message("千问模型加载失败，请检查模型和运行组件是否完整。")
                }
            }
            connection = active
        } catch { throw error }
    }
    public func transcribe(pcm: Data, sampleCount: Int, modelPath: String, prompt: String) throws -> String {
        guard sampleCount > 0, sampleCount <= 16000 * 60, pcm.count == sampleCount * MemoryLayout<Float>.size else {
            throw AppError.message("转写音频数据长度无效。")
        }
        try load(modelPath: modelPath)
        guard let active = connection else { throw AppError.message("千问尚未加载。") }
        do {
            return try withDeadline(active) {
                let id = UUID().uuidString
                let header: [String: Any] = ["op": "transcribe", "request_id": id, "sample_count": sampleCount, "prompt": String(prompt.prefix(4000))]
                var data = try JSONSerialization.data(withJSONObject: header); data.append(10)
                try active.input.write(contentsOf: data)
                try active.input.write(contentsOf: pcm)
                let response = try readResponse(active)
                guard response["request_id"] as? String == id, response["event"] as? String == "result", let text = response["text"] as? String else {
                    throw AppError.message("千问未能完成这个片段，声音暂留内存，可重试。")
                }
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            connection = nil
            throw error
        }
    }
    private func readResponse(_ active: Connection) throws -> [String: Any] {
        var line = Data()
        while line.count < 1024 * 1024 {
            guard let byte = try active.output.read(upToCount: 1), !byte.isEmpty else {
                throw AppError.message("千问本地组件已退出，未转写的声音暂留内存，可重试。")
            }
            if byte.first == 10 {
                guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { break }
                return value
            }
            line.append(byte)
        }
        throw AppError.message("千问本地组件返回了无效结果。")
    }
    private func withDeadline<T>(_ active: Connection, _ work: () throws -> T) throws -> T {
        let process = active.process
        let watchdog = DispatchWorkItem {
            // SIGKILL also releases pipes if a native inference operation does not handle termination.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }
        return try work()
    }
}
#endif
