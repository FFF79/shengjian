import SwiftUI

struct LocalASRSetupView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var installer: ASRInstaller
    var blocked = false
    var body: some View {
        Section("本地转写组件") {
            Text(settings.modelAvailable || installer.succeeded ? "千问本地组件已就绪" : "首次使用需下载千问模型与独立运行环境")
            Text("Apple Silicon · 无需 Xcode、Homebrew 或预装 Python。模型约2.46 GB，另需运行组件和临时下载空间。下载公开依赖与模型，不上传录音。").font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                if installer.running { ProgressView().controlSize(.small) }
                Button(installer.running ? "正在安装…" : "安装 / 修复本地转写组件") { installer.start() }.disabled(installer.running || blocked)
            }
            if !installer.status.isEmpty { Text(installer.status).font(.system(size: 10)).foregroundStyle(installer.succeeded ? Color.green : .secondary).textSelection(.enabled) }
            if !installer.log.isEmpty {
                DisclosureGroup("安装详情") { ScrollView { Text(installer.log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 100) }
            }
        }.onChange(of: installer.succeeded) { _, ready in if ready { settings.modelPath = QwenRuntime.modelDirectory.path } }
    }
}
