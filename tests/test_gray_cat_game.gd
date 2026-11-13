extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
## Import and gameplay contract for the gray-cat employee, on the shared shop rules.

const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/tea.tres")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var library: Script = load("res://presentation/characters/character_library.gd")
	_check("gray_cat" in library.IDS, "gray cat is available in the shared character catalog")
	var rules := LegacyRules.new(TEA)
	_check("gray_cat" in rules.hire_pool, "gray cat is a recruitable employee")
	if failures:
		_finish()
		return
	_check(library.portrait("gray_cat") is AtlasTexture, "portrait uses the real gray-cat atlas")
	_check(library.actions("gray_cat").map(func(a): return a.id) == ["walk", "idle", "work"], "authored gray-cat walk, idle and operation are advertised")
	rules.gold = 1000
	for kind in ["raccoon", "fox", "rabbit", "gray_cat"]:
		_check(rules.next_hire_kind() == kind, "existing recruitment order followed by gray cat")
		var cost: int = rules.hire_cost()
		var gold: float = rules.gold
		_check(rules.hire() == "" and is_equal_approx(rules.gold, gold - cost), "each recruit is paid")
	var worker: Dictionary = rules.worker_by_id(5)
	_check(worker.kind == "gray_cat" and worker.name == "小灰猫", "new gray cat has its own roster identity")
	_check(rules.next_hire_kind() == "bear", "bear follows the original five animals")
	rules.gold = 1000
	rules.unlock("lemonade")
	rules.unlock("boil")
	rules.unlock_box("tea_leaf")
	_check(rules.deploy_worker(5) == "", "gray cat deploys into a real kitchen slot")
	var carried := false
	for i in 1200:
		rules.step(0.1)
		if worker.carry_count > 0:
			carried = true
			break
	_check(carried, "gray cat physically carries real stock")
	var copy := LegacyRules.new(TEA)
	_check(copy.load_dict(rules.to_dict()) == "", "active gray cat saves and reloads")
	rules.run(2.0)
	copy.run(2.0)
	_check(var_to_bytes(rules.to_dict()) == var_to_bytes(copy.to_dict()), "gray-cat work resumes identically")
	var actor = load("res://presentation/shop/shop_actor.gd").new()
	actor.setup("gray_cat", load("res://art/ui/graybox_font.ttf"))
	root.add_child(actor)
	await process_frame
	_check(actor.frame_actor != null and not actor.body.visible, "world actor plays gray-cat frames")
	if actor.frame_actor != null:
		actor.display(worker, rules.clock)
		var moving := worker.duplicate(true)
		moving.walking = true
		moving.path = PackedVector2Array()
		moving.pos += Vector2(10, -10)
		actor.display(moving, rules.clock + 0.2)
		_check(actor.frame_actor.direction == 3, "movement selects gray-cat back diagonal")
		var phase: float = actor.frame_actor.get_phase()
		actor.display(moving, rules.clock + 0.2)
		_check(is_equal_approx(phase, actor.frame_actor.get_phase()), "paused simulation freezes gray-cat frames")
		moving.walking = false
		actor.display(moving, rules.clock + 0.3)
		_check(actor.frame_actor.action == "idle", "stopping plays the facing's idle action")
	actor.free()
	rules.reset()
	_check(rules.worker_by_id(5).is_empty() and rules.roster.size() == 1, "reset keeps only the starter (staff do not carry over)")
	_finish()

func _finish() -> void:
	print("GRAY CAT GAME: %d failures" % failures)
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
