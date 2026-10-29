# Third-party components

The MIT license in this repository covers ShengJian application source and its original helper scripts. It does not relicense separately downloaded models, dependencies, or online services. This source publication vendors no model weights, Python packages, or Apple SDK files.

| Component | Role | License / terms source |
| --- | --- | --- |
| [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) | Original speech-recognition model | Upstream Apache-2.0 license and model documentation |
| [MLX community Qwen3-ASR 1.7B 8-bit](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit) | Separately downloaded converted weights | Model card declares Apache-2.0; preserve its notices if redistributing weights |
| [mlx-audio](https://github.com/Blaizzy/mlx-audio) | Local inference runtime | MIT; see the upstream license |
| [MLX](https://github.com/ml-explore/mlx) | Apple Silicon tensor runtime | MIT; see the upstream license |
| [uv](https://github.com/astral-sh/uv) | User-installed Python environment/package tool | MIT or Apache-2.0; see upstream notices |
| [DeepSeek API](https://api-docs.deepseek.com/) | Optional hosted text organization | Account, service, and billing terms apply; no API credentials are included |
| [Obsidian](https://obsidian.md/) | External Markdown knowledge app | Separate proprietary application; no Obsidian code is bundled |
| Apple SDKs and SF Symbols | Native system APIs and system-provided symbols | Apple developer terms; SDKs and symbol assets are not redistributed here |

The pinned Python environment in `scripts/qwen-requirements.txt` includes additional transitive dependencies. Their individual licenses remain applicable. If you distribute a built application together with a Python environment or model, review and include the relevant dependency licenses and notices for that distribution. The source repository is not a bundled runtime distribution.

The references in `NOTE_FORMAT.md` are citations, not redistributed papers. This project is independent and is not affiliated with or endorsed by Qwen, DeepSeek, Obsidian, Apple, or their contributors.
