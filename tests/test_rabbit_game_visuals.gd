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
	_check(actions.map(func(a): return a.id) == ["walk", "idle", "work"] and actions[2].label == "操作" and actions[2].view_count == 3, "rabbit assembly is the shared three-view operation action")
	var actor: Node2D = load("res://presentation/shop/shop_actor.gd").new()
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
	worker.phase = "idle"
	worker.carry_item = "black_tea"
	worker.carry_count = 2
	actor.display(worker, clock + 0.2)
	_check(actor.frame_actor.action == "idle" and actor.frame_actor.direction == 7, "stopping keeps facing and plays authored idle")
	_check(actor.carried.visible and actor.amount.visible, "frame rabbit retains cup and quantity overlays")
	_check(absf(actor.carried.texture.get_height() * actor.carried.scale.y - 52.0) < 0.001, "rabbit keeps existing orthographic cup size")
	# Both dishes must follow the actor occlusion together during delivery.
	worker["presentation_version"] = 1
	worker["held_items"] = [{"item":"black_tea", "count":1},{"item":"lemonade", "count":1}]
	for facing in [4, 0, 3, 7, 5, 2, 6, 1]:
		actor.frame_actor.set_direction(facing)
		for i in 4:
			actor.display(worker, clock + 0.2)
			var layer: Node2D = actor.carried.get_parent()
			var second: Sprite2D = actor._held_sprites[0]
			var horizontal_spacing: float = second.position.x - actor.carried.position.x
			_check(is_equal_approx(horizontal_spacing, -18.0 if facing > 4 else 18.0), "second dish stacks outward after turning")
			_check((layer.get_index() < actor.frame_actor.get_index()) == (facing in [3, 4, 5]), "carried food occlusion stays stable across repeated draws")
			_check(second.get_parent() == layer and actor.carried.get_index() < second.get_index(), "both dishes retain their order while turning")
	_check(not actor.amount.visible and not actor._held_amounts[0].visible, "two different singles have no quantity badges")
	worker.carry_count = 5
	worker.held_items[0].count = 2
	worker.held_items[1].count = 3
	actor.display(worker, clock + 0.2)
	_check(actor.amount.visible and actor.amount.text == "×2", "primary quantity is specific to its item")
	_check(actor._held_amounts[0].visible and actor._held_amounts[0].text == "×3", "secondary quantity is specific to its item")
	worker.held_items.pop_back()
	worker.carry_count = 2
	actor.display(worker, clock + 0.2)
	_check(not actor._held_amounts[0].visible, "dropping the secondary item clears its badge")
	actor.free()
	print("RABBIT GAME VISUALS: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
