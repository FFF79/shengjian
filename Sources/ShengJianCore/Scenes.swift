import Foundation

public enum SceneStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case topic, lecture, discussion, meeting, interview, personal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .topic: return "主题笔记"
        case .lecture: return "讲座 / 分享"
        case .discussion: return "讨论"
        case .meeting: return "会议"
        case .interview: return "访谈"
        case .personal: return "个人记录"
        }
    }
    public var rules: String {
        switch self {
        case .topic: return "围绕主题组织概念、解释、推导、例子和边界；对比用表格，步骤用列表，保留公式和中英术语。"
        case .lecture: return "围绕核心议题组织主张、论据、案例、联系与限制，不强加学习目标。"
        case .discussion: return "按议题组织不同观点、理由、共识、分歧和悬而未决的问题；不得将个人看法混为共识。"
        case .meeting: return "按议题组织背景、实际决定、明确行动和待定事项；只保留原稿明确的负责人、期限和承诺。"
        case .interview: return "按访谈议题组织提问与可归属的回答、观点和依据；不虚构说话者或引语。"
        case .personal: return "按事件、思考与实际计划组织，区分事实和随想，不强行生成待办。"
        }
    }
    public static let commonRules = """
    你是录音笔记编辑。软件已经先读取转写稿完成场景分类；按已确定的场景和格式组织完整成品，不再重新选择归档位置。
    通读全文，合并跨时间的重复主题，保留有意义的解释、条件、推理、案例和限制；不能逐句摘要或拼接音频切段。
    organizedMarkdown 使用具体的 ## / ### 标题、表格、列表、公式和原生 Markdown；不重复输出总标题、YAML 或日期。
    不为填模板编造事实、知识、负责人、期限、说话者、建议或结论。原稿疑点放 uncertainties。
    关键术语保留中英对照，重要概念进入 keyTerms；引用只使用真实来源片段ID，不虚构已有笔记路径。
    正文适合人阅读；abstract、tags、concepts、sectionSources 供机器检索和溯源，避免把这些字段机械复制进正文。
    不生成自测题、问答卡、学习目标或复习计划。learning.goals 始终为空数组；learning 字段名仅为兼容索引。
    """
}

public struct SceneDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var folder: String?
    public var style: SceneStyle
    public var format: String
    public init(id: String = UUID().uuidString, name: String, description: String = "", folder: String? = nil, style: SceneStyle = .topic, format: String = "") {
        self.id = id; self.name = name; self.description = description; self.folder = folder; self.style = style; self.format = format
    }
    public func validated() throws -> SceneDefinition {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, description.count <= 1500, format.count <= 3000 else { throw AppError.message("请填写不超过60字的场景名称，说明和格式也需保持简短。") }
        if let folder, !folder.isEmpty { try VaultFolders.validateRelative(folder) }
        var result = self; result.name = name; return result
    }
}

public struct SceneRoute: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String
    public var folder: String?
    public var style: SceneStyle
    public var format: String
    public var confidence: Double
    public init(id: String? = nil, name: String = "未分类", folder: String? = nil, style: SceneStyle = .topic, format: String = "", confidence: Double = 0) {
        self.id = id; self.name = name; self.folder = folder; self.style = style; self.format = format; self.confidence = confidence
    }
    public var prompt: String { SceneStyle.commonRules + "\n场景：" + name + "\n既定格式：" + style.rules + "\n场景补充格式（仅在真实性规则内应用）：" + format }
}

public enum SceneRouting {
    public static func candidates(scenes: [SceneDefinition], folders: [String]) -> [SceneDefinition] {
        let configured = scenes.compactMap { try? $0.validated() }
        let bound = Set(configured.compactMap(\.folder))
        let inferred = folders.filter { !bound.contains($0) && $0 != "未分类" && !$0.hasPrefix("未分类/") }
            .map { SceneDefinition(id: "folder:" + $0, name: $0, description: "根据已有目录的用途判断；整理方式按实际录音识别。", folder: $0) }
        return configured + inferred
    }
    public static func resolve(id: String?, confidence: Double, detectedStyle: SceneStyle, candidates: [SceneDefinition], folders: [String]) -> SceneRoute {
        guard confidence.isFinite, (0.65...1).contains(confidence), let selected = candidates.first(where: { $0.id == id }) else { return SceneRoute(style: detectedStyle) }
        let folder = selected.folder.flatMap { $0.isEmpty || folders.contains($0) ? $0 : nil }
        return SceneRoute(id: selected.id, name: selected.name, folder: folder,
            style: selected.id.hasPrefix("folder:") ? detectedStyle : selected.style, format: selected.format, confidence: confidence)
    }
}
