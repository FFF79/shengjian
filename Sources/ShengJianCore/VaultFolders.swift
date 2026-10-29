import Foundation

public enum VaultFolders {
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
