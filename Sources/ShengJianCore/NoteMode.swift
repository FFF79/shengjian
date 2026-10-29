import Foundation

public enum NoteMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case study, other
    public var id: String { rawValue }
    public var title: String { self == .study ? "学习" : "其他" }
}

public enum EverydayNoteStyle {
    public static let editorialRules = """
    你是个人录音记录的编辑。用户选择了「其他」，不是学习笔记。先理解整场录音的用途和交互方式，再自适应设计正文。
    把重复表述合并，按事情和观点之间的关系组织，保留细节、论据、决定、分歧与限制；不能逐句缩写或拼接时间线。
    场景判断只用于选择适合的整理方法，不是每篇必须填满的模板：
    - 讲座/分享：抓住核心议题、讲者主张、论据与案例、观点之间的联系和明确启发；不强加学习目标、自测或课本式知识点。
    - 讨论/访谈：围绕讨论的问题归纳不同观点、理由、共识、分歧和悬而未决的事项。只有原稿确实能辨认说话者时才归属观点，不能虚构人物或把不同人的看法混为共识。
    - 会议/协作：提炼议题、实际决定和行动。只有录音明确提到时才写负责人、时间、承诺；建议不等于决定，计划不等于已经完成。
    - 日常口述/随想：按事件经过、个人思考、具体计划等自然逻辑组织；不把零散想法包装成确定结论或强行生成待办。
    正文 organizedMarkdown 直接输出完整成品，用具体的 ##、### 主题标题，必要时用表格、列表、引用、代码或公式；不要额外总标题、YAML、日期和软件来源套壳。
    结构必须服务本稿，有哪些内容就写哪些，不为填模板补写事实、建议、日期、人物、例子或行动事项。保留重要中英术语。
    重复主题跨时间合并，原稿疑似错词、矛盾或含糊内容进入 uncertainties，不得默默猜成事实。
    不生成自测题、问答卡、学习目标或复习计划。learning.goals 必须为空数组，其他索引与来源字段正常填写。
    context 从 lecture、discussion、meeting、personal、interview、other 中选择最接近的场景，软件据此标为讲座、讨论、会议、日常记录、访谈。无法判断用 other，暂存未分类。
    其他模式以场景标签为归档首要依据，优先匹配相应讲座/讨论/会议/日常记录/访谈目录及其主题子目录。没有相应类别目录时 suggestedFolder 返回空字符串；不能仅因提到物理等词就塞进学习学科目录。subject 输出场景标签，具体主题放 title/tags。
    使用 Obsidian 原生 Markdown。重要概念、人物、项目可作为 keyTerms，软件依据已有笔记生成双向链接；不得编造文件路径。
    """
}

public enum RecordingContext: String, CaseIterable, Sendable {
    case lecture, discussion, meeting, personal, interview, other
    public var title: String {
        switch self { case .lecture: return "讲座"; case .discussion: return "讨论"; case .meeting: return "会议"; case .personal: return "日常记录"; case .interview: return "访谈"; case .other: return "未分类" }
    }
    public func matches(folder: String) -> Bool {
        let aliases: [String]
        switch self {
        case .lecture: aliases = ["讲座", "演讲", "分享", "lecture", "talks"]
        case .discussion: aliases = ["讨论", "交流", "对谈", "聊天", "discussion", "conversation"]
        case .meeting: aliases = ["会议", "会谈", "meeting"]
        case .personal: aliases = ["日常", "生活", "随想", "随记", "个人", "journal", "memo"]
        case .interview: aliases = ["访谈", "采访", "interview"]
        case .other: return false
        }
        return aliases.contains { folder.localizedCaseInsensitiveContains($0) }
    }
}
