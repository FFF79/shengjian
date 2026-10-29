import AppKit
import SwiftUI
import ShengJianCore

private let ink = Color(red: 0.13, green: 0.18, blue: 0.16)
private let accent = Color(red: 0.19, green: 0.39, blue: 0.30)
private let paper = Color(red: 0.975, green: 0.973, blue: 0.957)

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    var showFloating: () -> Void
    @State private var history = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "waveform").foregroundStyle(accent)
                Text("声笺").font(.system(size: 15, weight: .medium))
                if model.selectedID != nil { Button("新录音", systemImage: "plus", action: model.newNote).font(.system(size: 11)).disabled(model.busy) }
                Spacer()
                if model.processingCount > 0 { Text("\(model.processingCount) 篇后台处理中").font(.system(size: 10)).foregroundStyle(.secondary) }
                Button { history.toggle() } label: { Image(systemName: "clock") }.help("最近记录")
                    .popover(isPresented: $history) { historyView }
                Button(action: showFloating) { Image(systemName: "rectangle.on.rectangle") }.help("悬浮窗")
                Button { model.showSettings = true } label: { Image(systemName: "gearshape") }.help("设置")
            }.buttonStyle(.borderless).font(.system(size: 13)).padding(.horizontal, 27).frame(height: 52)
            Divider().opacity(0.4)
            if let note = model.selected { noteView(note) } else { welcome }
            if let notice = model.notice {
                HStack(alignment: .top) {
                    Text(notice).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer(minLength: 6)
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(14).background(.orange.opacity(0.07))
            }
            bottomAction
        }
        .background(paper).foregroundStyle(ink).tint(accent).preferredColorScheme(.light)
        .sheet(isPresented: $model.showSettings, onDismiss: model.refreshFolders) { SettingsView(settings: settings).frame(width: 550, height: 560) }
        .frame(minWidth: 640, minHeight: 540)
    }
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("开始一段录音").font(.system(size: 25, weight: .medium))
                    Text("先选择学习或其他，结束后自动整理并归档。").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.top, 18)
                if !model.recordings.isEmpty {
                    HStack { Text("最近记录").font(.system(size: 12, weight: .semibold)); Spacer(); Button("全部记录") { history = true }.buttonStyle(.borderless).font(.system(size: 11)) }
                    VStack(spacing: 0) {
                        ForEach(Array(model.recordings.prefix(3))) { note in
                            Button { model.selectedID = note.id; model.selectedTab = note.analysis == nil ? 1 : 0; model.refreshFolders() } label: {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        Text(note.classificationDisplay).font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                                        Label(note.archivedFolderDisplay.map { "保存于 " + $0 } ?? "尚未归档", systemImage: "folder")
                                            .font(.system(size: 10)).foregroundStyle(note.needsClassification == true ? Color.orange : .secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer(minLength: 6)
                                    VStack(alignment: .trailing, spacing: 9) {
                                        Text(note.createdAt, format: .dateTime.month().day().hour().minute()).foregroundStyle(.secondary)
                                        Text(model.processing(note.id) ? "处理中" : note.needsClassification == true ? "待手动分类" : note.exportNote != nil ? "已归档" : "待整理")
                                            .foregroundStyle(note.needsClassification == true ? Color.orange : .secondary)
                                    }.font(.system(size: 10))
                                }.padding(.vertical, 15).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider().opacity(0.35)
                        }
                    }
                }
            }.frame(maxWidth: 550, alignment: .leading).padding(.horizontal, 28).padding(.bottom, 20).frame(maxWidth: .infinity)
        }
    }
    private func noteView(_ note: Recording) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if model.activeID == note.id {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text(timestamp(note.duration)).font(.system(size: 24, weight: .light, design: .monospaced))
                        WaveBars(level: model.level, active: true).frame(width: 65, height: 28)
                    } else {
                        Text(note.createdAt, format: .dateTime.month().day().hour().minute()).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("· " + timestamp(note.duration)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Text(note.recordingLabel).font(.system(size: 10)).foregroundStyle(accent)
                    Spacer()
                    Menu {
                        Menu("整理方式：" + note.resolvedMode.title) {
                            ForEach(NoteMode.allCases) { mode in Button(mode.title) { model.changeMode(mode) } }
                        }.disabled(model.processing(note.id))
                        Button("重新整理", action: model.requestSummary).disabled(model.processing(note.id) || !note.hasSpeech)
                        Button("查看独立原稿", action: model.revealRaw)
                        if note.exportNote != nil { Button("在 Obsidian 中打开", action: model.openObsidian); Button("在访达中显示", action: model.reveal) }
                        if model.canRetry(note.id) { Button("重试缺失片段", action: model.retryMissing).disabled(model.processing(note.id)) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }
                if model.activeID != note.id {
                    TextField("主题", text: Binding(get: { model.selected?.title ?? "" }, set: model.editTitle))
                        .textFieldStyle(.plain).font(.system(size: 23, weight: .medium)).disabled(model.processing(note.id))
                }
                if note.analysis != nil {
                    HStack(spacing: 8) {
                        if note.resolvedMode == .study { Menu {
                            ForEach(LocalClassifier.subjects, id: \.self) { subject in Button(subject) { model.editSubject(subject) } }
                            Button("自定义学科…") { customSubject() }
                        } label: { Text(note.subject) }.menuStyle(.borderlessButton).fixedSize()
                        Text("·").foregroundStyle(.tertiary) }
                        Menu {
                            Button("仓库根目录") { model.setFolder("") }
                            ForEach(model.availableFolders, id: \.self) { folder in Button(folder) { model.setFolder(folder) } }
                            Divider(); Button("选择其他位置…", action: model.chooseNoteRoot)
                        } label: { Label(folderLabel(note), systemImage: "folder") }.menuStyle(.borderlessButton).fixedSize()
                        Spacer(minLength: 0)
                        if note.exportNote != nil && note.needsArchiveUpdate != true { Text(note.needsClassification == true ? "待手动分类" : "已归档").foregroundStyle(note.needsClassification == true ? .orange : accent) }
                    }.font(.system(size: 11)).foregroundStyle(.secondary).disabled(model.processing(note.id))
                }
            }.padding(.horizontal, 29).padding(.top, 24).padding(.bottom, 19)
            if note.needsClassification == true {
                HStack { Text("这篇暂存「未分类」，请手动选择位置。"); Spacer(); Button("选择位置…", action: model.chooseNoteRoot) }
                    .font(.system(size: 11)).padding(.horizontal, 29).padding(.bottom, 14).foregroundStyle(.orange)
            }
            HStack(spacing: 20) {
                ForEach(Array(["整理稿", "原转录稿"].enumerated()), id: \.offset) { index, label in
                    Button { model.selectedTab = index } label: {
                        VStack(spacing: 10) {
                            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(model.selectedTab == index ? ink : .secondary)
                            Rectangle().fill(model.selectedTab == index ? accent : .clear).frame(height: 2)
                        }
                    }.buttonStyle(.plain)
                }
                Spacer()
                if model.processing(note.id) { ProgressView().controlSize(.mini); Text(model.jobProgress[note.id] ?? "处理中").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 29)
            Divider().opacity(0.35)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        if !note.failedRanges.isEmpty { Text("转写存在缺失：" + note.failedRanges.joined(separator: "；")).font(.system(size: 11)).foregroundStyle(.orange) }
                        if model.selectedTab == 1 {
                            if note.segments.isEmpty { Text(model.activeID == note.id ? "正在聆听…" : "等待转写结果").foregroundStyle(.tertiary).padding(.top, 15) }
                            ForEach(note.segments) { segment in
                                HStack(alignment: .top, spacing: 16) {
                                    Text(timestamp(segment.start)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 42).padding(.top, 3)
                                    Text(segment.text).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }.id(segment.id)
                            }
                        } else if let analysis = note.analysis {
                            if note.summaryIsStale { Text("原稿已更新，请重新整理。").foregroundStyle(.orange) }
                            StudyNoteView(markdown: analysis.documentBody, vaultPath: note.customRoot ?? settings.vaultPath)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(model.processing(note.id) ? "这篇正在后台处理。" : "原稿已独立保存。").font(.system(size: 17))
                                Text(model.processing(note.id) ? "你可以直接开始下一轮录音。" : "配置 DeepSeek 后，即可生成整理稿并自动归档。").font(.system(size: 12)).foregroundStyle(.secondary)
                                if !model.processing(note.id) {
                                    Button(settings.hasKey ? "整理原稿" : "设置 DeepSeek") { if settings.hasKey { model.requestSummary() } else { model.showSettings = true } }.buttonStyle(.bordered)
                                }
                            }.padding(.top, 20)
                        }
                    }.padding(29).frame(maxWidth: .infinity, alignment: .leading)
                }.onChange(of: note.segments.count) { _, _ in
                    if model.activeID == note.id, let last = note.segments.last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }.onAppear { model.refreshFolders() }
    }
    private var bottomAction: some View {
        VStack(spacing: 11) {
            if !model.isRecording && !model.isPreparing {
                HStack(spacing: 9) {
                    if model.selected != nil { Text("下一轮").font(.system(size: 10)).foregroundStyle(.secondary) }
                    Picker("整理方式", selection: $settings.noteMode) {
                        ForEach(NoteMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 166)
                }
            }
            HStack {
                Spacer()
                if model.isRecording {
                    Button("结束录音", action: model.toggleRecording).buttonStyle(.borderedProminent).tint(ink)
                } else if model.isPreparing {
                    ProgressView().controlSize(.small); Text("正在准备麦克风…").font(.system(size: 12)).foregroundStyle(.secondary)
                } else if model.selected?.summaryIsStale == true, !model.selectedProcessing {
                    Button("重新整理", action: model.requestSummary).buttonStyle(.borderedProminent)
                    Button("开始下一轮", action: model.nextRecording).buttonStyle(.borderless)
                } else if model.selected?.needsArchiveUpdate == true, model.selected?.analysis != nil, !model.selectedProcessing {
                    Button("更新归档", action: model.exportSelected).buttonStyle(.borderedProminent)
                    Button("开始下一轮", action: model.nextRecording).buttonStyle(.borderless)
                } else {
                    Button(model.selected == nil ? "开始录音" : "开始下一轮录音", action: model.nextRecording).buttonStyle(.borderedProminent)
                }
                Spacer()
            }.controlSize(.large)
            Text(model.isRecording ? "音频不保存 · 文字在本机转写" : "本地转写 · 原稿独立保存 · 成品自动归档")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }.padding(.vertical, 22)
    }
    private var historyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近记录").font(.system(size: 13, weight: .semibold))
            if model.recordings.isEmpty { Text("还没有记录").font(.system(size: 11)).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(model.recordings) { note in
                        Button { model.selectedID = note.id; model.selectedTab = note.analysis == nil ? 1 : 0; history = false; model.refreshFolders() } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.title).font(.system(size: 12)).lineLimit(2)
                                Text(note.classificationDisplay).font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                                Label(note.archivedFolderDisplay.map { "保存于 " + $0 } ?? "尚未归档", systemImage: "folder")
                                    .font(.system(size: 10)).foregroundStyle(note.needsClassification == true ? Color.orange : .secondary).lineLimit(2)
                                HStack {
                                    Text(note.createdAt, format: .dateTime.month().day().hour().minute())
                                    Spacer()
                                    Text(model.processing(note.id) ? (model.jobProgress[note.id] ?? "处理中") : note.needsClassification == true ? "待手动分类" : note.exportNote != nil ? "已归档" : "待归档")
                                }.font(.system(size: 10)).foregroundStyle(.secondary)
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: 420)
        }.padding(18).frame(width: 355)
    }
    private func folderLabel(_ note: Recording) -> String {
        if let custom = note.customRoot { return URL(fileURLWithPath: custom).lastPathComponent + (note.destinationFolder?.isEmpty == false ? "/" + note.destinationFolder! : "") }
        return note.destinationFolder?.isEmpty == false ? note.destinationFolder! : "仓库根目录"
    }
    private func markdown(_ text: String) -> some View {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .font(.system(size: 14)).lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func customSubject() {
        let alert = NSAlert(); alert.messageText = "学科"; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 230, height: 25)); field.stringValue = model.selected?.subject ?? ""; alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn, !safeComponent(field.stringValue).isEmpty { model.editSubject(safeComponent(field.stringValue)) }
    }
}

