"""Build the UI font subset: python3 tools/subset_font.py path/to/wqy-microhei.ttc.

The source font's complete license is distributed with the output in art/ui.
Retain glyphs from the checked-in subset so updating one screen preserves older UI text.
Requires fontTools only; not needed by the game runtime.
"""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
import sys

root = Path(__file__).resolve().parents[1]
text = ''.join(path.read_text(encoding='utf-8') for folder in ('presentation', 'game', 'content')
               for path in (root / folder).rglob('*') if path.suffix in ('.gd', '.tres', '.tscn'))
output = root / 'art/ui/graybox_font.ttf'
if output.exists():
    with TTFont(output) as current:
        text += ''.join(map(chr, current.getBestCmap()))
options = subset.Options()
options.layout_features = ['*']
font = TTFont(sys.argv[1], fontNumber=0)
subsetter = subset.Subsetter(options=options)
subsetter.populate(text=text + ''.join(chr(i) for i in range(32, 127)))
subsetter.subset(font)
font.save(output)
