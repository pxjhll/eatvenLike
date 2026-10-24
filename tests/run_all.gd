extends SceneTree
## 无头回归入口：godot --headless -s tests/run_all.gd
## 失败时退出码为 1。

const SUITES := [
	preload("res://tests/test_white_bread.gd"),
	preload("res://tests/test_invariants.gd"),
	preload("res://tests/test_commands.gd"),
	preload("res://tests/test_save.gd"),
]


func _initialize() -> void:
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
			suite.call(name)
			suite.cleanup()
			if suite.failures.is_empty():
				print("  ok    %s.%s" % [suite_name, name])
			else:
				failed += 1
				print("  FAIL  %s.%s" % [suite_name, name])
				for f in suite.failures:
					print("        - " + f)
	print("\n%d 个用例，%d 个失败" % [total, failed])
	quit(1 if failed > 0 else 0)
