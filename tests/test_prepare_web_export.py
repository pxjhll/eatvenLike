"""Exercise real export preparation and its media sidecars in temporary directories."""
from pathlib import Path
import gzip
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WebOpeningExportTests(unittest.TestCase):
    def test_unknown_shell_is_rejected_without_modifying_export(self):
        with tempfile.TemporaryDirectory() as folder:
            export = Path(folder)
            source = '<html><head></head><body><canvas></canvas></body></html>'
            (export / 'index.html').write_text(source, encoding='utf-8')
            (export / 'index.wasm').write_bytes(b'wasm fixture')
            result = subprocess.run([sys.executable, str(ROOT / 'tools/prepare_web_export.py'), str(export)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((export / 'index.html').read_text(encoding='utf-8'), source)
            self.assertTrue((export / 'index.wasm').exists())
            self.assertFalse((export / 'index.wasm.gz').exists())

    def test_prepared_export_contains_playable_media_and_player(self):
        with tempfile.TemporaryDirectory() as folder:
            export = Path(folder)
            wasm = b'wasm export fixture\0' * 300
            (export / 'index.wasm').write_bytes(wasm)
            (export / 'index.html').write_text('''<html lang="en"><head><title>eatvenLike</title></head>
<body><canvas id="canvas"></canvas><script>
function displayFailureNotice(err) { console.error(err); }
engine.startGame({'onProgress': function (current, total) {}});
</script></body></html>''', encoding='utf-8')
            command = [sys.executable, str(ROOT / 'tools/prepare_web_export.py'), str(export)]
            result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(gzip.decompress((export / 'index.wasm.gz').read_bytes()), wasm)
            self.assertFalse((export / 'index.wasm').exists())
            self.assertTrue((export / 'opening.mp4').is_file(), 'Web release must copy its MP4 outside the PCK')
            self.assertEqual((export / 'opening.mp4').read_bytes(), (ROOT / 'art/opening/intro.mp4').read_bytes())
            self.assertEqual((export / 'opening_video.js').read_bytes(), (ROOT / 'web/opening_video.js').read_bytes())
            self.assertIn('<script src="opening_video.js"></script>', (export / 'index.html').read_text(encoding='utf-8'))
            self.assertEqual((export / 'loading.mp4').read_bytes(), (ROOT / 'web/loading.mp4').read_bytes())
            self.assertEqual((export / 'loading-poster.jpg').read_bytes(), (ROOT / 'web/loading-poster.jpg').read_bytes())
            self.assertFalse((export / 'loading.gif').exists())
            self.assertEqual((export / 'loading-font.ttf').read_bytes(), (ROOT / 'art/ui/graybox_font.ttf').read_bytes())
            self.assertEqual((export / 'loading_screen.js').read_bytes(), (ROOT / 'web/loading_screen.js').read_bytes())
            self.assertEqual((export / 'loading_screen.css').read_bytes(), (ROOT / 'web/loading_screen.css').read_bytes())
            html = (export / 'index.html').read_text(encoding='utf-8')
            self.assertLess(html.index('id="welcome-loading"'), html.index('<canvas'))
            self.assertIn('id="welcome-animation" src="loading.mp4" poster="loading-poster.jpg" autoplay muted loop playsinline', html)
            self.assertIn('EatventureLoading.progress(current, total)', html)
            self.assertIn('EatventureLoading.fail(err)', html)
            self.assertIn('id="welcome-percentage"', html)
            self.assertIn('<button id="welcome-play" class="loading-caption" hidden type="button">加载完成，点击播放片头</button>', html)
            self.assertIn('美味正在准备中…', html)
            self.assertIn('小厨师们正在赶来，马上开饭！', html)
            self.assertNotIn('68%', html, 'Progress must not be baked into the loading UI')
            before = (export / 'index.html').read_bytes()
            repeated = subprocess.run(command, capture_output=True)
            self.assertNotEqual(repeated.returncode, 0, 'Double preparation must fail instead of injecting duplicate loaders')
            self.assertEqual(before, (export / 'index.html').read_bytes())


if __name__ == '__main__':
    unittest.main()
