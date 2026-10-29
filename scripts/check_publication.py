#!/usr/bin/env python3
"""Check tracked source files for private artifacts. Findings never print matched values."""
from pathlib import Path
import argparse
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
# Patterns are split where needed so this checker does not flag its own definitions.
PATTERNS = {
    'private-key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?' + r'PRIVATE KEY-----'),
    'github-token': re.compile(r'gh[pousr]' + r'_[A-Za-z0-9]{30,}|github_pat' + r'_[A-Za-z0-9_]{40,}'),
    'api-key': re.compile(r'\bsk' + r'-[A-Za-z0-9_-]{20,}\b'),
    'aws-access-key': re.compile(r'\b(?:AKIA|ASIA)' + r'[A-Z0-9]{16}\b'),
    'private-home-path': re.compile(r'/(?:Users|home)/[A-Za-z0-9_.-]+/'),
    'embedded-url-credentials': re.compile(r'https?://[^\s/@:]+:[^\s/@]+@'),
    'personal-email': re.compile(r'\b[A-Za-z0-9._%+-]+@(?![23]x\.png\b|users\.noreply\.github\.com\b|example\.(?:com|org)\b)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
}
FORBIDDEN_PARTS = {'.env', 'Mobile', 'Sessions', 'Harness', 'dist', '.build', '.swiftpm',
                   '__pycache__', 'xcuserdata', '.obsidian', '_声笺', '.声笺', '声笺原稿', '原稿'}
FORBIDDEN_SUFFIXES = {'.wav', '.mp3', '.m4a', '.aac', '.flac', '.pcm', '.safetensors', '.gguf',
                      '.pem', '.key', '.p12', '.mobileprovision', '.pyc', '.log', '.zip', '.dmg'}


def check(root, paths):
    issues = []
    for name in paths:
        relative = Path(name)
        path = root / relative
        if any(p in FORBIDDEN_PARTS or p.startswith('.env.') or p.endswith('.app') for p in relative.parts):
            issues.append((name, 0, 'private-artifact-path')); continue
        if path.is_symlink():
            issues.append((name, 0, 'symlink')); continue
        if relative.suffix.lower() in FORBIDDEN_SUFFIXES:
            issues.append((name, 0, 'private-artifact-type')); continue
        if not path.is_file():
            issues.append((name, 0, 'missing-tracked-file')); continue
        data = path.read_bytes()
        if len(data) > 2 * 1024 * 1024:
            issues.append((name, 0, 'oversized-file')); continue
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            issues.append((name, 0, 'unreviewed-binary')); continue
        for number, line in enumerate(text.splitlines(), 1):
            for label, pattern in PATTERNS.items():
                if pattern.search(line): issues.append((name, number, label))
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        samples = {
            'private-key': '-----BEGIN ' + 'PRIVATE KEY-----',
            'github-token': 'ghp' + '_' + 'A' * 36,
            'api-key': 'sk' + '-' + 'A' * 32,
            'aws-access-key': 'AKIA' + 'A' * 16,
            'private-home-path': '/' + 'Users' + '/sample/Documents/private.md',
            'embedded-url-credentials': 'https://' + 'sample:password@example.org',
            'personal-email': 'sample' + '@private.invalid',
        }
        for label, sample in samples.items():
            if not PATTERNS[label].search(sample): raise SystemExit('Failed detector self-test: ' + label)
        if PATTERNS['personal-email'].search('icon_16x16@2x.png'): raise SystemExit('Retina icon filename misclassified as email')
        print('Publication detector self-tests passed.')
        return
    result = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT, capture_output=True, check=True)
    paths = [name for name in result.stdout.decode().split('\0') if name]
    if not paths: raise SystemExit('No tracked files; stage the source files before checking.')
    issues = check(ROOT, paths)
    for name, line, label in issues: print(f'{name}:{line}: {label}', file=sys.stderr)
    if issues: raise SystemExit(f'Publication check failed: {len(issues)} finding(s); matched values are hidden.')
    print(f'Publication check passed: {len(paths)} tracked UTF-8 source/documentation files; no private artifacts or configured secret patterns found.')


if __name__ == '__main__':
    main()
