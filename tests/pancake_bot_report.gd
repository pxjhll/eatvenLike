extends SceneTree
## 煎饼摊节奏报告：godot --headless -s tests/pancake_bot_report.gd [-- seeds]

func _initialize() -> void:
	var seeds := 12
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: seeds = int(args[0])
	var overrides := {}
	if args.size() > 1: overrides = JSON.parse_string(args[1])
	var bot = preload("res://game/pancake/pancake_bot.gd").new()
	var keys := ["soy_milk", "rear_equipment", "hire2", "fryer", "hire3", "topping", "hire4"]
	var all := {}
	var sold := []
	var lost := []
	var done := []
	var gold := []
	for seed in seeds:
		var r: Dictionary = bot.play(seed, 30.0, overrides)
		for k in keys:
			if r.times.has(k):
				if not all.has(k): all[k] = []
				all[k].append(r.times[k] / 60.0)
		sold.append(r.sold); lost.append(r.lost); gold.append(r.gold)
		done.append(r.done_at / 60.0 if r.done_at > 0 else 99.0)
		if seed == 0: print("seed0 levels ", r.levels, " tasks ", r.tasks)
	for k in keys:
		var v: Array = all.get(k, [])
		print("%-15s median %5.1f min (%d/%d)" % [k, _median(v), v.size(), seeds])
	print("sold %d lost %d gold-left %d done(min) %.1f" % [_median(sold), _median(lost), _median(gold), _median(done)])
	quit()

func _median(v: Array) -> float:
	if v.is_empty(): return -1.0
	var s := v.duplicate(); s.sort()
	return float(s[s.size() / 2])
