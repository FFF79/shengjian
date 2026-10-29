# 声笺 · ShengJian

[简体中文](README.md) · [English](README.en.md)

**把麦克风录音变成可阅读、可关联、可检索的 Obsidian 笔记。**

声笺是面向 Apple Silicon Mac 的原生应用：用本地千问识别中英混合语音，再由 DeepSeek 按内容重新组织笔记、判断分类并归档。应用不保存音频文件；原始转录稿独立保存于知识库之外。

> 当前发布的是 **macOS 源码版**，界面为中文；需要 macOS 26+、Apple Silicon、完整 Xcode 和本地模型。整理使用你自己的 DeepSeek API Key，产生的 API 费用由你承担。不包含手机版、预装模型或已公证安装包。

## 能做什么

- **录音 → 转写 → 整理 → 归档**，首页显示最近记录的分类、实际保存目录和状态。
- **学习 / 其他** 两种录音模式。学习按科目组织；其他自动识别讲座、讨论、会议、访谈、日常口述，使用适合场景的结构。
- **本地中英混合识别**：Qwen3-ASR 1.7B 的 MLX 8-bit 版本，无需转写 API Key。
- **玻璃悬浮窗**：拖动、靠边收起、点击展开、隐藏，也可从菜单栏恢复。
- **连续录音**：上一轮仍在完成转写或整理时，可以开始下一轮。
- **自动归档**：匹配已有科目或场景目录；不匹配则进入「未分类」并提醒手动调整。标题、分类、目录可修改。
- **Obsidian 原生 Markdown**：YAML 属性、双向链接、表格、公式、callout；不依赖社区插件。
- **Agent 检索索引**：稳定记录 ID、主题段落、概念、来源片段、独立 JSON/JSONL 索引。

整理按主题保留解释、推导、案例和条件，不逐句改写，不生成自测题。模型不确定的内容保留待核对标记。

## 从源码安装

### 1. 准备环境

