import AppKit
import Foundation

/// Installs only public runtime/model components. It never reads credentials or recording data.
@MainActor final class ASRInstaller: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var status = ""
    @Published private(set) var log = ""
    @Published private(set) var succeeded = false
    private var task: Task<Void, Never>?
    func start() {
        guard !running else { return }
        guard let resources = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: resources.appendingPathComponent("installer/setup_asr.sh").path) else {
            status = "安装脚本缺失，请重新下载完整应用。"; return
        }
        running = true; succeeded = false; log = ""; status = "准备安装…"
        let script = resources.appendingPathComponent("installer/setup_asr.sh")
        let base = QwenRuntime.directory
        let cleanEnvironment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "TMPDIR": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8", "SHENGJIAN_ASR_BASE": base.path]
        task = Task {
            let code = await Task.detached(priority: .utility) { [weak self] () -> Int32 in
                let process = Process(), pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/sh"); process.arguments = [script.path]
                process.environment = cleanEnvironment; process.standardOutput = pipe; process.standardError = pipe
                let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "安装本地转写组件")
                defer { ProcessInfo.processInfo.endActivity(activity); try? pipe.fileHandleForReading.close() }
                do {
                    try process.run(); try? pipe.fileHandleForWriting.close()
                    while true {
                        let bytes = pipe.fileHandleForReading.availableData
                        if bytes.isEmpty { break }
                        await self?.append(String(decoding: bytes, as: UTF8.self))
                    }
                    process.waitUntilExit(); return process.terminationStatus
                } catch { await self?.append("\n安装进程未能完成，请重试。\n"); return -1 }
            }.value
            running = false; succeeded = code == 0 && QwenRuntime.isAvailable(modelPath: QwenRuntime.modelDirectory.path)
            status = succeeded ? "本地转写组件已就绪。" : "安装未完成，已保留下载进度，可重试。"
        }
    }
    private func append(_ text: String) {
        log = String((log + text).suffix(12000))
        if let line = text.components(separatedBy: .newlines).last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { status = String(line.suffix(180)) }
    }
}
