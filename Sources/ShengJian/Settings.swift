import AppKit
import SwiftUI
import Security
import LocalAuthentication
import ShengJianCore

@MainActor final class SettingsStore: ObservableObject {
    @Published var vaultPath: String { didSet { defaults.set(vaultPath, forKey: "vaultPath") } }
    @Published var rawPath: String { didSet { defaults.set(rawPath, forKey: "rawPath") } }
    @Published var modelPath: String { didSet { defaults.set(modelPath, forKey: "qwenModelPath") } }
    @Published var deepSeekModel: String { didSet { defaults.set(deepSeekModel, forKey: "deepSeekModel") } }
    @Published var instructions: String { didSet { defaults.set(instructions, forKey: "instructions") } }
    @Published var vocabulary: String { didSet { defaults.set(vocabulary, forKey: "vocabulary") } }
    @Published var interval: Double { didSet { defaults.set(interval, forKey: "interval") } }
    @Published var hasKey: Bool
    @Published var noteMode: NoteMode { didSet { defaults.set(noteMode.rawValue, forKey: "noteMode") } }
    private let defaults = UserDefaults.standard
    private var accessed: [URL] = []

    init() {
        let d = UserDefaults.standard
        noteMode = NoteMode(rawValue: d.string(forKey: "noteMode") ?? "") ?? .study
        vaultPath = d.string(forKey: "vaultPath") ?? Self.discoverVault() ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents").path
        rawPath = d.string(forKey: "rawPath") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/声笺原稿").path
        modelPath = d.string(forKey: "qwenModelPath") ?? QwenRuntime.modelDirectory.path
        let storedModel = d.string(forKey: "deepSeekModel") ?? "deepseek-flash"
        deepSeekModel = ["deepseek-flash", "deepseek-v4-pro"].contains(storedModel) ? storedModel : "deepseek-flash"
        instructions = d.string(forKey: "instructions") ?? "突出关键概念、推导过程和例子。保留中英双语专业术语。不要扩写原稿未提及的知识。"
        vocabulary = d.string(forKey: "vocabulary") ?? ""
        interval = d.object(forKey: "interval") as? Double ?? 10
        hasKey = KeychainStore.containsKey()
        for name in ["vaultBookmark", "rawBookmark"] { if let data = d.data(forKey: name) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() { accessed.append(url) }
        } }
    }
    static func discoverVault() -> String? {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
        guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let vaults = object["vaults"] as? [String: [String: Any]] else { return nil }
        return (vaults.values.first { $0["open"] as? Bool == true } ?? vaults.values.first)?["path"] as? String
    }
    func chooseVault() {
        if let url = chooseFolder(prompt: "选择 Obsidian 仓库或存储目录", initial: vaultPath) {
            if url.startAccessingSecurityScopedResource() { accessed.append(url) }
            if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) { defaults.set(bookmark, forKey: "vaultBookmark") }
            vaultPath = url.path
        }
    }
    func chooseModel() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.message = "选择已下载的 Qwen3-ASR MLX 模型文件夹（包含 config.json 和 model.safetensors）"
        if panel.runModal() == .OK, let url = panel.url { modelPath = url.path }
    }
    func chooseRawDirectory() -> String? {
        guard let url = chooseFolder(prompt: "选择 Obsidian 之外的原稿目录", initial: rawPath) else { return nil }
        let raw = url.resolvingSymlinksInPath().path
        let vault = URL(fileURLWithPath: vaultPath).resolvingSymlinksInPath().path
        guard raw != vault, !raw.hasPrefix(vault + "/") else { return "原稿目录必须位于 Obsidian 仓库之外。" }
        if url.startAccessingSecurityScopedResource() { accessed.append(url) }
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) { defaults.set(bookmark, forKey: "rawBookmark") }
        rawPath = url.path; return nil
    }
    var modelAvailable: Bool { QwenRuntime.isAvailable(modelPath: modelPath) }
}

@MainActor func chooseFolder(prompt: String, initial: String? = nil) -> URL? {
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false; panel.message = prompt; panel.prompt = "选择此目录"
    if let initial { panel.directoryURL = URL(fileURLWithPath: initial) }
    return panel.runModal() == .OK ? panel.url : nil
}

enum KeychainStore {
    private static let service = "org.shengjian.deepseek"
    static func containsKey() -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key",
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    static func load(interactionAllowed: Bool = true) -> String? {
        // The login keychain can use legacy ACL prompts even with a noninteractive LAContext.
        var previousInteraction = DarwinBoolean(true)
        if !interactionAllowed {
            SecKeychainGetUserInteractionAllowed(&previousInteraction)
            SecKeychainSetUserInteractionAllowed(false)
        }
        defer { if !interactionAllowed { SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) } }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if !interactionAllowed { let context = LAContext(); context.interactionNotAllowed = true; query[kSecUseAuthenticationContext as String] = context }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        let data = Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw AppError.message("无法将密钥保存到 macOS 钥匙串。") }; return
        }
        guard status == errSecSuccess else { throw AppError.message("无法更新 macOS 钥匙串中的密钥。") }
    }
    static func delete() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
}
