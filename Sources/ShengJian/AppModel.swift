import AppKit
import SwiftUI
import ShengJianCore

@MainActor final class AppModel: ObservableObject {
    let settings = SettingsStore()
    @Published var recordings = SessionFiles.load()
    @Published var selectedID: String?
    @Published var activeID: String?
    @Published var isRecording = false
    @Published var isPreparing = false
    @Published var finishingIDs: Set<String> = []
    @Published var summarizingIDs: Set<String> = []
    @Published var exportingIDs: Set<String> = []
    @Published var jobProgress: [String: String] = [:]
    @Published var availableFolders: [String] = []
    @Published var level: Float = 0
    @Published var notice: String?
    @Published var showSettings = false
    @Published var selectedTab = 0
    @Published var filter = ""
    private let mic = Microphone()
    private let transcriber = QwenService()
    private let archive = ArchiveWriter()
    private var loopTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var summaryTasks: [String: Task<Void, Never>] = [:]
    private var failedChunks: [String: [AudioChunk]] = [:]
    private var modelPaths: [String: String] = [:]
    private var activities: [String: NSObjectProtocol] = [:]
    var selected: Recording? { recordings.first { $0.id == selectedID } }
    var active: Recording? { recordings.first { $0.id == activeID } }
    // Only an active microphone or its initial permission request blocks a new round.
    var busy: Bool { isRecording || isPreparing }
    var isFinishing: Bool { !finishingIDs.isEmpty }
    var summarizingID: String? { selectedID.flatMap { summarizingIDs.contains($0) ? $0 : nil } }
    var exporting: Bool { !exportingIDs.isEmpty }
    var progress: String { selectedID.flatMap { jobProgress[$0] } ?? "准备就绪" }
    var selectedProcessing: Bool { selectedID.map { processing($0) } ?? false }
    var processingCount: Int { finishingIDs.union(summarizingIDs).union(exportingIDs).count }
    var filtered: [Recording] { filter.isEmpty ? recordings : recordings.filter { ($0.title + $0.subject + $0.transcript).localizedCaseInsensitiveContains(filter) } }
    init() {
        selectedID = nil; showSettings = !settings.hasConfiguredRoot
        for i in recordings.indices where ["recording", "transcribing", "summarizing"].contains(recordings[i].state) {
            if recordings[i].state != "summarizing" {
                recordings[i].transcriptComplete = false
                recordings[i].failedRanges.append("上次录音异常结束，尚未转写的内存音频已释放。")
            }
            recordings[i].state = "interrupted"; try? SessionFiles.save(recordings[i])
        }
    }
    func processing(_ id: String) -> Bool { finishingIDs.contains(id) || summarizingIDs.contains(id) || exportingIDs.contains(id) || activeID == id }
    func newNote() { guard !busy else { return }; selectedID = nil; selectedTab = 0; notice = nil }
    func nextRecording() { guard !busy else { return }; newNote(); toggleRecording() }
    func toggleRecording() { Task { if isRecording { await stop() } else { await start() } } }
    func start() async {
        guard !busy else { return }
        guard settings.modelAvailable else { notice = "未找到千问模型或本地运行组件，请检查高级设置中的模型目录。"; showSettings = true; return }
        isPreparing = true; notice = nil
        do {
            let sink = try await mic.start()
            var item = Recording(); item.title = "未命名的录音"; item.state = "recording"; item.rawDirectory = settings.rawPath
            item.mode = .automatic; item.customRoot = settings.hasConfiguredRoot ? settings.vaultPath : nil; item.sourceDevice = "macOS"
            item.transcriberModel = URL(fileURLWithPath: settings.modelPath).lastPathComponent
            item.transcriberEngine = "qwen3-asr-mlx"
            try SessionFiles.save(item)
            let id = item.id; let modelPath = settings.modelPath; let interval = settings.interval
            recordings.insert(item, at: 0); selectedID = id; activeID = id; selectedTab = 1
            modelPaths[id] = modelPath; isRecording = true; isPreparing = false; jobProgress[id] = "录音中"
            activities[id] = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "麦克风转写")
            meterTask = Task { [weak self] in
                while let self, self.activeID == id {
                    let info = await sink.snapshot(); self.level = info.1; self.mutate(id) { $0.duration = info.0 }
                    if let failure = info.2 { self.notice = failure; Task { await self.stop() }; return }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
            loopTask = Task { [weak self] in
                guard let self else { return }
                do {
                    self.jobProgress[id] = "正在加载千问 · 已开始录音"
                    try await self.transcriber.load(path: modelPath)
                    self.jobProgress[id] = "录音中"
                }
                catch { self.notice = error.localizedDescription; if self.activeID == id { Task { await self.stop() } }; return }
                while self.activeID == id {
                    if let chunk = await sink.pull(interval: interval) {
                        if !(await self.consume(chunk, id: id)) { if self.activeID == id { Task { await self.stop() } }; return }
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        } catch { await mic.stop(); isPreparing = false; notice = error.localizedDescription }
    }
    func stop() async {
        guard let id = activeID else { return }
        // Detach this round before waiting for inference. A new microphone round can start at the next await.
        let sink = mic.sink; let transcriptionLoop = loopTask
        activeID = nil; isRecording = false; loopTask = nil; meterTask?.cancel(); meterTask = nil; level = 0
        finishingIDs.insert(id); jobProgress[id] = "正在完成转写"; mutate(id) { $0.state = "transcribing" }
        await mic.stop()
        await transcriptionLoop?.value
        if let sink {
            let info = await sink.snapshot()
            mutate(id) { $0.duration = info.0; if let failure = info.2 { $0.failedRanges.append(failure) } }
            while let chunk = await sink.pull(interval: 15, force: true) { _ = await consume(chunk, id: id) }
        }
        mutate(id) { item in
            item.transcriptComplete = item.failedRanges.isEmpty; item.state = "finished"
            if !item.subjectEdited { item.subject = item.resolvedMode == .study ? LocalClassifier.classify(item.transcript) : "待分类" }
            if !item.titleEdited { item.title = "待整理的录音" }
        }
        persist(id); finishingIDs.remove(id)
        if let activity = activities.removeValue(forKey: id) { ProcessInfo.processInfo.endActivity(activity) }
        guard recordings.first(where: { $0.id == id })?.hasSpeech == true else { jobProgress[id] = "未识别到语音"; return }
        if settings.hasKey { await summarize(id: id) }
        else { jobProgress[id] = "原稿已独立保存 · 待配置 DeepSeek" }
    }
    private func consume(_ chunk: AudioChunk, id: String) async -> Bool {
        do {
            let segments = try await transcriber.transcribe(chunk, prompt: settings.vocabulary, modelPath: modelPaths[id] ?? settings.modelPath)
            mutate(id) { item in
                for var segment in segments {
                    if item.segments.contains(where: { abs($0.start - segment.start) < 0.8 && $0.text == segment.text }) { continue }
                    if let prior = item.segments.last(where: { $0.start <= segment.start }), segment.start < prior.end {
                        if segment.end <= prior.end + 0.15 { continue }
                        let n = min(prior.text.count, segment.text.count)
                        if n >= 4 {
                            for count in stride(from: n, through: 4, by: -1) where prior.text.suffix(count) == segment.text.prefix(count) {
                                segment.text = String(segment.text.dropFirst(count)).trimmingCharacters(in: .whitespacesAndNewlines); segment.start = max(segment.start, prior.end); break
                            }
                        }
                    }
                    if !segment.text.isEmpty { item.segments.append(segment) }
                }
                item.segments.sort { $0.start < $1.start }
            }
            persist(id); return true
        } catch {
            failedChunks[id, default: []].append(chunk); mutate(id) { $0.failedRanges.append("\(timestamp(chunk.start))–\(timestamp(chunk.end)) 尚未转写") }
            persist(id); notice = error.localizedDescription; return false
        }
    }
    func canRetry(_ id: String) -> Bool { !(failedChunks[id]?.isEmpty ?? true) }
    func retryMissing() {
        guard let id = selectedID, !processing(id), let chunks = failedChunks[id], !chunks.isEmpty else { return }
        Task {
            finishingIDs.insert(id); failedChunks[id] = []; mutate(id) { $0.failedRanges = [] }
            for chunk in chunks { _ = await consume(chunk, id: id) }
            mutate(id) { $0.transcriptComplete = $0.failedRanges.isEmpty }; persist(id); finishingIDs.remove(id)
            if settings.hasKey { await summarize(id: id) }
        }
    }
    func requestSummary() {
        guard let id = selectedID, !processing(id) else { return }
        summaryTasks[id] = Task { await summarize(id: id); summaryTasks[id] = nil }
    }
    private func summarize(id: String) async {
        guard var item = recordings.first(where: { $0.id == id }), item.hasSpeech, !summarizingIDs.contains(id) else { return }
        guard settings.hasConfiguredRoot || item.customRoot != nil else { showSettings = true; notice = "请先选择笔记根目录，原稿已保留。"; return }
        item.mode = .automatic; mutate(id) { $0.mode = .automatic }
        guard let key = KeychainStore.load(), !key.isEmpty else { showSettings = true; return }
        summarizingIDs.insert(id); mutate(id) { $0.state = "summarizing" }; persist(id)
        let root = URL(fileURLWithPath: item.customRoot ?? settings.vaultPath)
        var folders: [String] = []
        do { folders = try VaultFolders.list(at: root); availableFolders = folders }
        catch { notice = "无法读取仓库子目录。请在设置中重新选择 Obsidian 仓库授权；没有匹配目录时会尝试存到「未分类」。" }
        let model = settings.deepSeekModel
        let noteLinks = (try? await Task.detached(priority: .utility) {
            try KnowledgeNoteIndex.candidates(root: root, transcript: item.transcript, excluding: item.exportNote)
        }.value) ?? []
        let harness = DeepSeekHarness(configuration: HarnessConfiguration(apiKey: key, model: model, instructions: settings.instructions, folders: folders, noteLinks: noteLinks, scenes: settings.sceneDefinitions(for: root.path)))
        do {
            let result = try await harness.run(recording: item) { [self] status in await updateProgress(status, id: id) }
            mutate(id) { value in
                value.analysis = result; value.analysisModel = model; value.analyzedTranscriptHash = digest(item.transcript)
                if !value.titleEdited { value.title = result.title }
                if !value.subjectEdited { value.subject = result.subject }
                if value.folderEdited != true { value.destinationFolder = result.suggestedFolder ?? "" }
                value.state = "finished"; value.needsArchiveUpdate = true
            }
            persist(id); if selectedID == id { selectedTab = 0 }; summarizingIDs.remove(id)
            await export(id: id)
        } catch {
            summarizingIDs.remove(id); mutate(id) { $0.state = "finished" }; persist(id)
            jobProgress[id] = "整理未完成，原稿已保留"; notice = error.localizedDescription
        }
    }
    func exportSelected() { guard let id = selectedID, !processing(id) else { return }; Task { await export(id: id) } }
    private func export(id: String) async {
        guard let item = recordings.first(where: { $0.id == id }), item.analysis != nil else { return }
        exportingIDs.insert(id); jobProgress[id] = "正在归档"
        do {
            let result = try await archive.export(item, root: URL(fileURLWithPath: item.customRoot ?? settings.vaultPath), subfolder: item.destinationFolder ?? "", rawRoot: URL(fileURLWithPath: item.rawDirectory ?? settings.rawPath))
            if let i = recordings.firstIndex(where: { $0.id == id }) { recordings[i] = result }
            persist(id)
            if result.needsClassification == true {
                jobProgress[id] = "已存入未分类 · 请手动分类"
                notice = "「\(result.title)」暂未匹配到合适目录，已放入「未分类」。请在位置菜单中选择分类后更新归档。"
            } else { jobProgress[id] = "已自动归档" }
        } catch { jobProgress[id] = "归档未完成"; notice = "\(error.localizedDescription)\n原稿与整理结果已保留在本机。" }
        exportingIDs.remove(id)
    }
    func editTitle(_ value: String) { editSelected { $0.title = value; $0.titleEdited = true } }
    func editSubject(_ value: String) { editSelected { $0.subject = value; $0.subjectEdited = true } }
    func setFolder(_ value: String) { editSelected { $0.destinationFolder = value; $0.folderEdited = true } }
    func chooseNoteRoot() {
        guard let id = selectedID, !processing(id), let url = chooseFolder(prompt: "选择这篇成品的存储位置", initial: selected?.customRoot ?? settings.vaultPath) else { return }
        _ = url.startAccessingSecurityScopedResource()
        let vault = URL(fileURLWithPath: settings.vaultPath).resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        editSelected { item in
            if path == vault { item.customRoot = nil; item.destinationFolder = "" }
            else if path.hasPrefix(vault + "/") { item.customRoot = nil; item.destinationFolder = String(path.dropFirst(vault.count + 1)) }
            else { item.customRoot = path; item.destinationFolder = "" }
            item.folderEdited = true
        }
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var bookmarks = UserDefaults.standard.dictionary(forKey: "noteBookmarks") as? [String: Data] ?? [:]; bookmarks[id] = bookmark; UserDefaults.standard.set(bookmarks, forKey: "noteBookmarks")
        }
    }
    func refreshFolders() { availableFolders = (try? VaultFolders.list(at: URL(fileURLWithPath: selected?.customRoot ?? settings.vaultPath))) ?? [] }
    func revealRaw() {
        guard let item = selected, let reference = try? RawTranscriptStore.save(item, root: URL(fileURLWithPath: item.rawDirectory ?? settings.rawPath)) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([reference.manuscript])
    }
    func reveal() { if let url = exportedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    var exportedURL: URL? { guard let item = selected, let root = item.exportRoot, let note = item.exportNote else { return nil }; return URL(fileURLWithPath: root).appendingPathComponent(note) }
    func openObsidian() {
        guard let url = exportedURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/Applications/Obsidian.app"), configuration: NSWorkspace.OpenConfiguration())
    }
    func shutdown() async { for task in summaryTasks.values { task.cancel() }; await transcriber.unload() }
    private func editSelected(_ block: (inout Recording) -> Void) {
        guard let id = selectedID, !processing(id) else { return }
        mutate(id) { block(&$0); $0.needsArchiveUpdate = true }; persist(id)
    }
    private func updateProgress(_ value: String, id: String) { jobProgress[id] = value }
    private func mutate(_ id: String, _ block: (inout Recording) -> Void) { if let i = recordings.firstIndex(where: { $0.id == id }) { block(&recordings[i]) } }
    private func persist(_ id: String) {
        guard let item = recordings.first(where: { $0.id == id }) else { return }
        do {
            try SessionFiles.save(item)
            let root = URL(fileURLWithPath: item.rawDirectory ?? settings.rawPath).resolvingSymlinksInPath()
            let vault = URL(fileURLWithPath: settings.vaultPath).resolvingSymlinksInPath()
            guard root.path != vault.path, !root.path.hasPrefix(vault.path + "/") else { throw AppError.message("原稿目录不能位于 Obsidian 仓库内。") }
            _ = try RawTranscriptStore.save(item, root: root)
        } catch { notice = "原稿保存提示：\(error.localizedDescription)。识别结果仍保存在本机草稿。" }
    }
}
