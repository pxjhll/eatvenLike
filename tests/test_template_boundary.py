"""Mutation tests for the formal source/resource boundary gate."""
import importlib.util
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/'tools/check_template_boundary.py'
class BoundaryTests(unittest.TestCase):
    def tool(self):
        self.assertTrue(PATH.is_file(),'formal boundary gate must exist')
        spec=importlib.util.spec_from_file_location('boundary',PATH)
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        return module
    def test_real_formal_project_has_no_execution_bypass(self):
        self.assertEqual(self.tool().inspect_project(ROOT),[])
    def test_private_executor_import_and_legacy_call_are_rejected(self):
        tool=self.tool()
        source=(ROOT/'game/rules/template/runtime.gd').read_text(encoding='utf-8-sig')
        for extra in ['\nfunc bad():\n\tServeFlow.tick(runner.owner,dt)\n', '\nconst Bad = preload("res://game/rules/single_action_context.gd")\n']:
            self.assertTrue(tool.inspect_source('game/rules/template/runtime.gd',source+extra))
    def test_unused_shared_import_cannot_replace_required_actual_calls(self):
        tool=self.tool();path='game/rules/template/runtime.gd'
        source=(ROOT/path).read_text(encoding='utf-8-sig')
        broken=source.replace('runner.step(dt)','""').replace('service.advance(dt)','""')
        self.assertTrue(any(e['rule']=='required_call' for e in tool.inspect_source(path,broken)))
    def test_presentation_cannot_mutate_wallet_inventory_order_or_worker_state(self):
        tool=self.tool()
        for line in ['rules.gold += 10','rules.runtime.runner.inventory.complete_operation(1)',
                     'rules.runtime.service.orders._state.guests.append({})','rules.workers[0].pos = Vector2.ZERO',
                     'rules.runtime.runner.inventory._state.lots.clear()']:
            self.assertTrue(tool.inspect_source('presentation/shop/rogue.gd','func bad():\n\t'+line),line)
        self.assertEqual(tool.inspect_source('presentation/shop/clean.gd','# rules.gold += 1\nfunc draw():\n\tvar state = view.render_snapshot()\n'),[])
    def test_scene_and_resource_cannot_add_private_or_inline_business_scripts(self):
        tool=self.tool()
        for source in ['[ext_resource type="Script" path="res://presentation/shops/private.gd" id="bad"]',
                       '[ext_resource type="Script" path="res://content/rules/spec_private.gd" id="bad"]',
                       '[sub_resource type="GDScript" id="bad"]\nscript/source = "extends Node"',
                       '[ext_resource type="Script" path="res://tests/fixtures/legacy_shops/reference_rules.gd" id="bad"]']:
            self.assertTrue(tool.inspect_resource('content/examples/private.tscn',source))
    def test_static_gate_cli_reports_machine_readable_evidence(self):
        tool=self.tool()
        data=tool.inspect_source('game/rules/template/private.gd','func run():\n\tmatch owner.shop.fulfillment.handoff:\n\t\t"serve": pass\n')
        self.assertTrue(data)
        self.assertTrue(all({'path','line','rule','message'}<=set(row) for row in data))
if __name__=='__main__':unittest.main()
