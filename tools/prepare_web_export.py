"""Prepare a Godot Web export for static hosting with small compressed assets.

python3 tools/prepare_web_export.py /absolute/path/to/export-directory
"""
from pathlib import Path
import gzip
import shutil
import re
import sys

directory = Path(sys.argv[1]).resolve()
project = Path(__file__).resolve().parents[1]
media = project / 'art/opening/intro.mp4'
player = project / 'web/opening_video.js'
welcome = project / 'art/opening/welcome.png'
loading_js = project / 'web/loading_screen.js'
loading_css = project / 'web/loading_screen.css'
if not all(path.is_file() for path in [media, player, welcome, loading_js, loading_css]):
    raise SystemExit('Opening video or browser player is missing; export from the complete project.')
wasm = directory / 'index.wasm'
compressed = directory / 'index.wasm.gz'
html = directory / 'index.html'
source = html.read_text(encoding='utf-8')
if 'id="compressed-godot-loader"' in source:
    raise SystemExit('This export has already been prepared; export fresh files first.')
source, progress_hooks = re.subn(r"('onProgress':\s*function\s*\(current, total\)\s*\{)", r'\1\n window.EatventureLoading.progress(current, total);', source)
source, error_hooks = re.subn(r'(function displayFailureNotice\(err\)\s*\{)', r'\1\n window.EatventureLoading.fail(err);', source)
markup = '''<section id="welcome-loading" aria-label="游戏加载中" aria-busy="true" data-state="loading">
<div class="loading-portrait"><img src="welcome.png" alt="小动物的小店" fetchpriority="high">
<div class="loading-controls"><span id="welcome-progress-label" role="status" aria-live="polite">正在加载小店…</span>
<progress id="welcome-progress" max="100" aria-label="资源加载进度"></progress>
<button id="welcome-retry" hidden type="button">刷新重试</button></div></div></section>'''
source, body_hooks = re.subn(r'(<body\b[^>]*>)', lambda match: match.group(0) + markup, source, count=1)
if (progress_hooks, error_hooks, body_hooks) != (1, 1, 1):
    raise SystemExit('Unsupported Godot HTML shell: loading hooks were not found exactly once.')
raw_size = wasm.stat().st_size
compressed.write_bytes(gzip.compress(wasm.read_bytes(), compresslevel=9, mtime=0))
shutil.copyfile(media, directory / 'opening.mp4')
shutil.copyfile(player, directory / 'opening_video.js')
shutil.copyfile(welcome, directory / 'welcome.png')
shutil.copyfile(loading_js, directory / 'loading_screen.js')
shutil.copyfile(loading_css, directory / 'loading_screen.css')
shim = f'''<script src="opening_video.js"></script>
<link rel="stylesheet" href="loading_screen.css">
<script src="loading_screen.js"></script>
<script id="compressed-godot-loader">
(() => {{
  const originalFetch = window.fetch.bind(window);
  window.fetch = async (input, options) => {{
    const url = new URL(typeof input === 'string' ? input : input.url, document.baseURI);
    if (!url.pathname.endsWith('/index.wasm')) return originalFetch(input, options);
    if (!('DecompressionStream' in window)) throw new Error('请使用较新的 Chrome、Edge 或 Firefox 浏览器试玩。');
    url.pathname += '.gz';
    const response = await originalFetch(url.href, options);
    if (!response.ok) throw new Error('游戏文件加载失败，请刷新重试。');
    return new Response(response.body.pipeThrough(new DecompressionStream('gzip')), {{
      headers: {{'Content-Type':'application/wasm','Content-Length':'{raw_size}'}}
    }});
  }};
}})();
</script>
<style>
#status-splash{{display:none!important}}
#status::before{{content:'煎饼果子摊';font:600 32px system-ui;color:#65492f;margin-bottom:16px}}
#status::after{{content:'正在支摊，马上开张…';font:16px system-ui;color:#81938c}}
#status-progress{{bottom:32%;height:8px;max-width:340px;accent-color:#92b29b}}
</style>
'''
source = source.replace('<title>eatvenLike</title>', '<title>煎饼果子摊 · 试玩</title>')
source = source.replace('<html lang="en">', '<html lang="zh-CN">')
html.write_text(source.replace('</head>', shim + '</head>'), encoding='utf-8')
wasm.unlink()
assert compressed.stat().st_size < 25 * 1024 * 1024
print(f'Web engine: {raw_size:,} bytes → {compressed.stat().st_size:,} compressed bytes')
