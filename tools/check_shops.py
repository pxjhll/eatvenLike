"""One manifest for local and CI shop acceptance. Python standard library only."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tests/shop_acceptance.json'
ERRORS = re.compile(r'^\s*(?:SCRIPT ERROR:|ERROR:|FAIL(?:[:\s]|$))', re.MULTILINE)
FAILURE_COUNTS = re.compile(r'(?<!\d)[1-9]\d* (?:failures\b|个失败)')


def validate_manifest(data: dict, root: Path) -> None:
    if data.get('version') != 1 or not isinstance(data.get('jobs'), list) or not data['jobs']:
        raise ValueError('acceptance manifest requires version 1 and nonempty jobs')
    ids = set()
    for job in data['jobs']:
        name = job.get('id', '')
        if not re.fullmatch(r'[a-z][a-z0-9_]*', name) or name in ids:
            raise ValueError('job IDs must be unique identifiers')
        ids.add(name)
        if job.get('profile') not in ['headless', 'window', 'economy', 'web'] or job.get('kind') not in ['script', 'python', 'web']:
            raise ValueError(f'invalid profile/kind: {name}')
        if type(job.get('timeout')) is not int or not 0 < job['timeout'] <= 600:
            raise ValueError(f'invalid timeout: {name}')
        if not isinstance(job.get('args', []), list) or not all(isinstance(arg, str) for arg in job.get('args', [])):
            raise ValueError(f'args must be a string array: {name}')
        if job['kind'] == 'web':
            if job['profile'] != 'web':
                raise ValueError('web export belongs to web profile')
            continue
        path = Path(job.get('script', ''))
        if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] not in ['tests', 'tools']:
            raise ValueError(f'unsafe script path: {name}')
        if not (root / path).is_file():
            raise ValueError(f'missing script: {path}')
        if not isinstance(job.get('success'), str) or not job['success']:
            raise ValueError(f'missing completion banner: {name}')
        re.compile(job['success'])


def output_path(root: Path, value: str) -> Path:
    path = (root / value).resolve()
    if not path.is_relative_to((root / '_work').resolve()) or path == (root / '_work').resolve():
        raise ValueError('acceptance output must be a subdirectory of workspace _work/')
    return path


def select_jobs(data: dict, profile: str, names: list[str]) -> list[dict]:
    jobs = [job for job in data['jobs'] if job['profile'] == profile]
    if names:
        missing = set(names) - {job['id'] for job in jobs}
        if missing:
            raise ValueError('unknown jobs for selected profile: ' + ', '.join(sorted(missing)))
        jobs = [job for job in jobs if job['id'] in names]
    if not jobs:
        raise ValueError('no jobs selected')
    return jobs


def script_command(engine: str, root: Path, job: dict) -> list[str]:
    options=['--rendering-method','gl_compatibility','--audio-driver','Dummy'] if job['profile']=='window' else ['--headless']
    return [engine,*options,'--path',str(root),'-s',job['script']]


def run_command(command: list[str], root: Path, log: Path, timeout: float,
                userdata: Path, success: str | None = None) -> dict:
    userdata.mkdir(parents=True, exist_ok=True)
    log.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(APPDATA=str(userdata.resolve()), XDG_DATA_HOME=str(userdata.resolve()))
    options = {}
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
        options.update(startupinfo=startup, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
    else:
        options['start_new_session'] = True
    started = time.monotonic()
    result = {'command': command, 'status': 'failed', 'returncode': None,
              'seconds': 0.0, 'reason': '', 'log': str(log)}
    text = ''
    try:
        process = subprocess.Popen(command, cwd=root, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, encoding='utf-8',
                                   errors='replace', **options)
        try:
            text, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            text, _ = process.communicate(timeout=10)
            result['reason'] = f'timed out after {timeout}s'
        result['returncode'] = process.returncode
        if not result['reason']:
            if process.returncode != 0:
                result['reason'] = f'exit {process.returncode}'
            elif ERRORS.search(text) or FAILURE_COUNTS.search(text):
                result['reason'] = 'engine/test error in output despite zero exit'
            elif success and not re.search(success, text, re.MULTILINE):
                result['reason'] = 'required completion banner missing'
            else:
                result['status'] = 'passed'
    except (OSError, subprocess.SubprocessError) as error:
        result['reason'] = str(error)
    log.write_text(text, encoding='utf-8')
    result['seconds'] = round(time.monotonic() - started, 3)
    return result


def run_web(engine: str, root: Path, output: Path, job: dict, existing: Path | None) -> dict:
    """Check the actual exported binary scenes, not merely pack creation exit code."""
    started = time.monotonic()
    folder = output / job['id']
    folder.mkdir(parents=True, exist_ok=True)
    pack = existing or folder / 'check.pck'
    source = folder / 'scenes-source.txt'
    exported = folder / 'scenes-export.txt'
    dump = str(root / 'tests/dump_shop_scenes.gd')
    user = folder / 'userdata/session-lifecycle-userdata'
    commands = [([engine, '--headless', '--path', str(root), '-s', dump, '--', str(source)], 'source', r'shop scene nodes: [1-9]\d*')]
    if existing is None:
        commands.append(([engine, '--headless', '--path', str(root), '--export-pack', 'Web', str(pack)], 'export', None))
    commands.append(([engine, '--headless', '--main-pack', str(pack), '-s', dump, '--', str(exported)], 'binary', r'shop scene nodes: [1-9]\d*'))
    stages = []
    reason = ''
    for command, name, success in commands:
        stage = run_command(command, root, folder / f'{name}.log', job['timeout'], user, success)
        stages.append(stage)
        if stage['status'] != 'passed':
            reason = name + ': ' + stage['reason']
            break
    size = pack.stat().st_size if pack.is_file() else 0
    if not reason and (size == 0 or size >= 24 * 1024 * 1024):
        reason = f'pack size {size} bytes exceeds limit or is empty'
    if not reason and source.read_bytes() != exported.read_bytes():
        reason = 'source and exported scene nodes differ'
    return {'id': job['id'], 'status': 'failed' if reason else 'passed', 'reason': reason,
            'seconds': round(time.monotonic() - started, 3), 'pack_bytes': size, 'stages': stages}


def source_hashes(root: Path) -> dict:
    result = {}
    for directory in ['content', 'game', 'presentation', 'tests', 'tools']:
        for path in sorted((root / directory).rglob('*')):
            if path.suffix in ['.gd', '.tscn', '.tres', '.py', '.json']:
                result[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', default='godot')
    parser.add_argument('--profile', choices=['headless', 'window', 'economy', 'web'], default='headless')
    parser.add_argument('--only', action='append', default=[])
    parser.add_argument('--output', default='_work/shop-acceptance/' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + f'-{os.getpid()}')
    parser.add_argument('--pack', help='validate an already exported pack (web profile only)')
    parser.add_argument('--list', action='store_true')
    args = parser.parse_args(argv)
    try:
        data = json.loads(MANIFEST.read_text(encoding='utf-8'))
        validate_manifest(data, ROOT)
        jobs = select_jobs(data, args.profile, args.only)
        output = output_path(ROOT, args.output)
        if args.pack and args.profile != 'web':
            raise ValueError('--pack requires web profile')
        existing = (ROOT / args.pack).resolve() if args.pack else None
        if existing and (not existing.is_file() or existing.suffix != '.pck'):
            raise ValueError('--pack must be an existing .pck file')
        if args.list:
            for job in jobs:
                print(job['id'], job.get('script', job['kind']))
            return 0
        candidate = (ROOT / args.engine).resolve()
        engine = str(candidate) if candidate.is_file() else shutil.which(args.engine)
        if not engine:
            raise ValueError('Godot executable not found; pass --engine')
    except (ValueError, OSError) as error:
        print(f'FAIL acceptance arguments: {error}', file=sys.stderr)
        return 2
    output.mkdir(parents=True, exist_ok=True)
    before = source_hashes(ROOT)
    report = {'version': 1, 'generated_utc': datetime.now(timezone.utc).isoformat(),
              'profile': args.profile, 'jobs': [], 'sources': before}
    res_output = 'res://' + output.relative_to(ROOT).as_posix()
    for job in jobs:
        print('RUN', job['id'], flush=True)
        if job['kind'] == 'web':
            result = run_web(engine, ROOT, output, job, existing)
        else:
            extra = [arg.format(output=str(output), res_output=res_output, root=str(ROOT)) for arg in job.get('args', [])]
            command = [sys.executable, str(ROOT / job['script']), *extra] if job['kind'] == 'python' else script_command(engine, ROOT, job)
            if job['kind'] == 'script' and extra:
                command.extend(['--', *extra])
            result = run_command(command, ROOT, output / f"{job['id']}.log", job['timeout'],
                                 output / 'userdata' / job['id'] / 'session-lifecycle-userdata', job['success'])
            result['id'] = job['id']
        report['jobs'].append(result)
        print(result['status'].upper(), job['id'], f"{result['seconds']}s", result['reason'], flush=True)
    after = source_hashes(ROOT)
    report['source_drift'] = [path for path in before.keys() | after.keys()
                              if before.get(path) != after.get(path)]
    report['failed'] = sum(job['status'] != 'passed' for job in report['jobs']) + bool(report['source_drift'])
    (output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"SHOP ACCEPTANCE: {len(jobs)} jobs, {report['failed']} failures; {output / 'summary.json'}", flush=True)
    return 1 if report['failed'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