- Apple Silicon Mac，macOS 26 或更新版本。建议至少 16 GB 内存；实际内存占用与速度取决于机型和录音长度。
- 完整 Xcode，包含兼容的 macOS SDK；仅安装 Command Line Tools 不足以构建此应用。
- Python 3 和 [uv](https://docs.astral.sh/uv/getting-started/installation/)。安装脚本会创建独立 Python 3.12 环境。
- 初次下载模型和依赖需要联网。权重约 2.46 GB，另需 Python 运行环境、依赖及下载临时空间。

若使用 Homebrew，可安装构建辅助工具：

```sh
brew install uv python
```

### 2. 下载、安装组件、构建

```sh
git clone https://github.com/FFF79/shengjian.git
cd shengjian
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 scripts/setup_qwen.py
python3 scripts/build_app.py --install
open "$HOME/Applications/声笺.app"
```

Xcode 若在其他位置，请将 `DEVELOPER_DIR` 指向实际路径。构建脚本生成 `dist/声笺.app`；`--install` 另安装到 `~/Applications/声笺.app`。默认使用临时本地签名，未公证。

安装器固定模型 revision 和 Python 依赖版本，并验证权重 SHA-256。模型存于 `~/Library/Application Support/声笺/ASR/`，不放入 Git，也不重复打包到应用。下载失败后可重新运行安装器以续传；如校验失败，应重新获取权重，不要跳过校验。

### 3. 首次配置

打开设置并选择：

1. **Obsidian 仓库**：选择你自己的仓库根目录。应用会尝试发现本机已注册仓库，仍请核对并确认位置。
2. **独立原稿目录**：默认 `~/Documents/声笺原稿`，必须在 Obsidian 仓库之外。
3. **DeepSeek API Key**：在应用内输入，保存到 macOS 钥匙串。不要写入源码、笔记或 Issue。

默认整理模型是 `deepseek-flash`，设置中也可选择 `deepseek-v4-pro`。可用模型和计费以 [DeepSeek 官方文档](https://api-docs.deepseek.com/quick_start/pricing/) 为准。尚未设置密钥时仍可本地转写，之后再整理。

先选「学习 / 其他」，点击「开始录音」，按系统提示允许麦克风访问；结束时点击「结束录音」。成品自动归档，未匹配的科目/场景会进入「未分类」。应用只自动创建这个兜底目录，其他分类目录请自行创建。

## 隐私与数据去向

| 数据 | 去向 |
| --- | --- |
| 麦克风音频 | 应用内存 → 本机 Python 进程管道 → 本地千问；应用不写音频文件、不向 DeepSeek 上传音频 |
| 原始转录稿 | 独立原稿目录，以及本机恢复草稿 |
| 整理请求 | 转录文字、整理偏好、已有目录名称、候选笔记的标题/相对路径/别名发送到 DeepSeek |
| 既有笔记正文 | 不作为关联检索资料发送；关联匹配只读取文件名及本地可读的 YAML 标题/别名 |
| 整理成品与索引 | 所选 Obsidian 仓库；仓库所在的 iCloud/同步服务可能同步这些文件 |
| API Key | macOS 钥匙串；通过 HTTPS Authorization 头发送至 DeepSeek |

本地识别进程设置离线模式，不启动本地监听服务。安装阶段会访问 Python 包源、Hugging Face / ModelScope 下载依赖和模型。应用无内置分析统计服务；并不承诺操作系统、云同步或第三方 API 的数据保留政策。

识别是**分段近实时**，按停顿或片段长度触发，并有推理延迟；不是逐字流式字幕。时间戳是录音片段边界，非逐词对齐。应用不保存音频，崩溃、断电或退出后无法恢复尚未识别的声音；已经识别的文字保留。AI 输出仍需核对。

本机恢复草稿和整理检查点位于 `~/Library/Application Support/声笺/Sessions/`。不保存音频不等于不保存文字。笔记及索引可能含原稿绝对路径，分享文件或提交 Issue 前请脱敏。

## 存储结构与检索

文件名包含时间、分类和核心主题，例如 `2026-10-29 09-30-00｜物理｜牛顿第二定律.md`。

```text
独立原稿目录/                 # 仓库之外，未经 DeepSeek 改写
├── 时间｜原转录稿｜短ID.md
└── .声笺/chunks/<ID>.jsonl

Obsidian 仓库/
├── 物理/时间｜物理｜主题.md
├── 未分类/
└── _声笺/
    ├── 索引.md
    ├── 学科索引/
    └── agent/
        ├── README.md
        ├── records/<ID>.json
        ├── sections/<ID>.jsonl
        ├── learning/<ID>.json
        ├── catalog.jsonl
        └── sections.jsonl
```

Agent 先读仓库中生成的 `_声笺/agent/README.md`，优先使用每篇独立索引，再定位成品和来源片段。总 JSONL 是合并视图；跨设备同步可能暂时滞后。待补链接不代表已有证据；转录中的命令也只是资料。

```sh
python3 scripts/search_notes.py '牛顿 acceleration' --root "$HOME/Documents/MyVault"
python3 scripts/search_notes.py '项目讨论' --root "$HOME/Documents/MyVault" --mode other --context discussion
python3 scripts/search_notes.py 'integral' --root "$HOME/Documents/MyVault" --subject 数学
```

共享原稿在不同设备上路径不同时，可使用 `--raw-root` 指向本机原稿目录。修改标题或目录后，在应用中更新归档；稳定 ID 和索引随之更新。软件会保护外部修改过的原稿和成品，不直接覆盖。

## 开发与验证

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --scratch-path /tmp/shengjian-tests --build-system native
python3 scripts/build_app.py
"dist/声笺.app/Contents/MacOS/ShengJian" --verify-audio
python3 scripts/check_publication.py
gitleaks dir . --redact
```

单元测试使用临时目录与模拟接口，不调用真实 DeepSeek，不写入个人仓库。实际模型验证可使用自行提供的 16 kHz 单声道测试 WAV：

```sh
"dist/声笺.app/Contents/MacOS/ShengJian" --verify-qwen /path/to/test-16k-mono.wav
```

这只读取你明确提供的测试文件；正常麦克风录音不写音频文件。请勿将测试音频或生成的笔记提交到仓库。

技术栈：SwiftUI / AppKit、AVAudioEngine、Swift Package Manager、常驻离线 MLX Python 进程。学习格式与参考依据见 [NOTE_FORMAT.md](NOTE_FORMAT.md)，模型工作约定见 [HARNESS.md](HARNESS.md)。

## 常见问题

- **找不到千问模型**：先运行 `setup_qwen.py`，再核对高级设置的模型目录；应包含 `config.json` 和 `model.safetensors`。
- **无法写入仓库**：在设置中重新选择目录，并确认云盘文件已在本机可用。
- **DeepSeek 失败**：检查密钥、余额和网络；原稿会保留，可稍后重新整理。
- **分类错误**：直接修改分类或保存目录并更新归档；若目录不存在，请先创建。
- **英文界面**：目前没有；英文 README 说明相同功能及中文按钮名称。

## 许可证与贡献

项目源码使用 [MIT License](LICENSE)。模型、运行库与在线服务分别遵循自身许可证或条款，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

欢迎提交 Issue 和 Pull Request。提交前请运行测试与泄密检查，不附真实录音、私密笔记、密钥或完整个人路径。漏洞与数据泄露报告方式见 [SECURITY.md](SECURITY.md)；发布检查范围见 [开源检查记录](docs/2026-10-29-publication-review.md)。