struct WaveBars: View {
    let level: Float
    let active: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { context in
            HStack(spacing: 3) {
                ForEach(0..<12) { index in
                    let wave = abs(sin(context.date.timeIntervalSinceReferenceDate * 5 + Double(index) * 0.8))
                    Capsule().fill(accent.opacity(active ? 0.8 : 0.25)).frame(width: 3, height: active ? 4 + CGFloat(level) * (7 + wave * 20) : 4)
                }
            }.frame(maxHeight: .infinity)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var message = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("设置").font(.system(size: 19, weight: .medium)); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(23)
            Divider()
            Form {
                Section("存储位置") {
                    HStack { VStack(alignment: .leading, spacing: 5) { Text("Obsidian 成品仓库"); Text(settings.vaultPath).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Button("选择…", action: settings.chooseVault) }
                    HStack { VStack(alignment: .leading, spacing: 5) { Text("独立原稿目录"); Text(settings.rawPath).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Button("选择…") { message = settings.chooseRawDirectory() ?? "" } }
                    Text("模型从已有学科目录中选择位置并自动归档。原转录稿不进入 Obsidian。").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Section("DeepSeek") {
                    HStack {
                        SecureField(settings.hasKey ? "已配置密钥，可输入新密钥替换" : "填写 API Key", text: $key)
                        Button("保存") {
                            do { try KeychainStore.save(key); settings.hasKey = true; key = ""; message = "密钥已安全保存。" }
                            catch { message = error.localizedDescription }
                        }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("仅发送转写文字，用于整理、学科判断和目录匹配。").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                DisclosureGroup("高级设置") {
                    Picker("DeepSeek 模型", selection: $settings.deepSeekModel) {
                        Text("DeepSeek V4.1 Flash").tag("deepseek-flash")
                        Text("DeepSeek V4 Pro").tag("deepseek-v4-pro")
                    }
                    Text("API 标识：" + settings.deepSeekModel).font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack { Text(settings.modelAvailable ? "千问 Qwen3-ASR 1.7B · 已就绪" : "千问本地组件未就绪"); Spacer(); Button("模型目录…", action: settings.chooseModel) }
                    TextField("专业术语提示", text: $settings.vocabulary)
                    HStack { Text("转写分段"); Slider(value: $settings.interval, in: 6...25, step: 1); Text("\(Int(settings.interval))秒").monospacedDigit() }
                    Text("整理要求").font(.system(size: 11))
                    TextEditor(text: $settings.instructions).font(.system(size: 11)).frame(height: 65)
                    if settings.hasKey { Button("移除 DeepSeek 密钥") { KeychainStore.delete(); settings.hasKey = false; message = "密钥已移除。" } }
                }
                if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(accent) }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
        }.background(paper).foregroundStyle(ink).tint(accent).preferredColorScheme(.light)
    }
}

struct FloatingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: FloatingPresentation
    private var collapsed: Bool { presentation.collapsed }
    var expand: () -> Void
    var collapse: () -> Void
    var hide: () -> Void
    var openMain: () -> Void
    var body: some View {
        Group {
            if collapsed {
                Button(action: expand) {
                    VStack(spacing: 13) {
                        Image(systemName: model.isRecording ? "waveform" : "mic").font(.system(size: 19))
                        if model.isRecording { Circle().fill(.red).frame(width: 5, height: 5) }
                        Text(model.active.map { timestamp($0.duration) } ?? "声笺").font(.system(size: 9, design: .monospaced))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label("声笺", systemImage: "waveform").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Button(action: openMain) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("打开主窗口")
                        Button(action: collapse) { Image(systemName: "sidebar.right") }.help("收起到屏幕边缘")
                        Button(action: hide) { Image(systemName: "xmark").frame(width: 18, height: 18).contentShape(Rectangle()) }.help("隐藏悬浮窗")
                    }.buttonStyle(.plain).foregroundStyle(ink.opacity(0.7))
                    HStack(spacing: 13) {
                        WaveBars(level: model.level, active: model.isRecording).frame(width: 68, height: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.active.map { timestamp($0.duration) } ?? "准备就绪").font(.system(size: 19, weight: .light, design: .monospaced))
                            Text(model.isRecording ? "麦克风 · 本地转写" : model.isPreparing || model.isFinishing || model.summarizingID != nil ? model.progress : "不保存音频").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button(action: model.toggleRecording) {
                            Image(systemName: model.isRecording ? "stop.fill" : "mic.fill").font(.system(size: 15)).foregroundStyle(model.isRecording ? Color.white : accent).frame(width: 39, height: 39)
                                .background(model.isRecording ? Color.red.opacity(0.85) : Color.white.opacity(0.6), in: Circle())
                        }.buttonStyle(.plain).disabled(!model.isRecording && model.busy)
                    }
                    if model.isRecording {
                        Text(model.active?.segments.last?.text ?? "正在聆听，文字将在短暂停顿后出现…").font(.system(size: 11)).foregroundStyle(ink.opacity(0.8)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(18).frame(width: 325)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()).background(Color.white.opacity(0.01))
            .foregroundStyle(ink).background { glass }.clipShape(RoundedRectangle(cornerRadius: collapsed ? 18 : 23)).padding(3)
            .contextMenu { Button("隐藏悬浮窗", action: hide); Button("打开主窗口", action: openMain) }
            .preferredColorScheme(.light)
    }
    @ViewBuilder private var glass: some View {
        if #available(macOS 26, *) { RoundedRectangle(cornerRadius: collapsed ? 18 : 23).fill(.clear).glassEffect(.regular, in: .rect(cornerRadius: collapsed ? 18 : 23)) }
        else { RoundedRectangle(cornerRadius: collapsed ? 18 : 23).fill(.ultraThinMaterial) }
    }
}
