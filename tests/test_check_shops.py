"""Acceptance runner contracts use real child processes, not mocked success."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / 'tools/check_shops.py'
MANIFEST = ROOT / 'tests/shop_acceptance.json'


class AcceptanceTests(unittest.TestCase):
    def tool(self):
        self.assertTrue(TOOL.is_file(), 'one local/CI acceptance runner must exist')
        spec = importlib.util.spec_from_file_location('check_shops', TOOL)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_manifest_retains_existing_ci_entry_points_and_new_gates(self):
        self.assertTrue(MANIFEST.is_file(), 'shared acceptance manifest must exist')
        data = json.loads(MANIFEST.read_text(encoding='utf-8'))
        self.tool().validate_manifest(data, ROOT)
        scripts = {job.get('script') for job in data['jobs']}
        required = {'tests/run_all.gd', 'tools/validate_shops.gd', 'tools/sync_shop_layouts.gd',
                    'tests/baselines/record_rules.gd', 'tests/render_session_lifecycle.gd',
                    'tests/render_progress_retry.gd', 'tests/render_command_contracts.gd',
                    'tests/render_presentation_boundary.gd', 'tests/render_shop_audio.gd',
                    'tests/render_shared_movement.gd', 'tests/render_actor_actions.gd',
                    'tests/render_flow_composition.gd', 'tests/render_scene_modules.gd',
                    'tests/render_actor_presentation.gd', 'tests/render_stirfry_migration.gd',
                    'tests/render_first_shops_migration.gd', 'tests/render_shop_onboarding.gd',
                    'tools/shop_rhythm.gd', 'tools/shop_progression.gd', 'tests/render_work_actions.gd'}
        for shop in ['tea', 'pancake', 'stirfry', 'noodle', 'guide', 'extend']:
            required.add(f'tests/render_shop_{shop}.gd')
        for name in ['rabbit_frame_atlas', 'rabbit_game_visuals', 'gray_cat_atlas',
                     'gray_cat_game', 'work_action_atlases', 'work_actions']:
            required.add(f'tests/test_{name}.gd')
        self.assertLessEqual(required, scripts)
        self.assertTrue(any(job['kind'] == 'web' for job in data['jobs']))

    def run_child(self, code, timeout=3, success=None):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            result = self.tool().run_command([sys.executable, '-c', code], ROOT,
                                            base / 'test.log', timeout,
                                            base / 'session-lifecycle-userdata', success)
            return result, (base / 'test.log').read_text(encoding='utf-8')

    def test_zero_exit_with_engine_error_is_failure(self):
        result, log = self.run_child("print('SCRIPT ERROR: deliberate'); print('OK')", success='OK')
        self.assertEqual(result['status'], 'failed')
        self.assertIn('SCRIPT ERROR', log)
        result, _ = self.run_child("print('SHOP: 3 failures'); print('OK')", success='OK')
        self.assertEqual(result['status'], 'failed')

    def test_real_success_and_isolated_child_environment(self):
        code = "import os; print('OK ' + os.environ['APPDATA'] + ' ' + os.environ['XDG_DATA_HOME'])"
        result, log = self.run_child(code, success='OK ')
        self.assertEqual(result['status'], 'passed')
        self.assertIn('session-lifecycle-userdata', log)

    def test_nonzero_exit_missing_banner_and_timeout_cannot_pass(self):
        for code, timeout, success in [("raise SystemExit(2)", 3, None),
                                        ("print('incomplete')", 3, '^DONE$'),
                                        ("import time; time.sleep(10)", .1, None)]:
            with self.subTest(code=code):
                result, _ = self.run_child(code, timeout, success)
                self.assertEqual(result['status'], 'failed')

    def test_manifest_rejects_duplicates_invalid_profiles_and_unsafe_script_paths(self):
        tool = self.tool()
        good = {'version': 1, 'jobs': [{'id': 'rules', 'kind': 'script', 'profile': 'headless',
                'script': 'tests/run_all.gd', 'args': [], 'timeout': 30, 'success': '0 个失败'}]}
        tool.validate_manifest(good, ROOT)
        for field, value in [('profile', 'unknown'), ('script', '../outside.gd'),
                             ('script', '/absolute.gd'), ('timeout', 0), ('args', 'bad')]:
            changed = json.loads(json.dumps(good))
            changed['jobs'][0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                tool.validate_manifest(changed, ROOT)
        duplicate = json.loads(json.dumps(good))
        duplicate['jobs'].append(duplicate['jobs'][0].copy())
        with self.assertRaises(ValueError):
            tool.validate_manifest(duplicate, ROOT)

    def test_output_directory_cannot_overwrite_source_or_unknown_job_succeed(self):
        tool = self.tool()
        with self.assertRaises(ValueError):
            tool.output_path(ROOT, 'tests')
        with self.assertRaises(ValueError):
            tool.select_jobs({'jobs': []}, 'headless', ['missing'])


if __name__ == '__main__':
    unittest.main()
