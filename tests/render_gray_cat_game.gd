extends SceneTree
## Native input/render validation. All business state stays in memory.

var failures := 0
var view: Node2D
var errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(errors)
	Input.use_accumulated_input = false
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(720, 1280)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	var sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	sim.gold = 10000
	sim.revenue = 1000
	sim.unlock_station("lemonade")
	sim.unlock_station("boil")
	sim.unlock_box("tea_leaf")
	sim.paused = true
	view.sim = sim
	root.add_child(view)
	current_scene = view
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	await _click(view.ui.menu_button)
	await _click(view.ui.character_preview_button)
	_check(view.ui.page == "characters", "game menu opens preview")
	if view.ui.page != "characters":
		print("MENU DIAGNOSTIC: ", view.ui.page, " root=", root.size, " button=", view.ui.character_preview_button.get_global_rect())
		quit(1)
		return
	var preview = view.ui.character_preview
	var library: Script = load("res://presentation/characters/character_library.gd")
	for id in ["gray_cat", "rabbit", "cat", "gray_cat"]:
		var index: int = library.IDS.find(id)
		preview.character_select.select(index)
		preview.character_select.item_selected.emit(index)
		_check(preview.art_id == id, "selector changes character")
		if id in library.FRAME_ASSETS:
			_check(preview.frame_actor.sprite.sprite_frames == library.FRAME_ASSETS[id], "preview uses that character's atlas, not the previous character")
		else:
			_check(not preview.frame_actor.visible, "static portrait still works")
	_check(preview.available_actions.map(func(a): return a.id) == ["walk", "idle", "work"], "gray cat lists authored walk, idle and operation")
	await _click(preview.play_button)
	preview.frame_actor.seek_phase(0.37)
	for direction in 8:
		await _click(preview.directions[direction])
		_check(preview.frame_actor.direction == direction and absf(preview.frame_actor.get_phase() - 0.37) < 0.001, "eight direction buttons retain paused phase")
		var cycle := 0.65 / 1.15 if direction in [0, 1, 7] else 0.80
		_check(absf(preview.frame_actor.get_cycle_seconds() - cycle) < 0.0001, "game preview uses the balanced front/side/back cadence")
	var frame: int = preview.frame_actor.sprite.frame
	await _click(preview.next_button)
	_check(preview.frame_actor.sprite.frame == posmod(frame + 1, 7), "next keyframe")
	await _click(preview.previous_button)
	_check(preview.frame_actor.sprite.frame == frame, "previous keyframe")
	await _click(preview.timeline, 0.8)
	_check(absf(preview.frame_actor.get_phase() - preview.timeline.value) < 0.001 and preview.frame_actor.get_phase() > 0.6, "seek actual gray-cat frames to the slider's value")
	await _click(preview.speed_slider, 0.8)
	_check(preview.frame_actor.sprite.speed_scale > 1.0, "native speed control")
	var clock: float = sim.elapsed
	await create_timer(0.2).timeout
	_check(sim.elapsed == clock, "preview freezes business")
	await _capture("gray-cat-game-preview.png")
	await _click(view.ui.close_button)
	# Hiring now deploys immediately: five staff need the final stage's slots.
	for station in ["seal", "mix", "press", "topping"]: sim.unlock_station(station)
	sim.unlock_box("milk")
	view.ui.open_page("staff")
	for cost in [35, 60, 85, 110]:
		var gold: int = sim.gold
		await _click(view.ui.hire_button)
		_check(sim.gold == gold - cost, "real recruitment button charges %d" % cost)
	_check(sim.all_workers().size() == 5 and sim.worker_by_id(5).art == "gray_cat", "gray cat recruited after rabbit")
	view.selected_worker = 5
	view.ui.open_page("staff")
	await _capture("gray-cat-roster.png")
	await _click(view.ui.staff_preview_button)
	_check(view.ui.page == "characters" and preview.art_id == "gray_cat", "staff entry previews the selected gray cat")
	view.ui.open_page("staff")
	if not view.staff_is_deployed(5): await _click(view.ui.deploy_button)
	_check(view.staff_is_deployed(5), "HUD deploys gray cat into the kitchen")
	view.ui.open_page("shop")
	view.set_process(false)
	sim.paused = false
	var carried := false
	var poses := {}
	var facings := {}
	for i in 1800:
		sim.advance(0.1)
		view._refresh(0.0)
		var actor = view._actors[5]
		if sim.worker_by_id(5).walking:
			poses[actor.frame_actor.sprite.frame] = true
			facings[actor.frame_actor.direction] = true
		if actor.carried.visible and not carried:
			carried = true
			await _capture("gray-cat-carry.png")
		if carried and poses.size() > 2 and facings.size() > 1: break
	_check(carried and poses.size() > 2 and facings.size() > 1 and sim.audit().valid, "real kitchen work carries goods with animated direction changes")
	view.ui.open_character_preview("gray_cat")
	view._fit()
	DisplayServer.window_set_size(Vector2i(360, 640))
	for i in 4:
		view._fit()
		await process_frame
	await _capture("gray-cat-preview-small.png")
	_check(preview.directions[7].get_global_rect().end.x <= root.get_visible_rect().size.x + 1, "small screen fits horizontally")
	view.free()
	var viewer = load("res://presentation/gray_cat_walk_frames/preview.tscn").instantiate()
	root.add_child(viewer)
	await create_timer(0.15).timeout
	await _click(viewer._play)
	await _click(viewer._directions[6])
	_check(viewer.actor.sprite.sprite_frames == library.GRAY_CAT_FRAMES and viewer.actor.sprite.flip_h, "independent viewer uses gray-cat frames and mirrored facing")
	_check(viewer.paused and viewer.small.sprite.flip_h, "source-size and small previews stay synchronized")
	var previous: int = viewer.actor.sprite.frame
	await _click(viewer._next)
	_check(viewer.actor.sprite.frame == posmod(previous + 1, 7), "independent viewer steps original keyframes")
	await _capture("gray-cat-frames-preview.png")
	viewer.free()
	var comparison: Node2D = load("res://presentation/gray_cat_walk_frames/direction_compare.tscn").instantiate()
	root.add_child(comparison)
	await create_timer(0.15).timeout
	_check(comparison.actors.size() == 8, "comparison shows all eight native directions at once")
	await _click(comparison.play_button)
	_check(comparison.paused, "comparison pauses all directions")
	comparison.sliders[0].value = 1.5
	for actor in comparison.actors:
		_check(not actor.sprite.is_playing(), "all comparison actors are paused")
		_check(is_equal_approx(actor.sprite.speed_scale, 1.5 if actor.direction in [0, 1, 7] else 1.0), "group slider only affects that group's preview instances")
	await _click(comparison.reset_button)
	_check("0.57" in comparison.captions[0].text and "0.80" in comparison.captions[1].text, "comparison labels read actual resource cadence after reset")
	for actor in comparison.actors:
		_check(actor.sprite.speed_scale == 1.0 and actor.get_phase() == 0.0, "comparison reset restores original speed and phase")
	await _capture("gray-cat-direction-compare.png")
	comparison.free()
	var runtime_errors: Array = Array(errors.take())
	OS.remove_logger(errors)
	if not runtime_errors.is_empty():
		failures += runtime_errors.size()
		print(runtime_errors)
	print("GRAY CAT GUI: %d failures" % failures)
	quit(1 if failures else 0)

func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/gray_cat_capture")
	_check(root.get_texture().get_image().save_png("res://.godot/gray_cat_capture/" + name) == OK, "native screenshot")

func _click(control: Control, fraction := 0.5) -> void:
	await process_frame
	var hud := control.find_parent("HUD")
	var scroll: ScrollContainer = hud.get_node("%Scroll") if hud != null else null
	if scroll != null and scroll.is_ancestor_of(control):
		scroll.ensure_control_visible(control)
		await create_timer(0.03).timeout
	var rect := control.get_global_rect()
	var at := (rect.position + rect.size * Vector2(fraction, 0.5)) * Vector2(root.size) / root.get_visible_rect().size
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await create_timer(0.03).timeout

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
