extends SceneTree
## Record the five-species tea baseline without changing the historical six-species files.
## godot --headless --path . -s tests/baselines/record_tea_staff.gd [-- --check]

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const Replay := preload("res://tests/baselines/replay_rules.gd")
const UI := preload("res://tests/test_shop_view.gd")
const GAME_PATH := "res://tests/baselines/tea_active_staff.json"
const UI_PATH := "res://tests/baselines/tea_ui_active_staff.json"


func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/baselines/tea_73b0ae3.json"))
	var rules := ShopRules.new(TEA)
	var view := ShopView.new(rules)
	var actions: Array = []
	var rows: Array = []
	var previous := {}
	var next := 0
	for tick in int(source.minutes * 60.0 / ShopRules.STEP):
		rules.step(ShopRules.STEP)
		while next < source.actions.size() and float(source.actions[next][0]) <= rules.clock + 0.0001:
			var command: String = source.actions[next][1]
			var error := Replay.run_command(rules, command)
			if not error.is_empty():
				if error.begins_with("金币不足"): break
				push_error("Cannot record %s: %s" % [command, error])
				quit(1)
				return
			actions.append([snappedf(rules.clock, ShopRules.STEP), command])
			next += 1
		if tick % 50 == 0:
			var snapshot := UI.signature(view)
			var delta := {}
			for key in snapshot:
				if not previous.has(key) or not UI._same(snapshot[key], previous[key]): delta[key] = snapshot[key]
			rows.append([tick, delta])
			previous = snapshot
	if next != source.actions.size():
		push_error("Not all scheduled actions completed")
		quit(1)
		return
	var result := Replay.replay(TEA, {"minutes": source.minutes, "actions": actions})
	if not result.failed_actions.is_empty() or result.completed_at < 0:
		push_error("Recorded run must complete without failed actions")
		quit(1)
		return
	var levels := {}
	var material_levels := {}
	for station in TEA.stations:
		if not station.tracks.is_empty(): levels[station.id] = rules.level(station.id)
		for material in station.materials:
			if material.track != null: material_levels[material.id] = rules.level(station.id + "/" + material.id)
	var data := {"shop": TEA.id, "seed": TEA.random_seed, "minutes": source.minutes,
		"bot": "Legacy schedule; retry an unaffordable action each tick until it succeeds.",
		"staff": ["gray_cat", "bear", "rabbit", "fox", "parrot"], "checkpoints": result.checkpoints,
		"completed_at": result.completed_at, "segments": result.segments,
		"levels": levels, "material_levels": material_levels, "actions": actions}
	var ui := {"every_ticks": 50, "from": "Five active staff species; same successful actions as tea_active_staff.json.", "rows": rows}
	var same := _write_or_check(GAME_PATH, data) and _write_or_check(UI_PATH, ui)
	print("TEA ACTIVE STAFF: %d actions, %d UI samples, completed at %.1fs" % [actions.size(), rows.size(), result.completed_at])
	quit(0 if same else 1)


func _write_or_check(path: String, data: Dictionary) -> bool:
	var text := JSON.stringify(data, "\t", false) + "\n"
	if "--check" in OS.get_cmdline_user_args():
		var same := FileAccess.get_file_as_string(path) == text
		print(("MATCH " if same else "MISMATCH ") + path)
		return same
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return true
