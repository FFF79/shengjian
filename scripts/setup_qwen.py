#!/usr/bin/env python3
"""Install isolated binary wheels and pinned Qwen weights. Requires neither Swift nor Xcode."""
from pathlib import Path
import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from download_qwen import download_weights, SHA256

ROOT = Path(__file__).resolve().parent
DEFAULT_BASE = Path.home() / 'Library/Application Support/ShengJian/ASR'
REPO = 'mlx-community/Qwen3-ASR-1.7B-8bit'
REVISION = 'a8379a2e2f9e313c9292cdf1af4055ab56d50d55'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, default=DEFAULT_BASE)
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise RuntimeError('Local Qwen setup requires Apple Silicon macOS.')
    uv = os.environ.get('SHENGJIAN_UV_BIN') or shutil.which('uv') or str(Path.home() / '.local/bin/uv')
    if not Path(uv).is_file(): raise RuntimeError('Use the app’s Install local transcription components button, or run setup_asr.sh.')
    base = args.base.expanduser().resolve(); runtime = base / 'runtime'; model = base / 'models/Qwen3-ASR-1.7B-8bit'
    base.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, HF_HUB_DISABLE_TELEMETRY='1', HF_HUB_DISABLE_IMPLICIT_TOKEN='1', UV_NO_BUILD='1')
    if not (runtime / 'bin/python').is_file():
        print('正在安装独立 Python 3.12 环境…', flush=True)
        subprocess.run([uv, 'venv', '--managed-python', '--python', '3.12', str(runtime)], env=env, check=True)
    print('正在安装预编译转写组件（不编译源码）…', flush=True)
    subprocess.run([uv, 'pip', 'sync', '--python', str(runtime / 'bin/python'), '--only-binary', ':all:', str(ROOT / 'qwen-requirements.txt')], env=env, check=True)
    script = """
from huggingface_hub import snapshot_download
import sys
snapshot_download(sys.argv[1], revision=sys.argv[2], local_dir=sys.argv[3], token=False, allow_patterns=['*.json','*.txt','README.md'])
"""
    print('正在下载模型配置…', flush=True)
    subprocess.run([str(runtime / 'bin/python'), '-c', script, REPO, REVISION, str(model)], env=env, check=True)
    download_weights(model)
    (base / 'installation.json').write_text(json.dumps({'model': REPO, 'revision': REVISION, 'weights_sha256': SHA256, 'mlx_audio': '0.6.1'}, indent=2))
    print('本地转写组件已安装，可以开始录音。', flush=True)


if __name__ == '__main__':
    try: main()
    except Exception as error:
        print('安装未完成：' + str(error), file=sys.stderr, flush=True)
        raise SystemExit(1)
