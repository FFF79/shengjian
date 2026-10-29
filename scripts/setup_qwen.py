#!/usr/bin/env python3
"""Install the pinned local MLX runtime and Qwen3-ASR weights. No audio is read or sent."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE = Path.home() / 'Library/Application Support/声笺/ASR'
RUNTIME = BASE / 'runtime'
MODEL = BASE / 'models/Qwen3-ASR-1.7B-8bit'
REPO = 'mlx-community/Qwen3-ASR-1.7B-8bit'
REVISION = 'a8379a2e2f9e313c9292cdf1af4055ab56d50d55'
WEIGHTS_SHA256 = 'bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c'

def main():
    uv = shutil.which('uv') or str(Path.home() / '.local/bin/uv')
    if not Path(uv).is_file():
        raise RuntimeError('Install uv from https://docs.astral.sh/uv/getting-started/installation/ first')
    BASE.mkdir(parents=True, exist_ok=True)
    if not (RUNTIME / 'bin/python').exists():
        subprocess.run([uv, 'venv', '--python', '3.12', str(RUNTIME)], check=True)
    subprocess.run([uv, 'pip', 'sync', '--python', str(RUNTIME / 'bin/python'), str(ROOT / 'scripts/qwen-requirements.txt')], check=True)
    script = """
from huggingface_hub import snapshot_download
import sys
snapshot_download(sys.argv[1], revision=sys.argv[2], local_dir=sys.argv[3], allow_patterns=['*.json','*.txt','README.md'])
"""
    env = dict(os.environ, HF_XET_HIGH_PERFORMANCE='1', HF_HUB_DISABLE_TELEMETRY='1')
    subprocess.run([str(RUNTIME / 'bin/python'), '-c', script, REPO, REVISION, str(MODEL)], env=env, check=True)
    if Path('/Applications/Xcode.app/Contents/Developer').exists():
        env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['swift', str(ROOT / 'scripts/download_qwen.swift')], env=env, check=True)
    digest = hashlib.sha256()
    with (MODEL / 'model.safetensors').open('rb') as source:
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b''): digest.update(chunk)
    if digest.hexdigest() != WEIGHTS_SHA256:
        raise RuntimeError('Model checksum mismatch; do not use these weights')
    (BASE / 'installation.json').write_text(json.dumps({'model': REPO, 'revision': REVISION, 'weights_sha256': WEIGHTS_SHA256, 'mlx_audio': '0.6.1'}, indent=2))
    print('Local Qwen3-ASR model verified and ready:', MODEL)

if __name__ == '__main__':
    main()
