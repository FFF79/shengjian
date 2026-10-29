#!/usr/bin/env python3
"""Download pinned public Qwen weights with verified resumable ranges; no compiler needed."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import hashlib
import os
import shutil
import time
from urllib.request import Request, urlopen
from urllib.parse import urlsplit
import uuid

SIZE = 2_463_307_541
SHA256 = 'bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c'
SOURCES = (
    'https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/a8379a2e2f9e313c9292cdf1af4055ab56d50d55/model.safetensors',
    'https://modelscope.cn/models/mlx-community/Qwen3-ASR-1.7B-8bit/resolve/579e237ce6ec925252973afe835d2f98a138602f/model.safetensors',
)


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''): value.update(chunk)
    return value.hexdigest()


def download_weights(directory, *, sources=SOURCES, size=SIZE, expected_hash=SHA256, chunk_size=1024 * 1024, workers=12, retries=8, progress=print):
    for source in sources:
        parsed = urlsplit(source)
        local_test = parsed.scheme == 'http' and parsed.hostname == '127.0.0.1'
        if (parsed.scheme != 'https' and not local_test) or parsed.username or parsed.password:
            raise ValueError('Model downloads require HTTPS public URLs; only loopback HTTP is allowed for local tests.')
    directory = Path(directory); directory.mkdir(parents=True, exist_ok=True)
    target = directory / 'model.safetensors'
    if target.is_file():
        progress('正在校验已有模型…', flush=True)
        if target.stat().st_size == size and digest(target) == expected_hash:
            progress('模型 SHA-256 校验通过。', flush=True); return target
        raise RuntimeError('Existing model checksum mismatch. Preserve it and reinstall in a clean model folder.')
    parts = directory / '.download-1mb-parts'; parts.mkdir(exist_ok=True)
    count = (size + chunk_size - 1) // chunk_size

    def download(index):
        start = index * chunk_size; end = min(size, start + chunk_size) - 1
        part = parts / str(index)
        if part.is_file() and not part.is_symlink() and part.stat().st_size == end - start + 1: return
        for attempt in range(retries + 1):
            url = sources[(index + attempt) % len(sources)]
            url += ('&' if '?' in url else '?') + f'part={index}&attempt={attempt}'
            request = Request(url, headers={'Range': f'bytes={start}-{end}', 'User-Agent': 'ShengJian-model-setup/0.3'})
            try:
                with urlopen(request, timeout=90) as response:
                    if response.status != 206 or response.headers.get('Content-Range') != f'bytes {start}-{end}/{size}':
                        raise ValueError('Server did not return the requested range')
                    data = response.read(end - start + 2)
                if len(data) != end - start + 1: raise ValueError('Wrong range length')
                temporary = parts / f'{index}.tmp'; temporary.write_bytes(data); os.replace(temporary, part)
                return
            except Exception as error:
                if hasattr(error, 'close'): error.close()
                if attempt == retries: raise RuntimeError(f'Model download failed at part {index + 1}; run setup again to resume.') from None
                time.sleep(min(10, attempt + 1))

    progress('正在下载千问模型（约2.46 GB，可断点续传）…', flush=True)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(download, index) for index in range(count)]
        for completed, future in enumerate(as_completed(futures), 1):
            future.result()
            if completed % 32 == 0 or completed == count: progress(f'模型下载 {completed * 100 // count}%', flush=True)
    assembling = directory / 'model.safetensors.assembling'
    with assembling.open('wb') as output:
        for index in range(count):
            with (parts / str(index)).open('rb') as source: shutil.copyfileobj(source, output)
    progress('正在校验模型完整性…', flush=True)
    if assembling.stat().st_size != size or digest(assembling) != expected_hash:
        suffix = uuid.uuid4().hex
        assembling.rename(directory / ('model.safetensors.invalid-' + suffix))
        parts.rename(directory / ('.download-invalid-' + suffix))
        raise RuntimeError('Model checksum mismatch; unverified weights were quarantined, not installed.')
    os.replace(assembling, target)
    shutil.rmtree(parts)
    progress('模型 SHA-256 校验通过。', flush=True)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    download_weights(parser.parse_args().directory)
