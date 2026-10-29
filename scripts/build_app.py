#!/usr/bin/env python3
"""Build the native app. Run setup_qwen.py once to install the local ASR model/runtime."""
from pathlib import Path
import argparse, os, plistlib, shutil, subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--install', action='store_true', help='Also install in ~/Applications')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[1]
BUILD = Path.home() / 'Library/Caches/ShengJian-OpenSource-build'
APP = BUILD / '声笺.app'
env = dict(os.environ)
if 'DEVELOPER_DIR' not in env and Path('/Applications/Xcode.app/Contents/Developer').exists():
    env['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
build_command = ['swift', 'build', '--scratch-path', str(BUILD), '--build-system', 'native', '-c', 'release',
    '-Xswiftc', '-file-prefix-map', '-Xswiftc', str(ROOT) + '=/src/shengjian',
    '-Xswiftc', '-debug-prefix-map', '-Xswiftc', str(Path.home()) + '=/build',
    '-Xswiftc', '-file-compilation-dir', '-Xswiftc', '/src/shengjian']
subprocess.run(build_command, cwd=ROOT, env=env, check=True)
bin_path = Path(subprocess.check_output(build_command + ['--show-bin-path'], cwd=ROOT, env=env, text=True).strip())
contents = APP / 'Contents'
# The app contains the bridge script; the large model and Python runtime live once in Application Support.
if APP.exists(): shutil.rmtree(APP)
for folder in ['MacOS', 'Resources']:
    (contents / folder).mkdir(parents=True, exist_ok=True)
binary = contents / 'MacOS/ShengJian'
shutil.copy2(bin_path / 'ShengJian', binary)
subprocess.run(['/usr/bin/strip', '-S', '-x', str(binary)], check=True)
shutil.copy2(ROOT / 'scripts/qwen_worker.py', contents / 'Resources/qwen_worker.py')
installer = contents / 'Resources/installer'
installer.mkdir()
for name in ['setup_asr.sh', 'setup_qwen.py', 'download_qwen.py', 'qwen-requirements.txt']:
    shutil.copy2(ROOT / 'scripts' / name, installer / name)
iconset = BUILD / 'ShengJian.iconset'
subprocess.run(['swift', str(ROOT / 'scripts/make_icon.swift'), str(iconset)], env=env, check=True)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(contents / 'Resources/AppIcon.icns')], check=True)
source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
source_dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip())
plist = {
    'ShengJianSourceCommit': source_commit, 'ShengJianSourceDirty': source_dirty,
    'CFBundleExecutable': 'ShengJian', 'CFBundleIdentifier': 'org.shengjian.desktop',
    'CFBundleName': '声笺', 'CFBundleDisplayName': '声笺', 'CFBundlePackageType': 'APPL',
    'CFBundleIconFile': 'AppIcon',
    'CFBundleShortVersionString': '0.3.1', 'CFBundleVersion': '4', 'LSMinimumSystemVersion': '26.0',
    'NSMicrophoneUsageDescription': '声笺使用麦克风在本机将语音转为文字，不保存音频文件。',
    'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
}
with (contents / 'Info.plist').open('wb') as file: plistlib.dump(plist, file)
entitlements = ROOT / 'scripts/entitlements.plist'
subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(entitlements), str(APP)], check=True)
destination = ROOT / 'dist/声笺.app'
destination.parent.mkdir(exist_ok=True)
if destination.exists(): shutil.rmtree(destination)
subprocess.run(['ditto', '--norsrc', '--noextattr', str(APP), str(destination)], check=True)
subprocess.run(['xattr', '-cr', str(destination)], check=True)
print(destination)
if args.install:
    installed = Path.home() / 'Applications/声笺.app'
    if installed.exists():
        with (installed / 'Contents/Info.plist').open('rb') as file:
            if plistlib.load(file).get('CFBundleIdentifier') != 'org.shengjian.desktop': raise RuntimeError('Refusing to replace an unrelated app')
    installed.parent.mkdir(exist_ok=True)
    backup = BUILD / 'previous-installed.app'
    if backup.exists(): shutil.rmtree(backup)
    if installed.exists(): shutil.move(str(installed), backup)
    subprocess.run(['ditto', '--norsrc', '--noextattr', str(APP), str(installed)], check=True)
    subprocess.run(['xattr', '-cr', str(installed)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(installed)], check=True)
    print(installed)
