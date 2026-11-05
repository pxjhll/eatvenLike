extends SceneTree
## Import and gameplay contract for the new gray-cat employee.

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var library: Script = load("res://presentation/characters/character_library.gd")
	_check("gray_cat" in library.IDS, "gray cat is available in the shared character catalog")
	var sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	_check("gray_cat" in sim.ARTS, "gray cat is a recruitable employee")
	if failures:
		_finish()
		return
	_check(library.portrait("gray_cat") is AtlasTexture, "portrait uses the real gray-cat atlas")
	_check(library.actions("gray_cat").map(func(a): return a.id) == ["walk", "idle", "work"], "authored gray-cat walk, idle and operation are advertised")
	sim.gold = 1000
	for art in ["raccoon", "fox", "rabbit", "gray_cat"]:
		_check(sim.next_hire_art() == art, "existing recruitment order followed by gray cat")
		var cost: int = sim.hire_cost()
		var gold: int = sim.gold
		_check(sim.hire() and sim.gold == gold - cost, "each recruit is paid")
	var worker: Dictionary = sim.worker_by_id(5)
	_check(worker.art == "gray_cat" and worker.name == "小灰猫", "new gray cat has its own roster identity")
	_check(sim.next_hire_art() == "bear", "bear follows the original five animals")
	var legacy: Dictionary = sim.to_dict()
	legacy.roster[4].art = "cat"
	legacy.roster[4].name = "Cat"
	var old = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	_check(old.load_dict(legacy).is_empty(), "older repeated cat with id five remains valid")
	_check(old.acquire_staff("gray_cat", "test").is_empty(), "gray cat can be acquired when legacy id five is occupied")
	_check(old.all_workers()[-1].id == 6 and old.all_workers()[-1].art == "gray_cat", "new gray cat does not reuse an occupied staff id")
	sim.unlock_station("lemonade")
	sim.revenue = 1000
	sim.unlock_station("boil")
	sim.unlock_box("tea_leaf")
	_check(sim.deploy_worker(5).is_empty(), "gray cat deploys into a real kitchen slot")
	var carried := false
	for i in 1200:
		sim.advance(0.1)
		if worker.carry_count > 0:
			carried = true
			break
	_check(carried and sim.audit().valid, "gray cat physically carries real stock without losing inventory")
	var copy = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	_check(copy.load_dict(sim.to_dict()).is_empty(), "active gray cat saves and reloads")
	sim.advance(2.0)
	copy.advance(2.0)
	_check(var_to_bytes(sim.to_dict()) == var_to_bytes(copy.to_dict()), "gray-cat work resumes identically")
	var actor = load("res://presentation/tea_playtest/staff_actor.gd").new()
	actor.setup("gray_cat", load("res://art/ui/graybox_font.ttf"))
	root.add_child(actor)
	await process_frame
	_check(actor.frame_actor != null and not actor.body.visible, "world actor plays gray-cat frames")
	if actor.frame_actor != null:
		actor.display(worker, sim.elapsed)
		var moving := worker.duplicate(true)
		moving.walking = true
		moving.path = PackedVector2Array()
		moving.pos += Vector2(10, -10)
		actor.display(moving, sim.elapsed + 0.2)
		_check(actor.frame_actor.direction == 3, "movement selects gray-cat back diagonal")
		var phase: float = actor.frame_actor.get_phase()
		actor.display(moving, sim.elapsed + 0.2)
		_check(is_equal_approx(phase, actor.frame_actor.get_phase()), "paused simulation freezes gray-cat frames")
		moving.walking = false
		actor.display(moving, sim.elapsed + 0.3)
		_check(actor.frame_actor.action == "idle", "stopping plays the facing's idle action")
	actor.free()
	sim.reset_shop()
	_check(sim.worker_by_id(5).is_empty() and sim.all_workers().size() == 1, "reset keeps only the starter (staff do not carry over)")
	_finish()

func _finish() -> void:
	print("GRAY CAT GAME: %d failures" % failures)
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
