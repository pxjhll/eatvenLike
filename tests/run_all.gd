extends SceneTree
## 无头回归入口：godot --headless -s tests/run_all.gd
## 失败时退出码为 1。

const SUITES := [
	preload("res://tests/test_white_bread.gd"),
	preload("res://tests/test_toast.gd"),
	preload("res://tests/test_font.gd"),
	preload("res://tests/test_invariants.gd"),
	preload("res://tests/test_commands.gd"),
	preload("res://tests/test_save.gd"),
	preload("res://tests/test_workforce.gd"),
	preload("res://tests/test_logistics.gd"),
	preload("res://tests/test_presentation.gd"),
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
