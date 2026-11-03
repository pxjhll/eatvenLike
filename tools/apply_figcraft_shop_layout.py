"""Apply the approved FigCraft placement snapshot without resampling any game PNG."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'art_src/figcraft_layout_2026_11_03/placement.json'
SCENE = ROOT / 'presentation/reference/shop_art.tscn'

def vector(x, y):
    return f'Vector2({x:.9g}, {y:.9g})'

def apply():
    from PIL import Image
    data = json.loads(FIXTURE.read_text(encoding='utf-8'))
    text = SCENE.read_text(encoding='utf-8')
    pieces = re.split(r'(?=^\[node )', text, flags=re.M)
    prefix = pieces.pop(0)
    blocks = {}
    headers = {}
    for piece in pieces:
        header, _, body = piece.partition('\n')
        name = re.search(r'name="([^"]+)"', header)[1]
        parent = re.search(r'parent="([^"]+)"', header)
        path = name if not parent or parent[1] == '.' else parent[1] + '/' + name
        headers[path] = header
        blocks[path] = dict(re.findall(r'^([^\n=]+?) = (.*)$', body, re.M))
    resources = {path: key for path,key in re.findall(r'\[ext_resource type="Texture2D"[^\n]*path="([^"]+)" id="([^"]+)"\]', prefix)}
    def resource(path):
        nonlocal prefix
        if path not in resources:
            key = f'figcraft_texture_{len(resources)}'
            resources[path] = key
            prefix += f'[ext_resource type="Texture2D" path="{path}" id="{key}"]\n\n'
        return f'ExtResource("{resources[path]}")'
    anchors = {'Sortables/IngredientTable':(140,294.5), 'Sortables/MachineTable':(412,305.12), 'Sortables/Sealer':(622,391), 'Sortables/PrepBench':(84,616.88), 'Sortables/BeltVertical':(626,586.5), 'Sortables/Rack':(613,687.06), 'Sortables/Checkout':(360,857.16)}
    for path, point in anchors.items(): blocks[path]['position'] = vector(*point)
    blocks['Sortables/MachineTable/ConnectorPipe'].pop('visible',None)
    blocks['Sortables/BeltHorizontal']['visible'] = 'false'
    for suffix in ['A','B','C']:
        path = 'Sortables/BeltHorizontal/Direction'+suffix
        blocks.pop(path,None)
        headers.pop(path,None)
    def origin(path):
        if not path or path == 'ShopArt': return (0,0)
        b = blocks[path]
        parent = path.rpartition('/')[0]
        p = origin(parent)
        match = re.fullmatch(r'Vector2\(([^,]+), ([^)]+)\)',b.get('position','Vector2(0, 0)'))
        return (p[0]+float(match[1]),p[1]+float(match[2]))
    for row in data['sprites']:
        path = row['node']
        if '/DiningArea/' in path: continue # The existing dining presenter constructs these named sprites.
        b = blocks[path]
        parent = path.rpartition('/')[0]
        parent_origin = origin(parent)
        width,height = Image.open(ROOT/row['texture'].removeprefix('res://')).size
        if 'region' in row: width,height = row['region'][2:]
        for key in ['script','asset_path','display_width','offset','rotation']:
            b.pop(key,None)
        b['position'] = vector(row['transform'][4]-parent_origin[0],row['transform'][5]-parent_origin[1])
        b['scale'] = vector(row['width']/width,row['height']/height)
        b['texture'] = resource(row['texture'])
        b['centered'] = 'false'
        b['metadata/layout_group'] = json.dumps(row['group'],ensure_ascii=False)
        b['metadata/unlock_rule'] = json.dumps(data['rules'][row['group']])
    arrow = data['polygons'][0]
    path = arrow['node']
    headers[path] = '[node name="Direction" type="Polygon2D" parent="Sortables/BeltVertical"]'
    parent_origin = origin('Sortables/BeltVertical')
    coords = [f'{p[j]-parent_origin[j]:.9g}' for p in arrow['points'] for j in (0,1)]
    blocks[path] = {'z_index':'-1', 'color':'Color(0.8509804, 0.8313726, 0.7882353, 1)', 'polygon':'PackedVector2Array('+', '.join(coords)+')', 'metadata/layout_group':'"箭头"', 'metadata/unlock_rule':'"seal"'}
    # Reorder whole prop subtrees so a sprite remains after its parent declaration.
    paths = list(blocks)
    for behind, foreground in data.get('draw_before', []):
        subtree = [p for p in paths if p == behind or p.startswith(behind + '/')]
        paths = [p for p in paths if p not in subtree]
        index = paths.index(foreground)
        paths[index:index] = subtree
    SCENE.write_text(prefix.rstrip()+'\n\n'+'\n\n'.join(headers[p]+'\n'+'\n'.join(k+' = '+v for k,v in blocks[p].items()) for p in paths)+'\n',encoding='utf-8')
    print(f'Applied {len(data["sprites"])} approved sprite placements and the conveyor arrow')

if __name__ == '__main__': apply()
