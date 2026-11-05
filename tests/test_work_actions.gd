extends SceneTree
## Authored actions must be usable in the shop, not just present on disk.
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var library: Script = load("res://presentation/characters/character_library.gd")
	for id in ["rabbit", "gray_cat", "bear", "squirrel", "dog", "sheep"]:
		var ids: Array = library.actions(id).map(func(a): return a.id)
		_check("walk" in ids and "idle" in ids, id + " exposes walk and idle")
		if id in ["squirrel", "dog", "sheep"]:
			_check("sit" in ids, id + " exposes authored sitting")
	if failures:
		_finish()
		return
	var font := load("res://art/ui/graybox_font.ttf")
	for id in ["rabbit", "gray_cat", "bear", "squirrel", "dog", "sheep"]:
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
		if id in ["squirrel", "dog", "sheep"]:
			worker.walking = false
			worker.seated = true
			for direction in [2, 6]:
				worker.facing = direction
				actor.display(worker, 1.2 + direction)
				_check(actor.frame_actor.action == "sit" and actor.frame_actor.sprite.flip_h == ((direction == 6) != (id == "dog")), "sitting faces the table on either side")
		actor.free()
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
