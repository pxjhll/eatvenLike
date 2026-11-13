extends SceneTree
## 无头回归入口：godot --headless -s tests/run_all.gd
## 失败时退出码为 1。

const SUITES := [
	preload("res://tests/test_template_batch_transport.gd"),
	preload("res://tests/test_template_assistance.gd"),
	preload("res://tests/test_template_limits.gd"),
	preload("res://tests/test_template_transfers.gd"),
	preload("res://tests/test_template_customization.gd"),
	preload("res://tests/test_template_processing_display.gd"),
	preload("res://tests/test_template_available_batch.gd"),
	preload("res://tests/test_template_formal_tea.gd"),
	preload("res://tests/test_template_stage_ports.gd"),
	preload("res://tests/test_template_formal_pancake.gd"),
	preload("res://tests/test_template_menu_selection.gd"),
	preload("res://tests/test_template_menu_ramp.gd"),
	preload("res://tests/test_template_dining.gd"),
	preload("res://tests/test_template_tea_service.gd"),
	preload("res://tests/test_template_deferred_menu.gd"),
	preload("res://tests/test_template_seating.gd"),
	preload("res://tests/test_template_stirfry_service.gd"),
	preload("res://tests/test_template_pickup_queue.gd"),
	preload("res://tests/test_template_station_posts.gd"),
	preload("res://tests/test_template_pancake_service.gd"),
	preload("res://tests/test_template_waiting.gd"),
	preload("res://tests/test_template_flyers.gd"),
	preload("res://tests/test_template_pancake_flyers.gd"),
	preload("res://tests/test_template_pancake_waiting.gd"),
	preload("res://tests/test_template_integrated_inputs.gd"),
	preload("res://tests/test_template_batch_binding.gd"),
	preload("res://tests/test_template_stock_policy.gd"),
	preload("res://tests/test_template_source_clocks.gd"),
	preload("res://tests/test_template_content.gd"),
	preload("res://tests/test_template_normalizer.gd"),
	preload("res://tests/test_template_scheduler.gd"),
	preload("res://tests/test_template_dispatch_leases.gd"),
	preload("res://tests/test_template_arrivals.gd"),
	preload("res://tests/test_template_dispatch.gd"),
	preload("res://tests/test_template_inventory.gd"),
	preload("res://tests/test_template_machines.gd"),
	preload("res://tests/test_template_view.gd"),
	preload("res://tests/test_template_actions.gd"),
	preload("res://tests/test_template_compiler.gd"),
	preload("res://tests/test_template_runtime.gd"),
	preload("res://tests/test_template_restock.gd"),
	preload("res://tests/test_template_orders.gd"),
	preload("res://tests/test_template_customers.gd"),
	preload("res://tests/test_template_carriers.gd"),
	preload("res://tests/test_template_bundles.gd"),
	preload("res://tests/test_template_bundle_actions.gd"),
	preload("res://tests/test_template_interactions.gd"),
	preload("res://tests/test_template_meals.gd"),
	preload("res://tests/test_template_service.gd"),
	preload("res://tests/test_template_service_save.gd"),
	preload("res://tests/test_template_service_edges.gd"),
	preload("res://tests/test_transport_helpers.gd"),
	preload("res://tests/test_serve_front_production.gd"),
	preload("res://tests/test_stirfry_item_presentation.gd"),
	preload("res://tests/test_shop_onboarding.gd"),
	preload("res://tests/test_shop_rhythm.gd"),
	preload("res://tests/test_first_shops_migration.gd"),
	preload("res://tests/test_stirfry_migration.gd"),
	preload("res://tests/test_scene_modules.gd"),
	preload("res://tests/test_flow_composition.gd"),
	preload("res://tests/test_actor_actions.gd"),
	preload("res://tests/test_shared_movement.gd"),
	preload("res://tests/test_actor_presentation.gd"),
	preload("res://tests/test_tea_modularity_baseline.gd"),
	preload("res://tests/test_shared_staff.gd"),
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
	preload("res://tests/test_shop_progression.gd"),
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
