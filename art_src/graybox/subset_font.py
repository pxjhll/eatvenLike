"""Build the UI font subset: python3 art_src/graybox/subset_font.py path/to/wqy-microhei.ttc.

The source font's complete license is distributed with the output in art/ui.
Requires fontTools only; not needed by the game runtime.
"""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
import sys

root = Path(__file__).resolve().parents[2]
text = ''.join(path.read_text(encoding='utf-8') for folder in ('presentation', 'game', 'content')
               for path in (root / folder).rglob('*') if path.suffix in ('.gd', '.tres', '.tscn'))
options = subset.Options()
options.layout_features = ['*']
font = TTFont(sys.argv[1], fontNumber=0)
subsetter = subset.Subsetter(options=options)
subsetter.populate(text=text + ''.join(chr(i) for i in range(32, 127)))
subsetter.subset(font)
font.save(root / 'art/ui/graybox_font.ttf')
