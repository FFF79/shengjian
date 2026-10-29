#!/bin/sh
# Verified standalone bootstrap. Uses only tools included with macOS; no Xcode or system Python.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BASE=${SHENGJIAN_ASR_BASE:-"$HOME/Library/Application Support/ShengJian/ASR"}
TOOLS="$BASE/setup-tools"
ARCHIVE="$TOOLS/uv-0.12.10.tar.gz"
EXPECTED=51c6170e8e3a01cef9f33b94f582b7b81ac65046f55d40afb35f9cff5a68c179
URL=https://github.com/astral-sh/uv/releases/download/0.12.10/uv-aarch64-apple-darwin.tar.gz
if [ "$(/usr/bin/uname -m)" != arm64 ]; then
    echo '此版本需要 Apple Silicon Mac。' >&2
    exit 1
fi
/bin/mkdir -p "$TOOLS"
if [ ! -f "$ARCHIVE" ] || [ "$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')" != "$EXPECTED" ]; then
    echo '正在下载已固定版本的安装工具…'
    /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 30 --max-time 900 --silent --show-error --output "$ARCHIVE.part" "$URL"
    if [ "$(/usr/bin/shasum -a 256 "$ARCHIVE.part" | /usr/bin/awk '{print $1}')" != "$EXPECTED" ]; then
        echo '安装工具校验失败，未执行下载内容。请重试。' >&2
        exit 1
    fi
    /bin/mv "$ARCHIVE.part" "$ARCHIVE"
fi
# Re-extract from the verified archive rather than trusting a previously modified executable.
/usr/bin/tar -xf "$ARCHIVE" -C "$TOOLS" uv-aarch64-apple-darwin/uv
UV="$TOOLS/uv-aarch64-apple-darwin/uv"
/bin/chmod 700 "$UV"
export SHENGJIAN_UV_BIN="$UV"
export UV_PYTHON_INSTALL_DIR="$BASE/python"
export UV_CACHE_DIR="$BASE/setup-cache"
export UV_NO_BUILD=1
export HF_HUB_DISABLE_TELEMETRY=1
export HF_HUB_DISABLE_IMPLICIT_TOKEN=1
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export CC=/usr/bin/false
export CXX=/usr/bin/false
export PYTHONUNBUFFERED=1
echo '正在准备独立运行环境，无需 Xcode…'
exec "$UV" run --no-config --no-project --managed-python --python 3.12 "$SCRIPT_DIR/setup_qwen.py" --base "$BASE"
