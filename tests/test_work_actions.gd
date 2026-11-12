extends SceneTree
## Authored actions must be usable in the shop, not just present on disk.
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var library: Script = load("res://presentation/characters/character_library.gd")
	for id in ["rabbit", "gray_cat", "bear", "fox", "parrot", "squirrel", "dog", "sheep", "hamster"]:
		var ids: Array = library.actions(id).map(func(a): return a.id)
		_check("walk" in ids and "idle" in ids, id + " exposes walk and idle")
		if id in ["squirrel", "dog", "sheep", "hamster"]:
			_check("sit" in ids, id + " exposes authored sitting")
	_check("work" in library.actions("gray_cat").map(func(a): return a.id), "gray cat exposes authored operation")
	_check("work" in library.actions("rabbit").map(func(a): return a.id), "rabbit exposes authored assembly")
	if failures:
		_finish()
		return
	var font := load("res://art/ui/graybox_font.ttf")
	var tea: SpecShop = load("res://content/shops/tea/shop.tres")
	var view := ShopView.new(ShopRules.new(tea))
	for id in ["rabbit", "gray_cat", "bear", "fox", "parrot", "squirrel", "dog", "sheep", "hamster"]:
		var actor = load("res://presentation/shop/shop_actor.gd").new()
		actor.setup(id, font)
		actor.work_direction = view.work_direction
		actor.pouring_station = view.pouring_station
		root.add_child(actor)
		await process_frame
		var worker := {"pos": Vector2.ZERO, "walking": false, "phase": "idle", "task_label": ""}
		actor.display(worker, 0.0)
		actor.display(worker, 0.7)
		_check(actor.frame_actor.action == "idle" and actor.frame_actor.get_phase() > 0.0, id + " animates while waiting")
		var phase: float = actor.frame_actor.get_phase()
		actor.display(worker, 0.7)
		_check(is_equal_approx(phase, actor.frame_actor.get_phase()), "paused clock freezes idle")
		worker.walking = true
		worker.pos = Vector2(10, 0)
		actor.display(worker, 0.9)
		_check(actor.frame_actor.action == "walk" and actor.frame_actor.direction == 2, "movement resumes walk facing right")
		_check(actor.frame_actor.sprite.flip_h == (id in ["dog", "fox"]), "left-facing source walks are corrected without changing PNGs")
		if id in library.STAFF_IDS:
			worker.walking = false
			worker.phase = "work"
			worker.job = {"src": "boil"}
			actor.display(worker, 1.2)
			_check(actor.frame_actor.action == "work" and actor.frame_actor.sprite.animation == "work_back_right" and actor.frame_actor.sprite.flip_h == (id in ["fox", "parrot"]), id + " operates toward the pot")
			var work_phase: float = actor.frame_actor.get_phase()
			actor.display(worker, 1.2)
			_check(is_equal_approx(work_phase, actor.frame_actor.get_phase()), "paused clock freezes operation")
			worker.phase = "pickup"
			worker.job = {"src": "lemonade", "item": "lemonade"}
			actor.display(worker, 1.4)
			_check(actor.frame_actor.sprite.animation == "work_right" and actor.frame_actor.sprite.flip_h == (id != "fox"), id + " uses the source-aware side operation at the left dispenser")
			if id == "rabbit":
				var clips := ["work_front", "work_front", "work_right", "work_back_right", "work_back_right", "work_back_right", "work_right", "work_front"]
				var counts := [17, 17, 14, 14, 14, 14, 14, 17]
				for direction in 8:
					actor.frame_actor.set_direction(direction)
					_check(actor.frame_actor.sprite.animation == clips[direction], "rabbit assembly selects the nearest supplied view")
					_check(actor.frame_actor.sprite.flip_h == (direction > 4), "rabbit assembly mirrors only left views")
					_check(actor.frame_actor.sprite.sprite_frames.get_frame_count(clips[direction]) == counts[direction], "rabbit assembly keeps all 17 front and 14 side poses")
					_check(is_equal_approx(actor.frame_actor.get_cycle_seconds(), 4.0), "rabbit assembly retains the four-second source loop")
			worker.job = {"src": "boil", "item": "tea"}
			for phase_name in ["idle", "pickup", "dropoff"]:
				worker.phase = phase_name
				actor.display(worker, 1.6)
				_check(actor.frame_actor.action == "idle", "waiting and transport holds do not play machine operation")
			worker.phase = "work"
			worker.walking = true
			actor.display(worker, 1.8)
			_check(actor.frame_actor.action == "walk", "walking takes priority over operation")
		if id in ["squirrel", "dog", "sheep", "hamster"]:
			worker.walking = false
			worker.seated = true
			for direction in [2, 6]:
				worker.facing = direction
				actor.display(worker, 1.2 + direction)
				_check(actor.frame_actor.action == "sit" and actor.frame_actor.sprite.flip_h == ((direction == 6) != (id == "dog")), "sitting faces the table on either side")
		actor.free()
	# Exercise a real production job, so the operation is reachable from rules state.
	var rules := ShopRules.new(tea)
	rules.gold = 1000000
	for station in ["lemonade", "boil"]: rules.unlock(station)
	rules.unlock_box("tea_leaf")
	for unused in 5: rules.hire()
	var cat: Dictionary = rules.roster.filter(func(w: Dictionary) -> bool: return w.kind == "gray_cat")[-1]
	_check(rules.deploy_worker(cat.id) == "", "gray cat deploys into the kitchen")
	var operator = load("res://presentation/shop/shop_actor.gd").new()
	operator.setup("gray_cat", font)
	operator.work_direction = view.work_direction
	operator.pouring_station = view.pouring_station
	root.add_child(operator)
	await process_frame
	var operated := false
	for unused in 1800:
		rules.step(0.1)
		operator.display(cat, rules.clock)
		if cat.phase == "work":
			operated = operator.frame_actor.action == "work"
			break
	_check(operated, "real kitchen production reaches operation")
	operator.free()
	var hiring := ShopRules.new(tea)
	hiring.gold = 10000
	for id in ["bear", "rabbit", "fox", "parrot", "gray_cat"]:
		_check(hiring.next_hire_kind() == id and hiring.hire() == "", "recruit only active staff species")
	_check(hiring.worker_by_id(2).kind == "bear", "bear has its own staff identity")
	var copy := ShopRules.new(tea)
	_check(copy.load_dict(hiring.to_dict()) == "" and copy.worker_by_id(2).kind == "bear", "bear survives save roundtrip")
	_finish()

func _finish() -> void:
	print("WORK ACTIONS: %d failures" % failures)
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
