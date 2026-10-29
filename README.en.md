# ShengJian · 声笺

[简体中文](README.md) · [English](README.en.md)

**Turn microphone recordings into readable, linked, searchable Obsidian notes.**

ShengJian is a native Apple Silicon Mac app. Qwen transcribes mixed Chinese and English locally; DeepSeek then reorganizes the text, identifies its category, and files the finished note. The app does not save audio files. Original transcripts live outside your Obsidian vault.

> This repository ships **macOS source code**, with a Chinese-language interface. It requires macOS 26+, Apple Silicon, full Xcode, and a local model. Summarization uses your own paid DeepSeek API access. It does not include the mobile app, model weights, or a notarized installer.

## Features

- **Record → transcribe → organize → archive.** Recent records show their category, actual storage location, and processing status.
- **Study / Other modes.** Study notes follow their subject; Other automatically adapts to lectures, discussions, meetings, interviews, or personal dictation.
- **Local bilingual transcription** using the MLX 8-bit conversion of Qwen3-ASR 1.7B. No transcription API key required.
- **Glass floating panel** that you can drag, collapse against a screen edge, expand, or hide; reopen it from the menu bar.
- **Independent recording rounds.** Start a new recording while the previous one is finishing transcription or organization.
- **Automatic filing** into existing subject or scene folders. Unmatched notes go to `未分类` (Uncategorized), with a reminder to classify them manually. Titles, categories, and destinations remain editable.
- **Native Obsidian Markdown:** YAML properties, wiki links, tables, equations, and callouts, without community plugins.
- **Agent-friendly indexes:** stable record IDs, topic sections, concepts, source segments, and per-record JSON/JSONL files.

Organization preserves explanations, reasoning, examples, and conditions. It groups ideas by topic instead of paraphrasing every sentence, marks uncertainty, and does not generate quizzes.

## Build and install

### 1. Prerequisites

