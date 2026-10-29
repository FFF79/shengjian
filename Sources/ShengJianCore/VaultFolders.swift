import Foundation

public enum VaultFolders {
    public static func validateRelative(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), parts.count <= 4,
              parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && !["_声笺", "_agent"].contains(String($0)) && !$0.hasSuffix(".app") && $0.count <= 100 && !$0.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }) })
        else { throw AppError.message("请输入根目录内的相对文件夹名称，最多4层；不能包含隐藏目录、.. 或绝对路径。") }
    }
    /// Only a deliberate user action creates category folders; the model never calls this API.
    public static func create(_ path: String, at root: URL) throws -> String {
        try validateRelative(path)
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw AppError.message("请先选择可访问的笔记根目录。") }
        var parent = root
        for component in path.split(separator: "/") {
            parent.appendPathComponent(String(component))
            if FileManager.default.fileExists(atPath: parent.path) {
                let values = try parent.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard values.isSymbolicLink != true, values.isDirectory == true else { throw AppError.message("目标包含符号链接或同名文件，请选择其他名称。") }
            }
            guard parent.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { throw AppError.message("目标超出所选根目录。") }
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return path
    }
    /// Inspect directory names only. Note contents are never sent to the model.
    public static func list(at root: URL) throws -> [String] {
        let fm = FileManager.default
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var result: [String] = []
        func walk(_ parent: URL, depth: Int) throws {
            guard depth < 4, result.count < 400 else { return }
            let children = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = child.lastPathComponent
                guard !["_声笺", "_agent", "_原稿", "_学科索引", "_附件", "attachments", "node_modules"].contains(name), !name.hasSuffix(".app") else { continue }
                let info = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isDirectory == true, info.isSymbolicLink != true else { continue }
                guard result.count < 400 else { break }
                let canonical = child.standardizedFileURL.resolvingSymlinksInPath()
                guard canonical.path.hasPrefix(root.path + "/") else { continue }
                result.append(canonical.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/"))
                try walk(canonical, depth: depth + 1)
            }
        }
        try walk(root, depth: 0)
        return result
    }
}
