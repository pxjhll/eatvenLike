"""Exercise real export preparation and its media sidecars in temporary directories."""
from pathlib import Path
import gzip
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WebOpeningExportTests(unittest.TestCase):
    def test_prepared_export_contains_playable_media_and_player(self):
        with tempfile.TemporaryDirectory() as folder:
            export = Path(folder)
            wasm = b'wasm export fixture\0' * 300
            (export / 'index.wasm').write_bytes(wasm)
            (export / 'index.html').write_text('<html lang="en"><head><title>eatvenLike</title></head><body><canvas id="canvas"></canvas></body></html>', encoding='utf-8')
            command = [sys.executable, str(ROOT / 'tools/prepare_web_export.py'), str(export)]
            result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(gzip.decompress((export / 'index.wasm.gz').read_bytes()), wasm)
            self.assertFalse((export / 'index.wasm').exists())
            self.assertTrue((export / 'opening.mp4').is_file(), 'Web release must copy its MP4 outside the PCK')
            self.assertEqual((export / 'opening.mp4').read_bytes(), (ROOT / 'art/opening/intro.mp4').read_bytes())
            self.assertEqual((export / 'opening_video.js').read_bytes(), (ROOT / 'web/opening_video.js').read_bytes())
            self.assertIn('<script src="opening_video.js"></script>', (export / 'index.html').read_text(encoding='utf-8'))
            before = (export / 'index.html').read_bytes()
            repeated = subprocess.run(command, capture_output=True)
            self.assertNotEqual(repeated.returncode, 0, 'Double preparation must fail instead of injecting duplicate loaders')
            self.assertEqual(before, (export / 'index.html').read_bytes())


if __name__ == '__main__':
    unittest.main()
