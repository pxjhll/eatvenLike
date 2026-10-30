extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "res://presentation/characters/character_library.gd"
	_check(ResourceLoader.exists(path), "shared character library exists")
	if failures:
		quit(1)
		return
	var library: Script = load(path)
	for art: String in ["cat", "raccoon", "fox", "rabbit"]:
		_check(library.portrait(art) != null, "all employees have a usable portrait")
		_check(not library.actions(art).is_empty(), "each character exposes its actual available actions")
	_check(library.portrait("rabbit") is AtlasTexture, "rabbit portrait comes from its actual frame atlas")
	var actions: Array = library.actions("rabbit")
	_check(actions.size() == 1 and actions[0].id == "walk", "rabbit exposes the authored walk action")
	var actor: Node2D = load("res://presentation/tea_playtest/staff_actor.gd").new()
	actor.setup("rabbit", load("res://art/ui/graybox_font.ttf"))
	root.add_child(actor)
	await process_frame
	_check(actor.frame_actor != null and not actor.body.visible, "shop rabbit uses the frame actor")
	if actor.frame_actor == null:
		actor.free()
		quit(1)
		return
	var worker := {"pos": Vector2.ZERO, "walking": true, "phase": "walk", "task_label": "serve", "speed": 104.0, "carry_item": "", "carry_count": 0}
	actor.display(worker, 0.0)
	var point := Vector2.ZERO
	var clock := 0.0
	var vectors := [Vector2.DOWN, Vector2(1, 1), Vector2.RIGHT, Vector2(1, -1), Vector2.UP, Vector2(-1, -1), Vector2.LEFT, Vector2(-1, 1)]
	for direction in 8:
		point += vectors[direction] * 10
		clock += 0.1
		worker.pos = point
		var before := var_to_str(worker)
		actor.display(worker, clock)
		_check(actor.frame_actor.direction == direction, "real movement selects direction %d" % direction)
		_check(var_to_str(worker) == before, "drawing does not mutate worker data")
	var phase: float = actor.frame_actor.get_phase()
	actor.display(worker, clock)
	_check(absf(actor.frame_actor.get_phase() - phase) < 0.00001, "paused simulation clock freezes walking frames")
	actor.display(worker, clock + 0.1)
	_check(absf(actor.frame_actor.get_phase() - phase) > 0.01, "advancing simulation time advances walking frames")
	worker.walking = false
	worker.phase = "work"
	worker.carry_item = "black_tea"
	worker.carry_count = 2
	actor.display(worker, clock + 0.2)
	_check(actor.frame_actor.sprite.frame == 0 and actor.frame_actor.direction == 7, "stopping keeps facing and uses a still pose")
	_check(actor.carried.visible and actor.amount.visible, "frame rabbit retains cup and quantity overlays")
	_check(absf(actor.carried.texture.get_height() * actor.carried.scale.y - 52.0) < 0.001, "rabbit keeps existing orthographic cup size")
	for facing in [4, 0, 3, 7, 5, 2]:
		actor.frame_actor.set_direction(facing)
		for i in 4:
			actor.display(worker, clock + 0.2)
			_check((actor.carried.get_index() < actor.frame_actor.get_index()) == (facing in [3, 4, 5]), "carried cup occlusion stays stable across repeated draws")
	actor.free()
	print("RABBIT GAME VISUALS: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
