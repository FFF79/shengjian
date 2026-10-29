import SwiftUI
import ShengJianCore

struct SceneEditor: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SceneDefinition
    @State private var folder: String
    @State private var folders: [String] = []
    @State private var newFolder = ""
    @State private var message = ""
    init(settings: SettingsStore, scene: SceneDefinition) {
        self.settings = settings; _draft = State(initialValue: scene); _folder = State(initialValue: scene.folder ?? "__none__")
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("场景与归档规则").font(.title3)
                Spacer(); Button("取消") { dismiss() }
                Button("保存") {
                    do { draft.folder = folder == "__none__" ? nil : folder; try settings.saveScene(draft); dismiss() }
                    catch { message = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(22)
            Divider()
            Form {
                Section("自动识别") {
                    TextField("场景名称，例如 产品评审", text: $draft.name)
                    TextField("识别线索，例如 讨论需求、设计取舍与评审结论", text: $draft.description)
                }
                Section("归档位置 · 相对所选根目录") {
                    Picker("绑定文件夹", selection: $folder) {
                        Text("未绑定 · 暂存未分类").tag("__none__")
                        Text("根目录").tag("")
                        ForEach(folders, id: \.self) { Text($0).tag($0) }
                        if let missing = draft.folder, !missing.isEmpty, !folders.contains(missing) { Text(missing + "（不可用）").tag(missing) }
                    }
                    HStack {
                        TextField("新目录，例如 工作/产品评审", text: $newFolder)
                        Button("创建并绑定") {
                            do { folder = try settings.createFolder(newFolder); folders = settings.sceneFolders; newFolder = ""; message = "" }
                            catch { message = error.localizedDescription }
                        }.disabled(newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("既定整理格式") {
                    Picker("基础结构", selection: $draft.style) { ForEach(SceneStyle.allCases) { Text($0.title).tag($0) } }
                    Text(draft.style.rules).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("补充要求（可选）").font(.system(size: 11))
                    TextEditor(text: $draft.format).font(.system(size: 12)).frame(height: 80)
                    Text("例如：先写评审结论，再按议题列依据、分歧与明确行动。所有格式共享 YAML、来源片段和检索索引；不补造原稿没有的事实。").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(.orange) }
            }.formStyle(.grouped)
        }.frame(width: 570, height: 590).tint(Color(red: 0.19, green: 0.39, blue: 0.30)).preferredColorScheme(.light)
        .onAppear { folders = settings.sceneFolders }
    }
}