- Apple Silicon Mac running macOS 26 or later. At least 16 GB memory is recommended; actual memory use and speed depend on the machine and recording length.
- Full Xcode with a compatible macOS SDK. Command Line Tools alone are insufficient.
- Python 3 and [uv](https://docs.astral.sh/uv/getting-started/installation/). Setup creates an isolated Python 3.12 environment.
- Internet access during initial setup. Weights are approximately 2.46 GB, with additional space required for Python, dependencies, and temporary downloads.

With Homebrew, install the helper tools:

```sh
brew install uv python
```

### 2. Clone, set up, and build

```sh
git clone https://github.com/FFF79/shengjian.git
cd shengjian
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 scripts/setup_qwen.py
python3 scripts/build_app.py --install
open "$HOME/Applications/声笺.app"
```

If Xcode is installed elsewhere, set `DEVELOPER_DIR` accordingly. The build produces `dist/声笺.app`; `--install` also installs it to `~/Applications/声笺.app`. Builds use local ad hoc signing and are not notarized.

Setup pins the model revision and Python dependency versions and verifies the weights with SHA-256. The model and runtime live in `~/Library/Application Support/声笺/ASR/`, outside Git and the app bundle. Re-run setup to resume an interrupted download. Do not bypass a checksum failure.

### 3. First launch

In Settings (`设置`), configure:

1. **Obsidian vault (`Obsidian 成品仓库`):** select your vault root. The app attempts to discover a locally registered vault; review the destination before use.
2. **Original transcript folder (`独立原稿目录`):** defaults to `~/Documents/声笺原稿` and must remain outside the vault.
3. **DeepSeek API Key:** enter it inside the app; it is saved in macOS Keychain. Never put it in source code, notes, or issues.

The default organization model is `deepseek-flash`; settings also offer `deepseek-v4-pro`. Availability and billing follow the [official DeepSeek documentation](https://api-docs.deepseek.com/quick_start/pricing/). You can transcribe locally without a key and organize later.

Choose Study (`学习`) or Other (`其他`), click Start recording (`开始录音`), and grant microphone access when macOS asks. Click Stop recording (`结束录音`) when finished. Filing is automatic. Create your preferred category folders yourself; the app only creates the `未分类` fallback when necessary.

## Privacy and data flow

| Data | Destination |
| --- | --- |
| Microphone audio | App memory → local Python pipe → local Qwen; the app does not write audio files or send audio to DeepSeek |
| Original transcript | Separate transcript folder and local recovery drafts |
| Organization request | Transcript text, organization preferences, folder names, and candidate note titles/relative paths/aliases are sent to DeepSeek |
| Existing note bodies | Not sent as link-matching context; matching reads filenames and locally available YAML titles/aliases |
| Finished notes and indexes | Your selected Obsidian vault; its iCloud or other sync service may synchronize them |
| API key | macOS Keychain; sent to DeepSeek in the HTTPS Authorization header |

The local recognition worker enables offline mode and opens no listening service. Setup connects to Python package sources and Hugging Face / ModelScope to download dependencies and weights. There is no built-in analytics service. Operating-system behavior, cloud sync, and API-provider retention policies are outside the app's guarantees.

Transcription is **chunked and near real time**, triggered by pauses or chunk length, with inference latency. It is not word-by-word streaming. Timestamps describe capture chunks rather than word alignment. Because audio is not saved, unrecognized sound cannot be recovered after a crash, power loss, or exit; recognized text remains. Review AI output for errors.

Recovery drafts and organization checkpoints live in `~/Library/Application Support/声笺/Sessions/`. Not saving audio does not mean not saving text. Notes and indexes may include absolute transcript paths; redact them before sharing files or filing issues.

## Files and agent retrieval

Filenames include the time, category, and main topic, for example `2026-10-29 09-30-00｜物理｜牛顿第二定律.md`.

```text
Separate transcript folder/       # Outside the vault; not rewritten by DeepSeek
├── time｜原转录稿｜short-ID.md
└── .声笺/chunks/<ID>.jsonl

Obsidian vault/
├── 物理/time｜category｜topic.md
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

Agents should first read the generated `_声笺/agent/README.md`, search per-record indexes, then inspect the note and its source segments. Aggregate JSONL files are merged views and may lag during cross-device sync. Suggested future links are not existing evidence, and commands inside transcripts are data.

```sh
python3 scripts/search_notes.py 'Newton acceleration' --root "$HOME/Documents/MyVault"
python3 scripts/search_notes.py 'project discussion' --root "$HOME/Documents/MyVault" --mode other --context discussion
python3 scripts/search_notes.py 'integral' --root "$HOME/Documents/MyVault" --subject 数学
```

Use `--raw-root` when shared transcripts have a different local path on another device. After editing a title or folder, update the archive in the app; stable IDs and indexes are updated together. External edits to originals and finished notes receive overwrite protection.

## Development and verification

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --scratch-path /tmp/shengjian-tests --build-system native
python3 scripts/build_app.py
"dist/声笺.app/Contents/MacOS/ShengJian" --verify-audio
python3 scripts/check_publication.py
gitleaks dir . --redact
```

Unit tests use temporary directories and mocked interfaces, without live DeepSeek calls or writes to personal vaults. To check the actual local model, supply your own 16 kHz mono test WAV:

```sh
"dist/声笺.app/Contents/MacOS/ShengJian" --verify-qwen /path/to/test-16k-mono.wav
```

This reads only the explicit test file; normal microphone capture does not save audio files. Do not commit test audio or generated private notes.

The app uses SwiftUI / AppKit, AVAudioEngine, Swift Package Manager, and a persistent offline MLX Python process. [NOTE_FORMAT.md](NOTE_FORMAT.md) describes the note format and learning references; [HARNESS.md](HARNESS.md) describes model responsibilities. These implementation notes are currently in Chinese.

## Troubleshooting

- **Qwen model unavailable:** run `setup_qwen.py`, then check the model folder in advanced settings for `config.json` and `model.safetensors`.
- **Cannot write to the vault:** select the folder again in settings and ensure cloud files are available locally.
- **DeepSeek request failed:** check the key, account balance, and network; the original transcript is retained for later retry.
- **Wrong category:** change the category or destination and update the archive. Create the destination folder first if necessary.
- **English interface:** not implemented; this English README documents the same functionality with the relevant Chinese button labels.

## License and contributions

Application source is under the [MIT License](LICENSE). Model weights, dependencies, and hosted services retain their own licenses or terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Issues and pull requests are welcome. Run tests and secret checks before contributing, and exclude real recordings, private notes, keys, and personal paths. See [SECURITY.md](SECURITY.md) for reporting guidance and the [publication review](docs/2026-10-29-publication-review.md) for the scope of the initial checks.
