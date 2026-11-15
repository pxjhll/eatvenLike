"""Formal source/resource boundary checks; runtime traces supply execution proof."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
CATALOG='content/template_shops.json'
LEGACY=re.compile(r'(?:serve_flow|single_action_context|handoff_action_context|reference_rules)\.gd|\b(?:ServeFlow\.(?:tick|_pick_good)|_tick_handoff\s*\(|_tick_single\s*\()')
SCENE_SCRIPTS={'res://presentation/shop/anchor_rect.gd','res://presentation/shop/shop_dining.gd','res://presentation/shop/modules/shop_module.gd'}
# Explicit shared schemas: a private implementation cannot acquire approval just
# by naming itself spec_*. New schemas require the same public capability review.
SCHEMA_SCRIPTS={'res://content/rules/spec_'+name+'.gd' for name in '''campaign campaign_shop city connection dish dispatch effect event flyer fulfillment goal_rules guide_step item layout material modifier order_option perk price seat_group shop shop_template staff_kind staff_rules stage station step stock_rule task upgrade_level upgrade_track'''.split()}
REQUIRED={
 'game/rules/shop_rules.gd':['runtime.step(STEP)'],
 'game/rules/template/runtime.gd':['runner.step(dt)','service.advance(dt)'],
 'game/rules/template/action_context.gd':['runner.inventory.pickup','runner.inventory.drop','runner.machines.engage'],
}
def issue(path,line,rule,message):return {'path':path,'line':line,'rule':rule,'message':message}
def inspect_source(path:str,source:str)->list[dict]:
    errors=[]
    code='\n'.join(line.split('#',1)[0] for line in source.splitlines())
    formal=(path.startswith('game/rules/template/') and Path(path).name not in ['legacy_adoption.gd','recipe_normalizer.gd']) or path in REQUIRED or path=='game/app/shop_session.gd' or path.startswith('presentation/shop/')
    for number,line in enumerate(code.splitlines(),1):
        if 'res://tests/' in line:errors.append(issue(path,number,'test_dependency','Production code must not load a test executor or fixture.'))
        if formal and LEGACY.search(line):errors.append(issue(path,number,'legacy_executor','Formal execution cannot load or call a legacy business executor.'))
        if path.startswith('game/rules/template/') and Path(path).name not in ['legacy_adoption.gd','recipe_normalizer.gd'] and (re.search(r'\bfulfillment\.handoff\b',line) or (Path(path).name!='session_state.gd' and re.search(r'\bshop\.id\b',line))):
            errors.append(issue(path,number,'mode_dispatch','Public capabilities cannot select behavior by shop identity or legacy mode.'))
        if path.startswith('presentation/'):
            write=re.search(r'\b(?:rules|runtime)\.(?:gold|revenue|sold|workers|roster|orders|customers|queue|stations|serve|movement|runner|service)(?:\.[\w]+|\[[^\]]*\])*\s*[+*/-]?=(?!=)',line)
            mutate=re.search(r'\b(?:rules|runtime)\.(?:runtime\.)?(?:runner\.inventory|service\.orders|service\.customers|workers|roster|serve|movement)(?:\.[\w]+|\[[^\]]*\])*\.(?:clear|append|erase|remove_at|seed|pickup|drop|reserve_\w+|complete_operation|cancel|step|advance)\(',line)
            if write or mutate:errors.append(issue(path,number,'ledger_write','Presentation must use commands and read-only frames, never commit business state.'))
    for call in REQUIRED.get(path,[]):
        if call not in code:errors.append(issue(path,1,'required_call','Missing actual common call: '+call))
    return errors

def inspect_resource(path:str,source:str)->list[dict]:
    errors=[]
    for number,line in enumerate(source.splitlines(),1):
        if line.lstrip().startswith(';'):continue
        if 'res://tests/' in line:errors.append(issue(path,number,'test_dependency','Formal resources cannot depend on historical test fixtures.'))
        if re.search(r'type="(?:GDScript|CSharpScript|ScriptExtension)"|script/source\s*=',line):errors.append(issue(path,number,'inline_script','Data examples cannot embed executable scripts.'))
        match=re.search(r'type="Script"[^\n]*path="([^"]+)"',line)
        if match:
            script=match[1]
            if script not in SCHEMA_SCRIPTS and script not in SCENE_SCRIPTS:
                errors.append(issue(path,number,'private_script','Use an approved shared schema or scene component: '+script))
    return errors

def inspect_project(root:Path)->list[dict]:
    errors=[]
    for directory in ['game','presentation']:
        for path in sorted((root/directory).rglob('*.gd')):errors.extend(inspect_source(path.relative_to(root).as_posix(),path.read_text(encoding='utf-8-sig')))
    catalog=root/CATALOG
    if not catalog.is_file():return errors+[issue(CATALOG,1,'catalog','Formal shop catalog is required.')]
    data=json.loads(catalog.read_text(encoding='utf-8-sig'))
    if data.get('version')!=1 or not isinstance(data.get('shops'),list) or not data['shops']:return errors+[issue(CATALOG,1,'catalog','Expected a nonempty version 1 shop catalog.')]
    pending=[];seen=set();ids=set();saves=set()
    for row in data['shops']:
        name=row.get('path','')
        path=Path(name)
        if path.is_absolute() or '..' in path.parts or not name.startswith('content/') or path.suffix!='.tres':errors.append(issue(CATALOG,1,'catalog','Invalid formal shop path: '+name));continue
        text=(root/path).read_text(encoding='utf-8-sig')
        body=text.split('[resource]')[-1]
        if not re.search(r'^runtime_template\s*=',body,re.M):errors.append(issue(name,1,'missing_template','Formal shops require an explicit public runtime template.'))
        for field,values in [('id',ids),('save_file',saves)]:
            match=re.search(r'^'+field+r'\s*=\s*"([^"]+)"',body,re.M)
            if not match or match[1] in values:errors.append(issue(name,1,'identity','Stable shop identity and save file must be unique.'))
            else:values.add(match[1])
        pending.append(name)
    while pending:
        name=pending.pop()
        if name in seen:continue
        seen.add(name);path=root/name
        if not path.is_file():errors.append(issue(name,1,'missing_resource','Referenced resource does not exist.'));continue
        text=path.read_text(encoding='utf-8-sig');errors.extend(inspect_resource(name,text))
        for resource in re.findall(r'path="res://([^"]+)"',text):
            if Path(resource).suffix in ['.tres','.tscn']:pending.append(resource)
    return errors

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output');args=parser.parse_args()
    errors=inspect_project(ROOT)
    if args.output:
        path=(ROOT/args.output).resolve()
        if not path.is_relative_to((ROOT/'_work').resolve()):parser.error('report must be under _work/')
        path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps({'errors':errors,'failures':len(errors)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for row in errors:print('FAIL {path}:{line} [{rule}] {message}'.format(**row))
    print(f'TEMPLATE BOUNDARY: {len(errors)} failures')
    return int(bool(errors))
if __name__=='__main__':raise SystemExit(main())
