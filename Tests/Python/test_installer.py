"""Exercise resumable downloads against a tiny local server, never real model endpoints."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
import hashlib
import importlib.util
import tempfile
import unittest
from unittest.mock import patch
from urllib.request import build_opener, ProxyHandler

SPEC = importlib.util.spec_from_file_location('download_qwen', Path(__file__).parents[2] / 'scripts/download_qwen.py')
module = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(module)


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.opener = patch.object(module, 'urlopen', build_opener(ProxyHandler({})).open); self.opener.start()
        self.temporary = tempfile.TemporaryDirectory(); self.root = Path(self.temporary.name)
        self.data = b'public-synthetic-weights' * 32; self.requests = []; self.ignore_range = False; self.corrupt = False
        owner = self
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                owner.requests.append(self.headers.get('Range'))
                start, end = map(int, self.headers['Range'].removeprefix('bytes=').split('-'))
                data = owner.data[start:end + 1]
                if owner.corrupt: data = b'X' * len(data)
                self.send_response(200 if owner.ignore_range else 206)
                self.send_header('Content-Range', f'bytes {start}-{end}/{len(owner.data)}')
                self.end_headers(); self.wfile.write(data)
            def log_message(self, *args): pass
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.temporary.cleanup(); self.opener.stop()
    def download(self):
        return module.download_weights(self.root, sources=[f'http://127.0.0.1:{self.server.server_port}/weights'],
            size=len(self.data), expected_hash=hashlib.sha256(self.data).hexdigest(), chunk_size=64, workers=2, retries=0, progress=lambda *a, **k: None)
    def test_file_and_remote_http_schemes_are_rejected(self):
        for source in ('file:///etc/hosts', 'http://example.org/model'):
            with self.assertRaises(ValueError): module.download_weights(self.root, sources=[source])
    def test_verified_download_and_existing_file_check(self):
        path = self.download(); self.assertEqual(path.read_bytes(), self.data)
        count = len(self.requests); self.assertEqual(self.download(), path); self.assertEqual(count, len(self.requests))
        self.assertFalse((self.root / '.download-1mb-parts').exists())
    def test_resume_reuses_complete_parts(self):
        parts = self.root / '.download-1mb-parts'; parts.mkdir(); (parts / '0').write_bytes(self.data[:64])
        self.download(); self.assertNotIn('bytes=0-63', self.requests)
    def test_server_ignoring_range_does_not_install(self):
        self.ignore_range = True
        with self.assertRaises(RuntimeError): self.download()
        self.assertFalse((self.root / 'model.safetensors').exists())
    def test_corrupt_payload_is_quarantined(self):
        self.corrupt = True
        with self.assertRaises(RuntimeError): self.download()
        self.assertFalse((self.root / 'model.safetensors').exists())
        self.assertTrue(list(self.root.glob('model.safetensors.invalid-*')))
    def test_existing_invalid_model_is_preserved(self):
        path = self.root / 'model.safetensors'; path.write_bytes(b'preserve-me')
        with self.assertRaises(RuntimeError): self.download()
        self.assertEqual(path.read_bytes(), b'preserve-me'); self.assertEqual(self.requests, [])


if __name__ == '__main__': unittest.main()
