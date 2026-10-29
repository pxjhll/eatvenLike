"""Original vector graybox assets. Run with Python, then rasterize.gd in Godot.

No third-party art. SVG source and PNG exports share bottom-center anchors.
"""
from pathlib import Path
import json
import math

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / 'svg'
OUT.mkdir(parents=True, exist_ok=True)
INK = '#45545a'
assets = []


def svg(w, h, shapes):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><g stroke="{INK}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round">{shapes}</g></svg>'


def rect(x, y, w, h, fill, r=6, stroke=INK):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}"/>'


def ellipse(x, y, rx, ry, fill, stroke=INK):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{stroke}"/>'


def line(x1, y1, x2, y2, stroke=INK, width=3):
    return f'<path d="M{x1},{y1} L{x2},{y2}" fill="none" stroke="{stroke}" stroke-width="{width}"/>'


def poly(points, fill):
    return f'<polygon points="{points}" fill="{fill}"/>'


def save(name, category, w, h, shapes, **metadata):
    source = OUT / f'{name}.svg'
    source.write_text(svg(w, h, shapes))
    assets.append({'id': name, 'source': f'art_src/graybox/svg/{name}.svg',
                   'path': f'art/{category}/{name}.png', 'size': [w, h],
                   'anchor': 'bottom_center', **metadata})


def shadow(w=128, y=150):
    return f'<ellipse cx="{w/2}" cy="{y}" rx="{w*.36}" ry="8" fill="#37464b" fill-opacity="0.13" stroke="none"/>'


def cabinet(color, top, side):
    return shadow() + rect(10, 55, 96, 86, color) + poly('106,55 122,41 122,128 106,141', side) + poly('10,55 26,41 122,41 106,55', top)


def bread(x=64, y=84, scale=1):
    return (f'<g transform="translate({x},{y}) scale({scale})">'
            + rect(-26, -15, 52, 30, '#dca269', 12)
            + line(-12, -8, -16, 4, '#fff0c0', 3)
            + line(2, -8, -2, 4, '#fff0c0', 3)
            + line(16, -8, 12, 4, '#fff0c0', 3) + '</g>')


def machines():
    s = cabinet('#e2c7a0', '#f5e7cf', '#bc9f79')
    s += rect(24, 61, 64, 64, '#f8eedb', 14) + line(25, 72, 87, 72)
    s += ellipse(56, 94, 14, 18, '#d8be81') + line(56, 108, 56, 80, '#fff4d3')
    save('mach_flour_bin', 'machine', 128, 160, s)
    s = shadow() + rect(20, 83, 12, 57, '#ab8d6c', 3) + rect(94, 83, 12, 57, '#ab8d6c', 3)
    s += rect(8, 62, 105, 32, '#cba478', 5) + poly('8,62 26,45 124,45 113,62', '#edd4ac')
    s += ellipse(66, 59, 23, 12, '#fff0c7') + line(28, 72, 86, 72, '#8a6747', 8)
    save('mach_dough_table', 'machine', 128, 160, s)
    s = cabinet('#d28b78', '#e6b7a3', '#aa7165')
    s += rect(23, 68, 70, 58, '#3e5059', 8) + rect(30, 83, 56, 34, '#9e6d50', 5)
    s += bread(58, 102, .75) + line(29, 75, 87, 75, '#f6dfc4', 4)
    s += ellipse(36, 49, 3, 3, '#f9eac8') + ellipse(51, 49, 3, 3, '#52626b')
    save('mach_oven', 'machine', 128, 160, s)
    s = cabinet('#83a9bd', '#bed4df', '#60889c')
    s += ellipse(62, 82, 28, 27, '#e2edf0')
    for angle in range(0, 360, 60):
        a = math.radians(angle)
        s += line(62 + math.cos(a)*8, 82 + math.sin(a)*8, 62 + math.cos(a)*22, 82 + math.sin(a)*22, '#6f8a94')
    s += rect(24, 115, 66, 13, '#40525d', 3)
    save('mach_slicer', 'machine', 128, 160, s)
    s = shadow() + rect(14, 26, 96, 114, '#d3b68d', 5) + rect(24, 34, 75, 94, '#f1e4cd', 3)
    s += line(22, 69, 101, 69, '#a78560', 7) + line(22, 103, 101, 103, '#a78560', 7)
    save('mach_rack', 'machine', 128, 160, s)
    s = shadow(256, 119) + rect(10, 49, 226, 67, '#a2bcb0', 8)
    s += poly('10,49 28,31 251,31 236,49', '#fff5df') + poly('236,49 251,31 251,100 236,116', '#789b90')
    s += rect(35, 69, 164, 29, '#e8ecd9', 4) + bread(116, 45, .85)
    save('mach_counter', 'machine', 256, 128, s)


