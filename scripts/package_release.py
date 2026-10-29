#!/usr/bin/env python3
"""Audit an allowlisted app bundle and create a ZIP without host ownership or extended metadata."""
from pathlib import Path
import argparse
import getpass
import hashlib
import json
import plistlib
import re
import stat
import tempfile
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'dist/声笺.app'
FILES = {
    'Contents/Info.plist', 'Contents/MacOS/ShengJian', 'Contents/Resources/AppIcon.icns',
    'Contents/Resources/qwen_worker.py', 'Contents/_CodeSignature/CodeResources',
    *('Contents/Resources/installer/' + name for name in ('setup_asr.sh', 'setup_qwen.py', 'download_qwen.py', 'qwen-requirements.txt')),
}
SECRET_PATTERNS = {
    'private-home-path': rb'/(?:Users|home)/[A-Za-z0-9_.-]+/',
    'github-token': rb'gh[pousr]' + rb'_[A-Za-z0-9]{30,}|github_pat' + rb'_[A-Za-z0-9_]{40,}',
    'api-key': rb'\bsk' + rb'-[A-Za-z0-9_-]{20,}\b',
    'private-key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?' + rb'PRIVATE KEY-----',
}


def audit(app=APP):
    actual = {p.relative_to(app).as_posix() for p in app.rglob('*') if p.is_file() or p.is_symlink()}
    if actual != FILES: raise RuntimeError('Unexpected app inventory: ' + str(sorted(actual.symmetric_difference(FILES))))
    rows = []
    private = [str(Path.home()).encode(), (getpass.getuser() + '@').encode()]
    for name in sorted(actual):
        path = app / name
        if path.is_symlink(): raise RuntimeError('Release must contain no symlinks: ' + name)
        data = path.read_bytes()
        for label, pattern in SECRET_PATTERNS.items():
            if re.search(pattern, data): raise RuntimeError('Release privacy finding: ' + label + ' in ' + name)
        if any(value and value in data for value in private): raise RuntimeError('Release includes a host identity in ' + name)
        rows.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'org.shengjian.desktop': raise RuntimeError('Wrong app identity')
    # Verify the exact bytes and permissions that enter the ZIP, without local Finder/iCloud xattrs.
    with tempfile.TemporaryDirectory(prefix='shengjian-release-audit-') as temporary:
        clean = Path(temporary) / '声笺.app'
        for name in actual:
            path = clean / name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((app / name).read_bytes()); path.chmod(0o755 if name == 'Contents/MacOS/ShengJian' else 0o644)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(clean)], check=True, capture_output=True)
        signature = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', str(clean)], capture_output=True, text=True, check=True).stderr
    if 'Signature=adhoc' not in signature or 'TeamIdentifier=not set' not in signature: raise RuntimeError('Expected anonymous ad hoc signing, without a developer identity')
    return info, rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    info, rows = audit()
    if args.verify_only:
        print(f'Release app audit passed: {len(rows)} allowlisted files; no private paths or configured secret patterns found; ad hoc signature verified.')
        return
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip(): raise RuntimeError('Commit reviewed source changes before packaging a public release.')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if info.get('ShengJianSourceCommit') != commit or info.get('ShengJianSourceDirty') is not False: raise RuntimeError('Rebuild the app from this clean source commit before publishing.')
    version = info['CFBundleShortVersionString']
    provenance = {'version': version, 'source_commit': commit, 'architecture': 'arm64', 'minimum_macos': info['LSMinimumSystemVersion'],
        'signature': 'ad-hoc', 'developer_id': False, 'notarized': False, 'audio_or_user_data_included': False, 'files': rows}
    prefix = f'ShengJian-{version}-macOS-arm64'; output = ROOT / 'dist'
    archive = output / (prefix + '.zip')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
        def add(name, data, executable=False):
            entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0)); entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | (0o755 if executable else 0o644)) << 16
            package.writestr(entry, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        for row in rows:
            add('声笺.app/' + row['path'], (APP / row['path']).read_bytes(), row['path'] == 'Contents/MacOS/ShengJian')
        documentation = ['README.md', 'README.en.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'SECURITY.md', 'AGENTS.md', 'HARNESS.md', 'NOTE_FORMAT.md']
        documentation += [p.relative_to(ROOT).as_posix() for p in (ROOT / 'docs').glob('*.md')]
        for name in sorted(documentation):
            data = (ROOT / name).read_bytes()
            for label, pattern in SECRET_PATTERNS.items():
                if re.search(pattern, data): raise RuntimeError('Release documentation privacy finding: ' + label)
            add(name, data)
        add('RELEASE.json', (json.dumps(provenance, ensure_ascii=False, indent=2) + '\n').encode())
    with zipfile.ZipFile(archive) as package:
        if package.testzip(): raise RuntimeError('ZIP integrity check failed')
        for entry in package.infolist():
            if entry.extra or entry.comment: raise RuntimeError('Archive has unexpected metadata')
    audit_path = output / (prefix + '-audit.json'); audit_path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    checksum = output / 'SHA256SUMS.txt'
    checksum.write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in (archive, audit_path)))
    print('Release archive, audit manifest, and checksums created:', archive.name)


if __name__ == '__main__': main()
