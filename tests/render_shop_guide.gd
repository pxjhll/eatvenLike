extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const LegacySave := preload("res://tests/fixtures/legacy_shops/reference_save.gd")

const TestSession := preload("res://tests/shop_test_session.gd")
## 通用店铺场景里的奶茶店引导（数据驱动，§6.3），用真实点按走一遍：欢迎卡、柠檬水、第一杯、开店上手卡、
## 后面的开线、原料箱、后厨招人、客人等急、加料线以后的多招人；重开游戏记得看过哪些。
## 和旧场景的 render_guide.gd 一一对应（旧场景删掉时这个留下）。

const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/current/tea/shop.tres")
var view: Node2D
var hud: Control
var guide: Control
var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()
var save_path := "user://shop-guide-gui-%d.json" % OS.get_process_id()


func _initialize() -> void:
	Input.use_accumulated_input = false
	OS.add_logger(errors)
	call_deferred("_run")


func _rules() -> ShopRules:
	return view.rules


func _run() -> void:
	root.size = Vector2i(720, 1280)
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(save_path)
	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	view.session = TestSession.make(TEA, save_path, LegacyRules.new(TEA), LegacySave.new(TEA, save_path))
	root.add_child(view)
	await process_frame
	view.set_process(false)
	hud = view.ui
	guide = view.guide
	_check(not guide.enabled and not guide.visible, "测试注入的店不放引导")
	guide.enabled = true
	guide.refresh(0)
	_check(guide.active == "welcome" and guide.freezes() and hud.popups.has_card("guide:welcome"), "新店先弹欢迎卡，店停着")
	await process_frame
	guide.refresh(0)
	await _capture("welcome")
	await _click(hud.popups.button(hud.popups.primary_index()))
	_check(guide.active == "opening" and guide._hole.intersects(_local(view._station_buttons.lemonade)), "手指指着柠檬水台的虚线框")
	var cat: Dictionary = _rules().workers[0]
	var cat_pos: Vector2 = cat.pos
	await _drag(_screen(cat.pos), _screen(Vector2(250, 600)))
	_check(cat.post == "counter" and cat.pos == cat_pos and view._drag.worker_id == -1, "压暗的时候不能拖人")
	var clock := _rules().clock
	await _press(hud.tab("staff").get_global_rect().get_center())
	_check(hud.page == "shop", "洞外面的点按被吃掉")
	view._process(1.0)
	_check(_rules().clock == clock, "压暗的时候店停着")
	await _click(view._station_buttons.lemonade)
	_check(hud.page == "station" and guide._hole.intersects(_local(hud.page_node("station").unlock_button)), "面板里手指移到解锁键")
	await _click(hud.page_node("station").unlock_button)
	_check(_rules().station_unlocked("lemonade"), "按引导解锁了柠檬水台")
	await _click(hud.tab("shop"))
	_check(not guide.freezes() and guide._bubble.visible, "第一杯边卖边提示，不压暗")
	await _capture("first-sale")
	_run_until(func() -> bool: return _rules().sold > 0, 120.0)
	_check(_rules().workers.size() == 1 and guide.active == "done", "卖出第一杯，开场结束")
	_check(hud.page == "shop" and hud.popups.has_card("guide:done"), "开店上手卡盖在店面上")
	await _capture("done")
	await _touch(hud.popups.get_global_transform_with_canvas() * Vector2(360, 1100))
	_check(guide.active.is_empty() and guide.seen.has("opening") and not guide.freezes(), "点哪里都能关掉上手卡（只有触屏事件也行）")
	var resumed := LegacySave.new(TEA, save_path)
	resumed.load_game()
	_check("opening" in resumed.loaded_guides, "看过的引导和店一起存")
	_rules().gold = maxf(_rules().gold, 200)
	for cause in ["seats", "staff", "machine"]: guide.seen["lost_" + cause] = true
	_run_until(func() -> bool: return guide.active == "line_1", 300.0)
	_check(guide.freezes() and guide._hole.intersects(_local(view._station_buttons.boil)), "攒够钱：红茶线引导一次")
	await _capture("line")
	await _click(view._station_buttons.boil)
	await _click(hud.page_node("station").unlock_button)
	_check(_rules().stage_index == 1 and guide.active.is_empty(), "开了线，提示结束")
	await _click(hud.tab("shop"))
	_rules().gold = maxf(_rules().gold, 20)
	guide.refresh(0)
	_check(guide.active == "box_tea_leaf" and guide._hole.intersects(_local(view._station_buttons.supply)), "煮茶机的茶叶箱指着原料柜")
	await _click(view._station_buttons.supply)
	guide.refresh(0)
	await _click(hud.page_node("station").material_buttons.tea_leaf)
	guide.refresh(0)
	_check(_rules().boxes.tea_leaf and guide.active.is_empty(), "买了箱子，提示结束")
	await _click(hud.tab("shop"))
	_rules().gold = maxf(_rules().gold, _rules().hire_cost())
	guide.refresh(0)
	_check(guide.active == "kitchen" and guide._hole.intersects(_local(hud.tab("staff"))), "后厨没人：指着员工页签")
	await _capture("hire")
	await _click(hud.tab("staff"))
	_check(guide._hole.intersects(_local(hud.page_node("staff").hire_button)), "员工页里指着招人")
	await _click(hud.page_node("staff").hire_button)
	_check(_rules().roster.size() == 2 and _rules().kitchen_staff() == 1 and guide.active.is_empty(), "招来直接进后厨，提示结束")
	await _click(hud.tab("shop"))
	for order in _rules().orders: order.wait = 0.0
	guide._angry_pending = false
	for cause in ["seats", "staff", "machine"]: guide.seen.erase("lost_" + cause)
	await _click(hud.tab("staff"))
	_make_angry(true)
	guide.refresh(0)
	_check(guide.active.is_empty(), "在别的页面看到客人等急，回店面再说")
	await _click(hud.tab("shop"))
	var slow: String = "lemonade" if _rules().orders[-1].dish == "lemonade" else "boil"
	_check(guide.active == "lost_machine" and guide.freezes() and guide._hole.intersects(guide._world_rect(view.anchors.rect("Stations/%s/Tap" % slow))),
		"外带客人等急、岗位都满：指着做这杯的机器")
	await _capture("lost")
	await _click(guide._bubble_skip)
	_make_angry(true)
	guide.refresh(0)
	_check(guide.active.is_empty(), "每种提示只说一次")
	var group := _rules().dine_group()
	_rules().seats[group.id] = group.start
	_rules().diners.clear()
	for seat in group.start: _rules().diners.append({"seat": seat, "dish": "lemonade", "left": 99.0})
	_rules().gold = 0
	_make_angry(false)
	guide.refresh(0)
	_check(guide.active == "lost_seats" and guide._hole.intersects(_local(view._seats)), "座位坐满：指着堂食数字牌")
	await _click(guide._bubble_skip)
	_rules().diners.clear()
	for order in _rules().orders: order.wait = 0.0
	guide._angry_pending = false
	_rules().gold = 20000
	for id in ["seal", "mix", "press", "topping"]: _rules().unlock(id)
	_rules().unlock_box("milk")
	for stage in range(1, 6): guide.seen["line_%d" % stage] = true
	guide.seen["box_milk"] = true
	guide.refresh(0)
	_check(_rules().stage_index == 5 and guide.active == "more_staff" and guide._hole.intersects(_local(hud.tab("staff"))), "加料线开了、还有空岗：指着员工页签")
	await _capture("more-staff")
	await _click(hud.tab("staff"))
	_check(guide._hole.intersects(_local(hud.page_node("staff").hire_button)), "员工页里再指招人")
	await _click(hud.page_node("staff").hire_button)
	_check(guide.active.is_empty() and guide.seen.has("more_staff"), "多招一位，提示结束")
	await _click(hud.tab("shop"))
	view.free()
	var reopened: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	reopened.session = TestSession.make(TEA, save_path, null, LegacySave.new(TEA, save_path))
	reopened.session.guide_enabled = true
	await _reopen(reopened)
	_check(reopened.guide.active.is_empty() and reopened.guide.seen.has("lost_machine"), "重开游戏记得看过的引导")
	reopened.free()
	var old_save := LegacyRules.new(TEA)
	old_save.unlock("lemonade")
	old_save.hire()
	old_save.deploy_worker(old_save.roster[1].id)
	LegacySave.new(TEA, save_path).save_game(old_save, 1.0, [])
	var veteran: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	veteran.session = TestSession.make(TEA, save_path, null, LegacySave.new(TEA, save_path))
	veteran.session.guide_enabled = true
	await _reopen(veteran)
	_check(veteran.guide.active.is_empty() and veteran.guide.seen.has("opening"), "已经开过张的存档跳过开场")
	veteran.free()
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(save_path)
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("SHOP GUIDE GUI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## Explicit session reopens the isolated save and enables only the tutorial.
func _reopen(scene: Node2D) -> void:
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.guide.refresh(0)


func _run_until(done: Callable, limit: float) -> void:
	var spent := 0.0
	while not done.call() and spent < limit:
		view._process(0.25)
		spent += 0.25


func _screen(world: Vector2) -> Vector2:
	return view.get_node("Canvas").get_global_transform_with_canvas() * world


func _local(control: Control) -> Rect2:
	return guide._to_local(control.get_global_transform_with_canvas(), Rect2(Vector2.ZERO, control.size))


func _click(button: Button) -> void:
	for unused in 4: await process_frame
	view._refresh(0)
	guide.refresh(0)
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "按钮看得见、能按：" + (button.text if button != null else "null"))
	if button == null: return
	await _press(button.get_global_transform_with_canvas() * (button.size / 2.0))


## 只有触屏事件，没有 Godot 平常顺手生成的鼠标事件
func _touch(point: Vector2) -> void:
	var emulate := Input.is_emulating_mouse_from_touch()
	Input.emulate_mouse_from_touch = false
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	Input.emulate_mouse_from_touch = emulate
	guide.refresh(0)
	await process_frame


func _press(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	view._refresh(0)
	guide.refresh(0)
	await process_frame
	guide.refresh(0)


func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from
	press.pressed = true
	Input.parse_input_event(press)
	for i in 6:
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, (i + 1) / 6.0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await process_frame
	var release := press.duplicate()
	release.position = to
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame


func _capture(suffix: String) -> void:
	if DisplayServer.get_name() == "headless": return
	guide.refresh(0.4)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("user://shop-guide-" + suffix + ".png") == OK, "截图存好")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)


## 奶茶店的客人不走，等久了变生气
func _make_angry(takeaway: bool) -> void:
	if _rules().orders.is_empty(): _rules()._add_order()
	_rules().orders[-1].wait = _rules().shop.fulfillment.mood_seconds[1] + 1.0
	_rules().orders[-1].takeaway = takeaway
	_rules().orders[-1].seat = -1