def animals():
    colors = {'rabbit': ('#eee4d3', '#8db8ac'), 'bear': ('#bd916d', '#d9b765'), 'cat': ('#adb8bd', '#d9967d'), 'customer': ('#dac7ad', '#a9b6cb')}
    for kind, (fur, apron) in colors.items():
        columns = 6 if kind == 'customer' else 10
        content = ''
        for direction in range(3):
            for frame in range(columns):
                if frame < 2:
                    bob, swing, arm = frame, 0, 0
                elif frame < 6:
                    bob, swing, arm = (frame % 2) * 2, (-1 if frame % 2 else 1)*7, 0
                else:
                    bob, swing, arm = (frame % 2), 0, (frame % 2)*9
                head_x = 64 + (7 if direction == 2 else 0)
                s = shadow(y=151)
                s += ellipse(46 + swing, 142, 12, 6, '#697979') + ellipse(82 - swing, 142, 12, 6, '#697979')
                s += rect(38, 92-bob, 51, 47, apron, 15)
                if kind != 'customer':
                    s += rect(47, 102-bob, 34, 28, '#f6f0df', 5) + line(48, 118-bob, 80, 118-bob, '#cec7b5', 2)
                s += ellipse(30, 110-bob-arm, 11, 13, fur) + ellipse(97, 110-bob+arm, 11, 13, fur)
                if kind == 'rabbit':
                    s += ellipse(head_x-20, 35-bob, 11, 29, fur) + ellipse(head_x+20, 35-bob, 11, 29, fur)
                    s += ellipse(head_x-20, 34-bob, 4, 19, '#d6aaa1', 'none') + ellipse(head_x+20, 34-bob, 4, 19, '#d6aaa1', 'none')
                elif kind == 'cat':
                    s += poly(f'{head_x-31},65 {head_x-30},30 {head_x-7},50', fur) + poly(f'{head_x+31},65 {head_x+30},30 {head_x+7},50', fur)
                else:
                    s += ellipse(head_x-28, 52-bob, 13, 15, fur) + ellipse(head_x+28, 52-bob, 13, 15, fur)
                s += ellipse(head_x, 75-bob, 37, 32, fur)
                if direction != 1:
                    s += ellipse(head_x+4, 84-bob, 20, 15, '#f3e6ce', 'none')
                    for eye_x in ([head_x+14] if direction == 2 else [head_x-13, head_x+13]):
                        s += ellipse(eye_x, 72-bob, 3, 4, '#405058', 'none')
                    s += ellipse(head_x+5, 82-bob, 4, 3, '#6b5b54', 'none')
                    s += line(head_x, 91-bob, head_x+9, 91-bob, '#79675c', 2)
                if frame >= 6:
                    s += line(32, 117-bob, 95, 117-bob, '#ab835c', 6)
                content += f'<g transform="translate({frame*128},{direction*160})">{s}</g>'
        save('char_'+kind, 'char', 128*columns, 480, content, frame_size=[128,160], columns=columns, rows=3, directions=['down','up','side'], idle=[0,1], walk=[2,3,4,5], work=[] if kind=='customer' else [6,7,8,9], fps=8)


