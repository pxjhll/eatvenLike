extends SceneTree
## 煎饼摊引导真点击回归：用鼠标事件点“开始”、点豆浆机虚线框、点招人按钮，确认每一步都能点过去。
## 只调 _confirm() 测不出“按钮点了没反应”（2026-11-06 手机上卡在欢迎卡）。

var failures := []


func _initialize() -> void:
	call_deferred("_run")


func _click(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		root.push_input(e)
		await process_frame
		await process_frame


func _check(ok: bool, text: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", text])
	if not ok: failures.append(text)


func _run() -> void:
	root.size = Vector2i(720, 1280)
	var play: Node2D = load("res://presentation/pancake/pancake_play.tscn").instantiate()
	play.store = null
	play.profile = preload("res://game/app/profile.gd").new("user://test_profile_guide.json")
	play.profile.reset_all()
	root.add_child(play)
	for i in 3: await process_frame
	var guide: Control = play.guide
	_check(guide.active == "welcome", "开局是欢迎卡")
	await _click(guide._card_button.get_global_rect().get_center())
	_check(guide.active == "open", "点“开始”进入开张这一步")
	await _click(play.frame_screen_rect("soy_milk").get_center())
	_check(play.sim.is_open(), "点豆浆机虚线框能开张")
	await _click(Vector2(360, 300))
	_check(guide.active == "first_sale", "遮罩外随便点不影响")
	play.sim.run(40.0)
	play.sim.gold = 200
	await _click(play.frame_screen_rect("rear_equipment").get_center())
	_check(play.sim.unlocked.get("rear_equipment", false), "点鏊子虚线框能开鏊子")
	for i in 2: await process_frame
	_check(guide.active == "hire", "开鏊子后提示招人")
	await _click(play.hire_screen_rect().get_center())
	_check(play.sim.staff.size() == 2, "点招人按钮能招到人")
	_check(guide.active == "done", "出完成卡")
	await _click(guide._card_button.get_global_rect().get_center())
	_check(guide.active == "", "点“知道了”结束引导")
	play.profile.reset_all()
	print("Pancake guide clicks: %d failures" % failures.size())
	quit(1 if failures.size() > 0 else 0)
