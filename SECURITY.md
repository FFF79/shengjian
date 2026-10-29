# Security and privacy

ShengJian is a personal desktop tool. Its application source is public; recordings, transcripts, vaults, local settings, runtime/model downloads, and credentials are not repository content.

## Before sharing a bug report

- Remove API keys, authorization headers, personal paths, transcript text, and private note titles.
- Prefer a minimal synthetic example. Do not attach your Keychain, preferences, session directory, or entire Obsidian vault.
- The app stores text recovery drafts and model organization checkpoints locally. Generated indexes may contain absolute original-transcript paths.
- DeepSeek receives text and selected metadata when organization is requested. The source code cannot promise the provider's retention behavior.

## Report a vulnerability

If GitHub offers **Security → Report a vulnerability** on this repository, use that private channel. Otherwise open a minimal issue asking for a private reporting channel, without including exploit details, secrets, or private data. Never publish a live key in an issue. Revoke an exposed key immediately through its provider.

## Contributor checks

```sh
python3 scripts/check_publication.py --self-test
python3 scripts/check_publication.py
gitleaks dir . --redact
gitleaks git . --redact
```

The publication checker scans tracked working-tree files. Gitleaks also checks Git history. Neither scanner proves that a program has no vulnerabilities; manually review additions, especially assets, sample data, screenshots, logs, and generated files. Do not bypass secret detection with force-add or broad allowlists.
