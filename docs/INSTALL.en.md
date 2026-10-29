# Download, install, and open ShengJian

[简体中文](INSTALL.zh-CN.md) · [Full usage guide](USAGE.en.md)

The packaged app and source share the MIT license. `RELEASE.json` records the matching source commit. Normal use requires no Xcode, Homebrew, or preinstalled Python. This build supports **Apple Silicon M-series Macs on macOS 26+**, not Intel Macs or Windows.

## 1. Download and install

1. Visit [GitHub Releases](https://github.com/FFF79/shengjian/releases/latest).
2. Under Assets, download `ShengJian-0.3.1-macOS-arm64.zip`. The automatically generated “Source code” archives are not application downloads.
3. Download `SHA256SUMS.txt` from the same release. Optionally compute the ZIP digest in Terminal and compare it with the corresponding line:

```sh
cd "$HOME/Downloads"
shasum -a 256 ShengJian-0.3.1-macOS-arm64.zip
```

4. Extract the ZIP. Move `声笺.app` to Applications or your personal `~/Applications` folder, then open it. Preserve an existing app from another source rather than overwriting it.

The ZIP includes README files, installation and usage guides in docs/, the license, and third-party notices. Model weights are downloaded separately at first use.

## 2. Signing and macOS warnings

This release uses an **ad hoc local signature**, without Apple Developer ID signing or Apple notarization. Its signature checks integrity but does not establish a verified developer identity. A matching SHA-256 is not an Apple security review.

If macOS blocks the app specifically because the developer is unidentified or the app is unnotarized, and you have verified the source and checksum:

1. Attempt to open the app once.
2. In System Settings, open Privacy & Security and find the app-specific Open Anyway control.
3. Confirm opening when prompted, authenticating with your own system account if required.

This grants an exception for that app; later launches normally work by double-clicking. See [Apple's official guidance](https://support.apple.com/en-us/102445). Do not disable Gatekeeper, global security checks, or SIP. Stop if a warning says malware was detected, the app will damage the computer, or the file is damaged; verify and re-download instead of treating every warning as an ordinary notarization notice. Managed Macs may prohibit exceptions.

## 3. Prepare local transcription

1. Open ShengJian Settings and find Local transcription components (`本地转写组件`). Click Install / repair (`安装 / 修复本地转写组件`).
2. The installer downloads a verified uv tool, managed Python 3.12, prebuilt dependency wheels, and Qwen weights. It does not invoke Swift or Xcode or compile dependency source.
3. Weights are approximately 2.46 GB. Allow extra space for runtime files, caches, and assembly; at least 10 GB free space is recommended during setup.
4. You may close the settings window, but keep the app running. Status and Installation details (`安装详情`) show progress. Retry after a network interruption to resume model chunks.
5. Wait for Local transcription components ready (`本地转写组件已就绪`). No API key, Keychain data, or personal recording is needed for setup.

Components live in `~/Library/Application Support/ShengJian/ASR/`, outside the app bundle, source checkout, and Obsidian vault. Setup accesses public package and model hosts without uploading audio or notes. The bootstrap tool and model weights are checked with SHA-256; unverified content is not used.

## 4. Connect your own notes

- **Note root:** select an Obsidian vault root or an ordinary folder. Open an ordinary folder as a vault in Obsidian to use Obsidian navigation.
- **Separate originals:** select a location outside the note root; default `~/Documents/声笺原稿`.
- **Automatic scenes and folders:** add scenes, bind destinations and formats, or create subfolders inside the app. Existing folders are candidates even without custom rules; unmatched records go to Uncategorized.
- **DeepSeek:** enter and save your own API key inside the app. Classification and organization send text and required scene/folder metadata and incur API charges; audio is not uploaded.

Click Start recording (`开始录音`) and grant microphone access when macOS prompts. The app does not save audio files; originals and finished notes are stored separately. See the [usage guide](USAGE.en.md) for daily controls and copy-ready agent prompts.

## Troubleshooting

- **No Open Anyway option:** attempt a launch first, then revisit Privacy & Security. Ask your administrator on a managed device, or build from source.
- **Missing components:** ensure you downloaded the full application ZIP. Reinstalling the app does not intentionally delete models or notes.
- **Setup fails:** retain the details, check network access and disk space, and retry. Do not skip checksums or install random replacements. Redact private paths and text before sharing errors.
- **Someone requests a key in chat or an issue:** do not send it. Configure it inside the app.
