extends SceneTree
## Authored actions must be usable in the shop, not just present on disk.
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var library: Script = load("res://presentation/characters/character_library.gd")
	for id in ["rabbit", "gray_cat", "bear", "squirrel", "dog", "sheep", "hamster"]:
		var ids: Array = library.actions(id).map(func(a): return a.id)
		_check("walk" in ids and "idle" in ids, id + " exposes walk and idle")
		if id in ["squirrel", "dog", "sheep", "hamster"]:
			_check("sit" in ids, id + " exposes authored sitting")
	_check("work" in library.actions("gray_cat").map(func(a): return a.id), "gray cat exposes authored operation")
	if failures:
		_finish()
		return
	var font := load("res://art/ui/graybox_font.ttf")
	for id in ["rabbit", "gray_cat", "bear", "squirrel", "dog", "sheep", "hamster"]:
		var actor = load("res://presentation/tea_playtest/staff_actor.gd").new()
		actor.setup(id, font)
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
		_check(actor.frame_actor.sprite.flip_h == (id == "dog"), "dog's left-facing source walk is corrected without changing PNGs")
		if id == "gray_cat":
			worker.walking = false
			worker.phase = "work"
			worker.job = {"src": "boil"}
			worker.pos = Vector2(350, 330)
			actor.display(worker, 1.2)
			_check(actor.frame_actor.action == "work" and actor.frame_actor.sprite.animation == "work_back_right" and not actor.frame_actor.sprite.flip_h, "gray cat operates toward the pot")
			var work_phase: float = actor.frame_actor.get_phase()
			actor.display(worker, 1.2)
			_check(is_equal_approx(work_phase, actor.frame_actor.get_phase()), "paused clock freezes operation")
			worker.phase = "pickup"
			worker.job = {"src": "supply", "item": "lemonade"}
			worker.pos = Vector2(190, 650)
			actor.display(worker, 1.4)
			_check(actor.frame_actor.sprite.animation == "work_right" and actor.frame_actor.sprite.flip_h, "gray cat uses mirrored side operation at the left dispenser")
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
	# Exercise a real production job, so the operation is reachable from simulation state.
	var operation_sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	operation_sim.gold = 1000000
	operation_sim.revenue = 1000
	operation_sim.unlock_station("lemonade")
	operation_sim.unlock_station("boil")
	operation_sim.unlock_box("tea_leaf")
	operation_sim.acquire_staff("gray_cat", "test")
	operation_sim.deploy_worker(5)
	var operator = load("res://presentation/tea_playtest/staff_actor.gd").new()
	operator.setup("gray_cat", font)
	root.add_child(operator)
	await process_frame
	var operated := false
	for unused in 1800:
		operation_sim.advance(0.1)
		var worker: Dictionary = operation_sim.worker_by_id(5)
		operator.display(worker, operation_sim.elapsed)
		if worker.phase == "work":
			operated = operator.frame_actor.action == "work"
			break
	_check(operated and operation_sim.audit().valid, "real kitchen production reaches operation without changing inventory accounting")
	operator.free()
	var sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	sim.gold = 10000
	for id in ["raccoon", "fox", "rabbit", "gray_cat", "bear"]:
		_check(sim.next_hire_art() == id and sim.hire(), "recruit existing animals before new bear")
	_check(sim.worker_by_id(6).art == "bear", "bear has its own staff identity")
	var copy = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	_check(copy.load_dict(sim.to_dict()).is_empty() and copy.worker_by_id(6).art == "bear", "bear survives save roundtrip")
	var legacy: Dictionary = sim.to_dict()
	legacy.roster[-1].art = "cat"
	legacy.roster[-1].name = "Cat"
	_check(copy.load_dict(legacy).is_empty(), "old repeated cat at id six remains valid")
	_check(copy.acquire_staff("bear", "test").is_empty(), "new bear can be acquired without replacing old staff")
	_check(copy.worker_by_id(6).art == "cat" and copy.worker_by_id(7).art == "bear", "old identity retained and bear gets a fresh id")
	_finish()

func _finish() -> void:
	print("WORK ACTIONS: %d failures" % failures)
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
