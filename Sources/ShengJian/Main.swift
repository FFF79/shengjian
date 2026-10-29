import AppKit
import SwiftUI
import AVFoundation
import QuartzCore
import Combine
import ShengJianCore

@main struct Launcher {
    @MainActor static func main() {
        if let flag = CommandLine.arguments.firstIndex(of: "--verify-study-note"), CommandLine.arguments.count > flag + 1 {
            guard let key = KeychainStore.load(interactionAllowed: false) else { print("DeepSeek key unavailable without prompting; no request sent"); exit(2) }
            let folder = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            Task.detached {
                do {
                    var recording = Recording()
                    let source = [
                        "今天讨论科学研究中假说、可检验预期和实验之间的联系。不是先随便做实验，而是先说清楚要检验什么。",
                        "Hypothesis 假说是对现象的解释，Prediction 预期是由假说推出、能观察或测量的结果。可以用 if 改变什么，then 观察到什么来表达预期。假说和预期不能混成一个词。",
                        "设计实验时主动改变 independent variable 自变量，测量 dependent variable 因变量，尽量保持其他 constant variables 控制变量不变。要说明具体怎样改变和测量。",
                        "误差要区分。Systematic error 系统误差有固定方向，需要检查并校准仪器。Random error 随机误差方向不固定，可以通过重复测量取平均减轻影响。重复测量不能自动解决系统偏差。",
                        "比如手机黑屏，我们假设是没电。由此推导充电后应该能开机，再插电观察。没开机不一定直接推翻假说，还要检查充电器是否正常；开机也只是支持这个解释。",
                        "最后回到假说和预期：一个解释现象，一个给出可检验结果。写实验报告要把推理链、操作过程、观测结果和误差限制分清楚，不能只写一个结论。"
                    ]
                    recording.segments = source.enumerated().map { .init(start: Double($0.offset * 30), end: Double(($0.offset + 1) * 30), text: $0.element, id: "demo-segment-\($0.offset + 1)") }
                    let model = UserDefaults.standard.string(forKey: "deepSeekModel") ?? "deepseek-flash"
                    let harness = DeepSeekHarness(configuration: HarnessConfiguration(apiKey: key, model: model), cacheDirectory: folder.appendingPathComponent(".checks"))
                    let analysis = try await harness.run(recording: recording) { print($0) }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let document = "---\ntype: learning-note\nsource: synthetic-demo\nnote_format_version: 3\n---\n\n# \(analysis.title)\n\n> 格式演示，使用模拟课堂转录验证整理流程。\n\n" + analysis.documentBody + "\n"
                    try Data(document.utf8).write(to: folder.appendingPathComponent("学习笔记格式示例.md"), options: .atomic)
                    try Data(analysis.documentBody.utf8).write(to: folder.appendingPathComponent(".preview-body.md"), options: .atomic)
                    try JSONEncoder().encode(analysis).write(to: folder.appendingPathComponent(".checks/result.json"), options: .atomic)
                    print("Validated generated learning note: \(folder.appendingPathComponent("学习笔记格式示例.md").path)")
                    exit(0)
                } catch { fputs("Study-note verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--verify-audio") {
            Task.detached {
                do {
                    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
                    let sink = try AudioSink(inputFormat: format)
                    for index in 0..<90 {
                        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
                        buffer.frameLength = 4800
                        for i in 0..<4800 { buffer.floatChannelData![0][i] = Float(sin(Double(index * 4800 + i) * 2 * .pi * 440 / 48000)) * 0.08 }
                        sink.accept(buffer)
                    }
                    await sink.stop()
                    let snapshot = await sink.snapshot()
                    guard abs(snapshot.0 - 9) < 0.01, snapshot.2 == nil else { throw AppError.message("Resampler duration mismatch: \(snapshot.0)") }
                    var count = 0
                    while let chunk = await sink.pull(interval: 6, force: true) { count += chunk.samples.count }
                    guard abs(count - 144000) < 160 else { throw AppError.message("PCM lost during chunking: \(count)") }
                    print("48kHz microphone PCM → 16kHz mono: \(count) samples, \(snapshot.0)s; no audio file written")
                    exit(0)
                } catch { fputs("Audio verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--verify-qwen") {
            let args = CommandLine.arguments
            guard let flag = args.firstIndex(of: "--verify-qwen"), args.count > flag + 1 else { print("Usage: --verify-qwen input-16k.wav [expected-text]"); exit(2) }
            let input = args[flag + 1]
            let expected = args.count > flag + 2 ? args[flag + 2] : ""
            let model = UserDefaults.standard.string(forKey: "qwenModelPath") ?? QwenRuntime.modelDirectory.path
            Task.detached {
                do {
                    let file = try AVAudioFile(forReading: URL(fileURLWithPath: input), commonFormat: .pcmFormatFloat32, interleaved: false)
                    guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
                          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw AppError.message("Fixture must be 16kHz mono") }
                    try file.read(into: buffer)
                    let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
                    let service = QwenService(); let start = Date()
                    try await service.load(path: model)
                    let loaded = Date()
                    let result = try await service.transcribe(AudioChunk(start: 0, samples: samples), prompt: "", modelPath: model)
                    print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
                    print("Qwen3-ASR: load \(String(format: "%.2f", loaded.timeIntervalSince(start)))s; decoded \(String(format: "%.2f", Double(samples.count) / 16000))s in \(String(format: "%.2f", Date().timeIntervalSince(loaded)))s")
                    guard !result.isEmpty, expected.isEmpty || result.map(\.text).joined().localizedCaseInsensitiveContains(expected) else { throw AppError.message("Expected fixture words were not recognized") }
                    // A second round must reuse the process and have independent capture timestamps.
                    let again = try await service.transcribe(AudioChunk(start: 100, samples: samples), prompt: "", modelPath: model)
                    guard again.first?.start == 100, again.map(\.text) == result.map(\.text) else { throw AppError.message("Recording rounds interfered") }
                    let silence = try await service.transcribe(AudioChunk(start: 200, samples: Array(repeating: 0, count: 16000)), prompt: "", modelPath: model)
                    guard silence.isEmpty else { throw AppError.message("Silence produced text") }
                    await service.unload()
                    print("Independent second round and silence guard passed; no microphone used or recording saved")
                    exit(0)
                } catch { fputs("Qwen verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var window: NSWindow!
    private var floating: FloatingController!
    private var status: NSStatusItem!
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = MainView(model: model, settings: model.settings, showFloating: { [weak self] in self?.floating.toggle() })
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "声笺"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 640, height: 540)
        window.contentView = NSHostingView(rootView: main); window.center()
        if let flag = CommandLine.arguments.firstIndex(of: "--preview-study-note"), CommandLine.arguments.count > flag + 1,
           let text = try? String(contentsOfFile: CommandLine.arguments[flag + 1], encoding: .utf8) {
            window.contentView = NSHostingView(rootView: ScrollView { StudyNoteView(markdown: text).padding(32) }.background(Color.white).preferredColorScheme(.light))
        }
        floating = FloatingController(model: model, openMain: { [weak self] in self?.showMain() })
        setupMenu()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "声笺")
        let menu = NSMenu(); menu.delegate = self; status.menu = menu
        showMain()
        if CommandLine.arguments.contains("--show-floating") { floating.show() }
        // Restore per-note folder grants without reading vault contents during startup.
        let bookmarks = UserDefaults.standard.dictionary(forKey: "noteBookmarks") as? [String: Data] ?? [:]
        for data in bookmarks.values {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale) { _ = url.startAccessingSecurityScopedResource() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.isRecording || model.isFinishing || model.isPreparing {
            let alert = NSAlert(); alert.messageText = "转写还在进行中"; alert.informativeText = "已经转成文字的原稿已保留。退出会释放尚未转写的内存音频。请先结束录音并等待转写完成。"
            alert.addButton(withTitle: "返回转写"); alert.runModal(); showMain(); return .terminateCancel
        }
        if terminating { return .terminateNow }
        terminating = true
        Task { await model.shutdown(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add("打开声笺", action: #selector(showMain), to: menu)
        add("显示悬浮窗", action: #selector(showFloat), to: menu)
        add("隐藏悬浮窗", action: #selector(hideFloat), to: menu)
        let record = add(model.isRecording ? "结束录音" : "开始录音", action: #selector(record), to: menu)
        record.isEnabled = model.isRecording || !model.busy
        menu.addItem(.separator()); add("设置…", action: #selector(settings), to: menu)
        menu.addItem(.separator()); add("退出声笺", action: #selector(quit), to: menu)
    }
    private func setupMenu() {
        let bar = NSMenu(); let appItem = NSMenuItem(); let app = NSMenu(); appItem.submenu = app; bar.addItem(appItem)
        add("关于声笺", action: #selector(about), to: app)
        app.addItem(.separator()); let settings = add("设置…", action: #selector(settings), to: app); settings.keyEquivalent = ","
        app.addItem(.separator()); let quit = add("退出声笺", action: #selector(quit), to: app); quit.keyEquivalent = "q"
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑"); editItem.submenu = edit; bar.addItem(editItem)
        for (title, action, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        NSApp.mainMenu = bar
    }
    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item); return item
    }
    @objc func showMain() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func showFloat() { floating.show() }
    @objc private func hideFloat() { floating.hide() }
    @objc private func record() { model.toggleRecording(); floating.show() }
    @objc private func settings() { showMain(); model.showSettings = true }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "声笺", .applicationVersion: "0.2.0", .credits: NSAttributedString(string: "本地转写 · 知识归档\nQwen3-ASR · MLX Audio · DeepSeek · Obsidian")]) }
}

@MainActor final class FloatingPresentation: ObservableObject {
    @Published var collapsed = false
}

@MainActor final class FloatingPanel: NSPanel {
    var isCollapsed = false
    var onExpand: (() -> Void)?
    override func sendEvent(_ event: NSEvent) {
        // Handle the whole tab at the window boundary, including transparent padding and rounded corners.
        if isCollapsed, event.type == .leftMouseDown, NSRect(origin: .zero, size: frame.size).contains(event.locationInWindow) {
            onExpand?(); return
        }
        super.sendEvent(event)
    }
}

@MainActor final class FloatingHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class FloatingController: NSObject, NSWindowDelegate {
    let panel: FloatingPanel
    let model: AppModel
    let openMain: () -> Void
    private let presentation = FloatingPresentation()
    private var adjusting = false
    private var expandedOrigin: NSPoint?
    private var moveTask: Task<Void, Never>?
    private var recordingObserver: AnyCancellable?
    private var collapsed: Bool { presentation.collapsed }
    private var expandedHeight: CGFloat { model.isRecording ? 152 : 110 }
    init(model: AppModel, openMain: @escaping () -> Void) {
        self.model = model; self.openMain = openMain
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 331, height: 110), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "声笺 · 悬浮窗"
        panel.isOpaque = false; panel.backgroundColor = NSColor.white.withAlphaComponent(0.01); panel.hasShadow = true
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.onExpand = { [weak self] in self?.expand() }
        let view = FloatingView(model: model, presentation: presentation, expand: { [weak self] in self?.expand() }, collapse: { [weak self] in self?.collapse() }, hide: { [weak self] in self?.hide() }, openMain: openMain)
        let hosting = FloatingHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: screen.maxX - 370, y: screen.maxY - 220))
        recordingObserver = model.$isRecording.removeDuplicates().dropFirst().sink { [weak self] recording in
            Task { @MainActor [weak self] in
                guard let self, !self.collapsed else { return }
                let frame = self.panel.frame
                let height: CGFloat = recording ? 152 : 110
                self.animate(to: NSRect(x: frame.minX, y: frame.maxY - height, width: 331, height: height))
            }
        }
    }
    func show() { panel.orderFrontRegardless() }
    func hide() { moveTask?.cancel(); panel.orderOut(nil) }
    func toggle() { if panel.isVisible { hide() } else { show() } }
    private func animate(to frame: NSRect) {
        adjusting = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.adjusting = false }
        }
    }
    func collapse() {
        guard !collapsed, !adjusting else { return }
        moveTask?.cancel()
        let screen = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        expandedOrigin = panel.frame.origin
        let right = panel.frame.midX > screen.midX
        panel.isCollapsed = true; panel.isMovableByWindowBackground = false; presentation.collapsed = true
        animate(to: NSRect(x: right ? screen.maxX - 49 : screen.minX, y: min(max(panel.frame.midY - 68, screen.minY + 8), screen.maxY - 144), width: 49, height: 136))
    }
    func expand() {
        guard collapsed, !adjusting else { return }
        moveTask?.cancel()
        let screen = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let original = expandedOrigin ?? NSPoint(x: screen.maxX - 370, y: panel.frame.minY)
        let x = min(max(original.x, screen.minX + 20), screen.maxX - 351)
        let y = min(max(original.y, screen.minY + 12), screen.maxY - expandedHeight - 12)
        panel.isCollapsed = false; panel.isMovableByWindowBackground = true; presentation.collapsed = false
        animate(to: NSRect(x: x, y: y, width: 331, height: expandedHeight))
    }
    func windowDidMove(_ notification: Notification) {
        guard !adjusting, !collapsed else { return }
        moveTask?.cancel()
        moveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            while NSEvent.pressedMouseButtons != 0, !Task.isCancelled { try? await Task.sleep(nanoseconds: 25_000_000) }
            guard let self, !Task.isCancelled, !self.adjusting, !self.collapsed, let screen = self.panel.screen?.visibleFrame else { return }
            if self.panel.frame.minX <= screen.minX + 12 || self.panel.frame.maxX >= screen.maxX - 12 { self.collapse() }
        }
    }
}
