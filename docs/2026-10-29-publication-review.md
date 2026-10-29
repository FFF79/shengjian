# Desktop source publication review · 2026-10-29

## Result and scope

The publication contains desktop application source, synthetic unit tests, original build helpers, and documentation. It was prepared from an explicit source-file allowlist in a fresh repository, without importing earlier Git history. Automated checks and manual review found no live API credentials, personal home-directory paths, private emails, recordings, transcripts, or local user configuration in the reviewed files. This is a bounded publication-content review, not proof that all possible secrets or software vulnerabilities have been eliminated.

Scope is authorized publication of the macOS application. The mobile application, app bundles, build caches, IDE state, model weights, Python environments, logs, vault contents, generated indexes, local session recovery data, preferences, and Keychain are excluded. The review neither reads nor exports Keychain values. Git authorship uses the public account name and its GitHub noreply address. No private account email is included.

The review uses the generic publication-review structure; no malware, intrusion, or vulnerability-report flavor applies. No external target was tested.

## Evidence

All observations are dated 2026-10-29. Commands below run from the repository root. Raw machine-specific build logs and scanner reports are local-only artifacts and are deliberately not redistributed; artifact paths and content hashes are therefore n/a. The commands reproduce the checks against the checked-out revision.

| ID | Source type / reference | Reproduction command | Observed result |
| --- | --- | --- | --- |
| E-001 | command / tracked-file inventory | `git ls-files` | Source, tests and documentation only; no mobile directory or private runtime artifacts |
| E-002 | command / Gitleaks 8.30.1 filesystem scan | `gitleaks dir . --redact` | No secret findings |
| E-003 | command / publication checker | `python3 scripts/check_publication.py --self-test` and `python3 scripts/check_publication.py` | Detector self-tests and tracked-file checks pass; reports hide matched values |
| E-004 | command / Swift tests | `swift test --scratch-path /tmp/shengjian-tests --build-system native` | 42 desktop/shared-core tests pass, using synthetic data and temporary directories |
| E-005 | command / source build and audio conversion | `python3 scripts/build_app.py` then `"dist/声笺.app/Contents/MacOS/ShengJian" --verify-audio` | App builds; in-memory conversion yields 144000 samples for 9 seconds, without microphone access or saving audio |
| E-006 | file + manual / privacy boundaries | Review `Sources/ShengJian/Settings.swift`, `Sources/ShengJianCore/DeepSeekHarness.swift`, `Sources/ShengJianCore/LocalASRWorker.swift`, and `scripts/qwen_worker.py` | Key stored through Keychain API; DeepSeek receives text, scene rules and metadata; local ASR receives PCM in pipes and enables offline mode |
| E-007 | command + manual / Python static review | `uvx --from bandit bandit -q -r scripts` | 0 high and 0 medium findings; 28 low subprocess/PATH warnings manually reviewed |

E-007 warnings concern developer helper scripts invoking local tools through argument arrays. They do not invoke a shell with transcript or model-generated input. Scripts assume a trusted local development environment and PATH; they are not a boundary for executing untrusted repositories.

Git history is additionally checked before the initial push with `gitleaks git . --redact`. Re-run it after every new commit. The history begins with the sanitized source snapshot, not a copied development history.

## Findings

### F-001 · Private runtime data excluded

- Severity: info; category: other; status: validated; confidence: high.
- Evidence: E-001, E-002, E-003.
- Location: tracked repository tree, `.gitignore`, `scripts/check_publication.py`.
- Impact: the source publication does not distribute personal recordings, settings, credentials, local environment contents, or device-specific home paths found by these checks.
- Reproduce: list tracked files, run the publication checker, then run the filesystem and history secret scans.
- Remediation: preserve the allowlist-based publication approach; inspect every new tracked file and never force-add private artifacts.
- Residual risk: scanners cover known formats and configured patterns; synthetic-looking or novel secret formats still require manual review.

### F-002 · Text organization uses a hosted provider

- Severity: info; category: design; status: accepted_risk; confidence: high.
- Evidence: E-006, E-004.
- Location: `Sources/ShengJianCore/DeepSeekHarness.swift`, privacy sections of both READMEs.
- Impact: organization sends transcript text, preferences, folder names, and candidate note metadata to DeepSeek; this feature is not an entirely offline workflow.
- Reproduce: inspect the request body in the harness and the mocked request tests; no live credentials are needed.
- Remediation: use local transcription without organization when hosted processing is unsuitable; read provider terms before sending private material.
- Residual risk: provider retention and local operating-system or cloud-sync behavior are outside this source review.

## Publication path

P-001 · Sanitized source → verified public snapshot (`path_type: callflow`)

1. Select desktop source and synthetic tests; omit all personal and generated artifacts. Evidence: E-001; finding: F-001.
2. Replace personal build identifiers with generic project identifiers; write bilingual setup and privacy documentation. Evidence: E-003, E-006; findings: F-001, F-002.
3. Run content checks, manual review, tests, and source build. Evidence: E-002 through E-007; findings: F-001, F-002.
4. Commit using GitHub noreply authorship, scan the complete initial Git history, then publish the reviewed snapshot. Evidence: E-001 through E-003; finding: F-001.

Residual risks: ongoing changes need the same checks; generated notes can contain private text and local paths even though they are not repository content. This review is not a dependency vulnerability audit or certification of secure behavior.

## Completion checklist

- [x] Authorized desktop-only scope identified.
- [x] Findings cite reproducible evidence and a publication path.
- [x] Automated findings received manual review.
- [x] Readmes describe cloud text processing and retained local text.
- [x] Tests use synthetic inputs and isolated temporary folders.
- [x] No real credentials, private paths, or machine-specific logs are included in this report.

## Automatic-scenes update

The same publication checks cover the unified automatic-scene release. New recordings classify first, then organize with the bound format and archive. The recording page has no Study/Other selector. Legacy mode values remain solely for compatibility with old records.

Scene-routing tests validate request order, custom format and folder precedence, unrecognized IDs, low confidence, missing destinations, explicit root binding, source metadata, and folder traversal/symlink rejection. Interactive checks used an isolated temporary workspace to select a generic root, create a subfolder, add/edit a scene, bind a destination, save a structure and custom format, and verify the mode-free homepage. No private vault, original recording, or live API key was used.

Scene settings are local and isolated by root. The open-source app uses its own preference identity, Keychain service, and `ShengJian/Sessions` text-recovery directory; it does not load a separate personal build's credentials or recording history. ASR weights are installed separately, outside Git.
