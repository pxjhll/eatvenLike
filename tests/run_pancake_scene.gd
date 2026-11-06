extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite_script := preload("res://tests/test_pancake_scene.gd")
	var errors := preload("res://tests/error_counter.gd").new()
	OS.add_logger(errors)
	var failed := 0
	var total := 0
	for method in suite_script.new().get_method_list():
		if not String(method.name).begins_with("test_"): continue
		var suite := suite_script.new()
		suite.call(method.name)
		for error in errors.take(): suite.failures.append(error)
		total += 1
		if not suite.failures.is_empty(): failed += 1
		print("%s %s %s" % ["PASS" if suite.failures.is_empty() else "FAIL", method.name, suite.failures])
	OS.remove_logger(errors)
	print("Pancake scene: %d tests, %d failures" % [total, failed])
	quit(1 if failed else 0)