def environment():
    s = rect(0,0,128,128,'#dfe9e8',0,'none')
    for x,y in [(0,0),(64,64)]:
        s += rect(x,y,64,64,'#cfdfdf',0,'none')
    s += line(64,0,64,128,'#f4f8f4',2) + line(0,64,128,64,'#f4f8f4',2)
    save('env_kitchen_floor','env',128,128,s)
    s = rect(0,0,128,128,'#eedfc6',0,'none')
    for y in [32,64,96]:
        s += line(0,y,128,y,'#d9c5a6',2)
    s += line(42,0,42,32,'#d9c5a6',2)+line(92,32,92,64,'#d9c5a6',2)+line(52,64,52,96,'#d9c5a6',2)
    save('env_front_floor','env',128,128,s)
    save('env_divider','env',128,32,rect(0,0,128,30,'#f4ead9',3)+line(0,28,128,28,'#bfbaaa',4))
    save('env_window','env',128,96,rect(2,3,124,80,'#ece3cc',8)+rect(12,12,104,56,'#a5bab1',4)+rect(0,68,128,18,'#f8eedb',4))


def items():
    save('item_flour','item',64,64,shadow(64,56)+rect(14,12,36,42,'#fff0cd',8)+line(15,22,49,22)+ellipse(32,37,7,10,'#d9bd7a')+line(32,29,32,46,'#f5ead2',2))
    save('item_dough','item',64,64,shadow(64,54)+ellipse(32,36,25,17,'#fff0c4')+line(23,28,39,28,'#fff9e7',3))
    save('item_bread','item',64,64,shadow(64,55)+bread(32,35,1))
    save('item_toast','item',64,64,shadow(64,55)+rect(11,13,42,40,'#cb945f',9)+rect(17,18,30,29,'#f9e9bb',6))


def icons():
    shapes = [
        ellipse(32,32,23,23,'#e8c766')+line(32,18,32,46,'#fff1ba',5),
        line(20,52,20,10)+poly('20,12 49,12 42,25 20,25','#93b6a7'),
        rect(7,20,50,28,'#98a9b0')+line(20,26,33,34,'white')+line(33,34,20,42,'white'),
        rect(10,12,44,44,'#cf8a77')+rect(18,25,28,23,'#45545a'),
        ellipse(32,30,21,21,'#a9c7d5')+line(17,16,47,46),
        rect(18,23,28,29,'#c9d0cc')+line(13,18,51,18)+line(26,13,38,13),
        ellipse(25,24,12,12,'#abc5b4')+rect(9,40,39,13,'#abc5b4')+line(51,24,51,43)+line(43,33,59,33),
        ellipse(32,27,18,19,'#e5ce83')+line(26,51,38,51),
        '<path d="M48 24 A21 21 0 1 0 49 43 M48 10 V25 H33" fill="none"/>',
        poly('32,9 54,33 42,33 42,53 22,53 22,33 10,33','#a9c5b0'),
        rect(14,28,36,28,'#b6bcb8')+'<path d="M22 28 V19 A10 10 0 0 1 42 19 V28" fill="none"/>',
        '<path d="M15 25 A20 20 0 0 1 50 22 L52 9 M50 22 L36 20 M49 40 A20 20 0 0 1 15 43 L12 55 M15 43 L28 44" fill="none"/>',
        line(18,18,46,46)+line(46,18,18,46),
        line(10,24,53,24)+poly('53,24 42,16 42,32','#98b6a6')+line(53,42,10,42)+poly('10,42 21,34 21,50','#98b6a6'),
        rect(12,10,40,45,'#94b1c1')+rect(22,12,22,14,'#eff2e6',2)+rect(21,35,24,19,'#eff2e6',2),
        rect(10,12,44,40,'#c5cec9')+line(20,22,44,22)+line(20,32,40,32)+line(20,42,36,42),
    ]
    names=['coin','goal','belt','oven','slicer','delete','hire','hint','reset','upgrade','lock','rotate','close','assign','save','debug']
    atlas=''
    for i,s in enumerate(shapes):
        atlas += f'<g transform="translate({(i%4)*64},{(i//4)*64})">{s}</g>'
    save('ui_icons','ui',256,256,atlas,icons={name:[(i%4)*64,(i//4)*64,64,64] for i,name in enumerate(names)})


machines()
animals()
environment()
items()
icons()
(ROOT/'art'/'graybox_manifest.json').write_text(json.dumps({'version':1,'style':'2d_three_quarter_graybox','assets':assets},indent=2))
print(f'{len(assets)} original SVG sources; export PNGs with Godot rasterize.gd')
