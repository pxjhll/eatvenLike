"""Prepare a Godot Web export for static hosting with small compressed assets.

python3 tools/prepare_web_export.py /absolute/path/to/export-directory
"""
from pathlib import Path
import gzip
import sys

directory = Path(sys.argv[1]).resolve()
wasm = directory / 'index.wasm'
compressed = directory / 'index.wasm.gz'
raw_size = wasm.stat().st_size
compressed.write_bytes(gzip.compress(wasm.read_bytes(), compresslevel=9, mtime=0))
html = directory / 'index.html'
source = html.read_text()
shim = f'''<script id="compressed-godot-loader">
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
#status::before{{content:'面包小店';font:600 32px system-ui;color:#42565c;margin-bottom:16px}}
#status::after{{content:'正在准备生产线…';font:16px system-ui;color:#81938c}}
#status-progress{{bottom:32%;height:8px;max-width:340px;accent-color:#92b29b}}
</style>
'''
if 'id="compressed-godot-loader"' in source:
    raise SystemExit('This export has already been prepared; export fresh files first.')
source = source.replace('<title>eatvenLike</title>', '<title>面包小店 · 灰盒试玩</title>')
source = source.replace('<html lang="en">', '<html lang="zh-CN">')
html.write_text(source.replace('</head>', shim + '</head>'))
wasm.unlink()
assert compressed.stat().st_size < 25 * 1024 * 1024
print(f'Web engine: {raw_size:,} bytes → {compressed.stat().st_size:,} compressed bytes')
