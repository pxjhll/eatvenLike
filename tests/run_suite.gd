extends SceneTree
## Focused suites use the same assertions and runtime-error accounting as run_all.

func _initialize() -> void:
	var errors := preload("res://tests/error_counter.gd").new()
	OS.add_logger(errors)
	var total := 0
	var failed := 0
	for path in OS.get_cmdline_user_args():
		var script: Script = load("res://" + path.trim_prefix("res://"))
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL cannot load test suite: ", path)
			continue
		for method in script.new().get_method_list():
			if not String(method.name).begins_with("test_"): continue
			var suite: RefCounted = script.new()
			total += 1
			errors.take()
			suite.call(method.name)
			suite.cleanup()
			for error in errors.take(): suite.failures.append("runtime: " + error)
			if suite.failures.is_empty(): print("ok ", method.name)
			else:
				failed += 1
				print("FAIL ", method.name)
				for error in suite.failures: print("  ", error)
	if total == 0: failed += 1
	OS.remove_logger(errors)
	print("%d tests, %d failures" % [total, failed])
	quit(1 if failed > 0 else 0)
