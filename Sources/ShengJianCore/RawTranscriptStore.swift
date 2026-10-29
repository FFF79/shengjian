import Foundation

public struct RawReference: Sendable {
    public var manuscript: URL
    public var chunks: URL
}

public enum RawTranscriptStore {
    public static func save(_ recording: Recording, root: URL) throws -> RawReference {
        let fm = FileManager.default
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let file = root.appendingPathComponent("\(date.string(from: recording.createdAt))｜原转录稿｜\(recording.id.prefix(8)).md")
        let chunks = root.appendingPathComponent(".声笺/chunks/\(recording.id).jsonl")
        let hashFile = root.appendingPathComponent(".声笺/hashes/\(recording.id).txt")
        let iso = ISO8601DateFormatter().string(from: recording.createdAt)
        func q(_ string: String) -> String { String(decoding: try! JSONEncoder().encode(string), as: UTF8.self) }
        let text = """
        ---
        id: \(q(recording.id))
        type: raw-transcript
        source_kind: \(recording.isDemo == true ? "synthetic-demo" : "microphone-recording")
        note_mode: \(recording.resolvedMode.rawValue)
        recording_label: \(q(recording.recordingLabel))
        recording_context: \(q(recording.analysis?.context ?? "pending"))
        scene_id: \(q(recording.analysis?.scene?.id ?? ""))
        scene_name: \(q(recording.recordingLabel))
        tags: \(String(decoding: try! JSONEncoder().encode(Array(Set([recording.recordingLabel] + (recording.resolvedMode == .study ? [recording.subject] : []))).sorted()), as: UTF8.self))
        created: \(q(iso))
        title: \(q(recording.title))
        subject: \(q(recording.subject))
        transcription_status: \(recording.transcriptComplete ? "complete" : "incomplete")
        transcriber_model: \(q(recording.transcriberModel))
        transcriber: \(q(recording.transcriberEngine ?? "whisper.cpp"))
        audio_saved: false
        ---

        # 原转录稿

        > 类型：\(recording.resolvedMode == .study ? "学习 · 科目：" + recording.subject : ["待识别", "场景待识别"].contains(recording.recordingLabel) ? "等待自动识别场景" : recording.recordingLabel + "（自动识别）")
        > 原始语音识别结果，未由 DeepSeek 改写。\(recording.transcriptComplete ? "" : "转写进行中或存在缺失片段。")

        \(recording.segments.map { "### \(timestamp($0.start))\n\n\($0.text)\n\n^seg-\($0.id)" }.joined(separator: "\n\n"))
        """
        if fm.fileExists(atPath: file.path) {
            let prior = try String(contentsOf: file, encoding: .utf8)
            let hash = try? String(contentsOf: hashFile, encoding: .utf8)
            guard prior == text || hash == digest(prior) else { throw AppError.message("独立原稿已被外部修改，已停止覆盖；识别文字仍保存在本机草稿中。") }
        }
        for folder in [root, chunks.deletingLastPathComponent(), hashFile.deletingLastPathComponent()] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        try Data(text.utf8).write(to: file, options: .atomic)
        try Data(digest(text).utf8).write(to: hashFile, options: .atomic)
        let rows = try recording.segments.map { s in
            let row: [String: Any] = ["recording_id": recording.id, "segment_id": s.id, "start_seconds": s.start, "end_seconds": s.end, "text": s.text, "raw_path": file.path, "anchor": "seg-\(s.id)"]
            return String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        }.joined(separator: "\n")
        try Data((rows.isEmpty ? "" : rows + "\n").utf8).write(to: chunks, options: .atomic)
        return RawReference(manuscript: file, chunks: chunks)
    }
}
