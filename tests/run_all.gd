extends SceneTree
## 无头回归入口：godot --headless -s tests/run_all.gd
## 失败时退出码为 1。

const SUITES := [
	preload("res://tests/test_order_lifecycle.gd"),
	preload("res://tests/test_dispatch_policy.gd"),
	preload("res://tests/test_machine_progress.gd"),
	preload("res://tests/test_fulfillment_completion.gd"),
	preload("res://tests/test_sales.gd"),
	preload("res://tests/test_worker_state.gd"),
	preload("res://tests/test_inventory_audit.gd"),
	preload("res://tests/test_inventory.gd"),
	preload("res://tests/test_fulfillment_plan.gd"),
	preload("res://tests/test_presentation_boundary.gd"),
	preload("res://tests/test_presentation_reads.gd"),
	preload("res://tests/test_command_ui.gd"),
	preload("res://tests/test_command_results.gd"),
	preload("res://tests/test_readonly_queries.gd"),
	preload("res://tests/test_content_save.gd"),
	preload("res://tests/test_content_rules.gd"),
	preload("res://tests/test_reference_art.gd"),
	preload("res://tests/test_font.gd"),
	preload("res://tests/test_ui_skin.gd"),
	preload("res://tests/test_tea_rules.gd"),
	preload("res://tests/test_pancake_rules.gd"),
	preload("res://tests/test_noodle_shop.gd"),
	preload("res://tests/test_stirfry_serve.gd"),
	preload("res://tests/test_shop_specs.gd"),
	preload("res://tests/test_config_contracts.gd"),
	preload("res://tests/test_profile_campaign.gd"),
	preload("res://tests/test_scene_contracts.gd"),
	preload("res://tests/test_shop_rules.gd"),
	preload("res://tests/test_shop_view.gd"),
	preload("res://tests/test_numeric_consistency.gd"),
	preload("res://tests/test_shop_save.gd"),
	preload("res://tests/test_state_validation.gd"),
	preload("res://tests/test_profile_safety.gd"),
	preload("res://tests/test_session.gd"),
	preload("res://tests/test_scene_session.gd"),
]


func _initialize() -> void:
	# 测试方法里发生运行时错误时 Godot 只会中止那个方法，断言不会记失败，所以另外收集错误
	var errors := preload("res://tests/error_counter.gd").new()
	OS.add_logger(errors)
	var total := 0
	var failed := 0
	for suite_script in SUITES:
		var suite_name: String = suite_script.resource_path.get_file().get_basename()
		for method in suite_script.new().get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			var suite: RefCounted = suite_script.new()
			total += 1
			errors.take()
			suite.call(name)
			suite.cleanup()
			for e in errors.take():
				suite.failures.append("运行时错误：" + e)
			if suite.failures.is_empty():
				print("  ok    %s.%s" % [suite_name, name])
			else:
				failed += 1
				print("  FAIL  %s.%s" % [suite_name, name])
				for f in suite.failures:
					print("        - " + f)
	OS.remove_logger(errors)
	print("\n%d 个用例，%d 个失败" % [total, failed])
	quit(1 if failed > 0 else 0)
