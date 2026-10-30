extends SceneTree
## Exercises the real HUD and game scene using an isolated in-memory business.

var failures := 0
var view: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	var sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	view.sim = sim
	root.add_child(view)
	current_scene = view
	await process_frame
	await process_frame
	var size_before := DisplayServer.window_get_size()
	await _click(view.ui.menu_button)
	await _click(view.ui.character_preview_button)
	_check(view.ui.page == "characters", "menu opens embedded character preview")
	var preview = view.ui.character_preview
	_check(preview.art_id == "rabbit" and preview.available_actions.size() == 1, "rabbit lists its actual walk action")
	_check(preview.frame_actor.visible, "native frame actor is displayed")
	var clock: float = sim.elapsed
	await create_timer(0.25).timeout
	_check(sim.elapsed == clock and not sim.paused, "preview freezes business without changing saved pause state")
	_check(view.sim == sim and DisplayServer.window_get_size() == size_before, "preview keeps game and window")
	await _click(preview.play_button)
	_check(not preview.frame_actor.sprite.is_playing(), "pause button pauses real frame playback")
	preview.frame_actor.seek_phase(0.37)
	for direction in 8:
		await _click(preview.directions[direction])
		_check(preview.frame_actor.direction == direction, "direction control %d" % direction)
		_check(absf(preview.frame_actor.get_phase() - 0.37) < 0.001, "switch preserves paused phase")
	await _click(preview.next_button)
	_check(preview.frame_actor.sprite.frame == 3, "next keyframe button")
	await _click(preview.previous_button)
	_check(preview.frame_actor.sprite.frame == 2, "previous keyframe button")
	await _click(preview.timeline, 0.8)
	_check(absf(preview.frame_actor.get_phase() - 0.8) < 0.03, "timeline seeks actual frames")
	await _click(preview.speed_slider, 0.8)
	_check(preview.frame_actor.sprite.speed_scale > 1.0, "preview speed slider")
	await _capture("res://docs/qa/rabbit-game-preview.png")
	for id in ["cat", "raccoon", "fox"]:
		preview.character_select.select(preview.Library.IDS.find(id))
		preview.character_select.item_selected.emit(preview.Library.IDS.find(id))
		_check(preview.art_id == id, "character selector changes the displayed character")
		_check(preview.available_actions.size() == 1 and preview.available_actions[0].id == "pose", "static employees expose only available pose")
		_check(not preview.frame_actor.visible and not preview.play_button.visible, "static pose has no invented playback")
	await _click(view.ui.close_button)
	_check(view.ui.page == "shop", "close button returns to shop")
	# Business advances at 0.1s fixed steps; a frame count varies by renderer/GPU.
	await create_timer(0.25).timeout
	_check(sim.elapsed > clock, "business resumes when preview closes")
	sim.paused = true
	view.ui.open_character_preview()
	await process_frame
	view.ui.open_page("shop")
	_check(sim.paused, "already paused business remains paused")
	sim.gold = 1000
	view.ui.open_page("recruit")
	for cost in [35, 60, 85]:
		var before: int = sim.gold
		await _click(view.ui.hire_button)
		_check(sim.gold == before - cost, "real hire button charges %d" % cost)
	_check(sim.all_workers().size() == 4 and sim.all_workers()[3].art == "rabbit", "rabbit recruited as fourth employee")
	view.selected_worker = 4
	view.ui.open_page("staff")
	await process_frame
	await _click(view.ui.staff_preview_button)
	_check(view.ui.page == "characters" and preview.art_id == "rabbit", "selected employee opens its own preview")
	_check(preview.frame_actor.sprite.is_playing(), "reopening preview resumes playback")
	view.ui.open_page("staff")
	await _capture("res://docs/qa/rabbit-game-roster.png")
	# Newly hired employees start on the roster. Deploy rabbit using the actual HUD.
	if sim.workers.size() >= 3:
		for worker in sim.workers.duplicate():
			if int(worker.id) != 1: sim.recall_worker(worker.id)
	view.ui.refresh()
	await _click(view.ui.deploy_button)
	view._refresh(0.0)
	_check(view.staff_is_deployed(4) and view._actors.has(4), "rabbit deploys into actual shop")
	_check(view._actors[4].frame_actor != null, "deployed rabbit uses atlas actor")
	var copy = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	_check(copy.load_dict(sim.to_dict()).is_empty() and copy.all_workers().size() == 4, "gameplay rabbit roundtrips save data")
	sim.unlock_station("lemonade")
	sim.paused = false
	view.ui.open_page("shop")
	for i in 100: sim.advance(0.1)
	view._refresh(0.0)
	await _capture("res://docs/qa/rabbit-game-shop.png")
	var rabbit = view._actors[4]
	var carried_seen := false
	var phases := {}
	var facings := {}
	for i in 400:
		sim.advance(0.1)
		view._refresh(0.0)
		var worker: Dictionary = sim.all_workers()[3]
		if worker.walking:
			facings[rabbit.frame_actor.direction] = true
			phases[rabbit.frame_actor.sprite.frame] = true
		if not carried_seen and rabbit.carried.visible:
			carried_seen = true
			await _capture("res://docs/qa/rabbit-game-carry.png")
	_check(carried_seen and facings.size() > 1 and phases.size() > 1, "real assigned rabbit carries goods and walks with changing frames and facing")
	view.ui.open_character_preview()
	DisplayServer.window_set_size(Vector2i(360, 640))
	for i in 4: await process_frame
	await _capture("res://docs/qa/rabbit-game-preview-small.png")
	_check(preview.directions[7].get_global_rect().end.x <= root.get_visible_rect().size.x + 1, "small portrait has no horizontal overflow")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	for i in 4: await process_frame
	await _capture("res://docs/qa/rabbit-game-preview-landscape.png")
	view.free()
	print("RABBIT GAME INTEGRATION: %d failures; HUD input, preview, recruitment, deployment and save" % failures)
	quit(1 if failures else 0)

func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(path) == OK, "screenshot saved")

func _click(control: Control, fraction: float = 0.5) -> void:
	await process_frame
	# Bring lower controls into the sheet's scroll viewport, as touch scrolling would.
	var scroll: ScrollContainer = view.ui.get_node("%Scroll")
	if scroll.is_ancestor_of(control):
		scroll.ensure_control_visible(control)
		await create_timer(0.03).timeout
	var at := control.get_global_rect().position + control.size * Vector2(fraction, 0.5)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await create_timer(0.03).timeout

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
