#!/usr/bin/env python3
"""Persistent offline Qwen3-ASR worker. Audio exists only as PCM in pipes and memory."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import sys

for name in ("HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE", "HF_HUB_DISABLE_TELEMETRY"):
    os.environ[name] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"
sys.dont_write_bytecode = True


def emit(value):
    sys.stdout.write(json.dumps(value, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def read_exact(stream, count):
    data = bytearray()
    while len(data) < count:
        chunk = stream.read(count - len(data))
        if not chunk:
            raise EOFError("incomplete PCM frame")
        data.extend(chunk)
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, type=Path)
    args = parser.parse_args()
    # Library diagnostics must never corrupt stdout's protocol.
    with contextlib.redirect_stdout(sys.stderr):
        import mlx.core as mx
        import numpy as np
        from mlx_audio.stt.utils import load_model
        model = load_model(args.model, strict=True)
        if model.sample_rate != 16000:
            raise ValueError("expected 16kHz model")
    emit({"event": "ready", "sample_rate": 16000})
    source = sys.stdin.buffer
    while header := source.readline(65537):
        request = json.loads(header)
        count = request.get("sample_count")
        if request.get("op") != "transcribe" or not isinstance(count, int) or not 0 < count <= 16000 * 60:
            raise ValueError("invalid PCM request")
        pcm = read_exact(source, count * 4)
        audio = np.frombuffer(pcm, dtype="<f4").copy()
        del pcm
        try:
            if not np.all(np.isfinite(audio)):
                raise ValueError("nonfinite PCM")
            duration = len(audio) / 16000
            budget = min(2048, max(256, int(duration * 30) + 128))
            with contextlib.redirect_stdout(sys.stderr):
                result = model.generate(audio, language=None, temperature=0.0, max_tokens=budget,
                    system_prompt=request.get("prompt", "")[:4000] or None, verbose=False)
                if result.generation_tokens >= budget:
                    raise ValueError("transcription token limit reached")
                text = result.text.strip()
                mx.clear_cache()
            emit({"event": "result", "request_id": request["request_id"], "text": text})
        except Exception:
            # Only a controlled error crosses the protocol; audio, prompts and internal paths are not logged.
            emit({"event": "error", "request_id": request.get("request_id"), "reason": "inference_failed"})
        finally:
            del audio


if __name__ == "__main__":
    try:
        main()
    except (EOFError, BrokenPipeError):
        pass
    except Exception:
        emit({"event": "error", "reason": "worker_failed"})
        sys.exit(1)
