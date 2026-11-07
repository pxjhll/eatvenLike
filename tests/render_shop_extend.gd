extends SceneTree
## 扩展验收（规格 §6.2.1）：不改 HUD 核心，从外面加一个页签和它的页面、弹一张奇遇卡、显示一个进行中加成的图标，
## 都要能看见、能点；另外新场景能整局跑下去不报错（读档、存档、重开都走一遍）。

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()
var view: Node2D
var save_path := "user://shop-extend-%d.json" % OS.get_process_id()


func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(720, 1280)
	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	view.rules = ShopRules.new(TEA)
	view.store = ShopSave.new(TEA, save_path)
	root.add_child(view)
	await process_frame
	view.set_process(false)
	var hud: Control = view.ui
	var rules: ShopRules = view.rules
	rules.unlock("lemonade")

	# 1. 假页签 + 假页面：register_tab / register_page
	var page := Label.new()
	page.text = "假页面"
	hud.register_page("fake", page, {"title": "假页面", "icon": "goals"})
	var tab: Button = hud.register_tab("fake", "假的", "goals", "fake")
	await process_frame
	_check(tab != null and tab.is_visible_in_tree() and hud.tab("fake") == tab, "新页签出现在底栏")
	await _click(tab)
	_check(hud.page == "fake" and page.is_visible_in_tree(), "点新页签打开新页面")
	await _click(hud.tab("shop"))
	_check(hud.page == "shop" and not page.is_visible_in_tree(), "点店铺收起面板")

	# 2. 假奇遇卡：规则层触发一张要选的卡，界面弹卡队列接住，选了以后规则层应用效果
	var ev := SpecEvent.new()
	ev.id = "fake_investor"
	ev.display_name = "投资人来了"
	ev.card_text = "给你一笔钱，要不要？"
	ev.icon = "coin"
	ev.choices.assign([{"label": "收下", "accept": true}, {"label": "不要", "accept": false}])
	var bonus := SpecEffect.new()
	bonus.kind = "grant_gold"
	bonus.op = "add"
	bonus.value = 100.0
	ev.effects.assign([bonus])
	rules.event_defs.append(ev)
	var gold := rules.gold
	rules.trigger_event(ev)
	view._refresh(0.0)
	await process_frame
	_check(hud.popups.has_card("event:fake_investor") and view.frozen(), "奇遇卡弹出来，店停着")
	_check(hud.popups._title.text == "投资人来了", "卡片标题来自奇遇数据")
	await _click(hud.popups.button(0))
	_check(rules.pending_events.is_empty() and not hud.popups.has_card() and is_equal_approx(rules.gold, gold + 100.0), "选“收下”：卡片关掉，金币到账")

	# 3. 进行中加成：顶栏下面出一个图标，倒计时，过时消失
	rules.apply_effect("event", "fake_investor", SpecEffect.make("flow", "mul", 2.0), 30.0)
	view._refresh(0.0)
	await process_frame
	var bar: Control = hud.get_node("%UnderHeader").get_children().filter(func(n: Node) -> bool: return n is HBoxContainer).front()
	_check(bar.is_visible_in_tree() and bar.get_child(0).visible, "加成图标显示出来")
	_check(bar.get_child(0).get_node("Row/Left").text == "30 秒", "加成图标写着剩几秒")
	rules.step(31.0)
	view._refresh(0.0)
	_check(not bar.visible, "加成过时图标消失")

	# 拖人：把后厨的人拖到煮茶机的坐班位，再拖回空地
	rules.gold = 2000.0
	rules.unlock("boil")
	rules.unlock_box("tea_leaf")
	view.hire_worker()
	var cook: Dictionary = rules.workers.filter(func(w: Dictionary) -> bool: return w.post != rules.counter_id).front()
	view._refresh(0.0)
	await _drag(_screen(cook.pos + Vector2(0, -40)), _screen(view.anchors.meta("Drops/2", "point")))
	_check(cook.post == "boil", "拖到煮茶机：坐班")
	await _drag(_screen(cook.pos + Vector2(0, -40)), _screen(Vector2(300, 480)))
	_check(cook.post == "" and cook.deployed, "拖回空地：恢复流动")

	# 调参面板：机器一行一个，拖了马上生效
	view.tuning.toggle()
	var keys: Array = view.tuning.rows.map(func(row: Array) -> String: return row[0])
	_check(view.tuning.visible and "boil" in keys and "price" in keys and not "counter" in keys, "调参面板按店铺数据列出各行")
	view.tuning.set_value("boil", 1.5)
	_check(is_equal_approx(rules.tuned("boil"), 1.5), "调参马上生效")
	view.tuning.set_value("boil", 1.0)
	view.tuning.toggle()

	# 4. 整局：跑十分钟店内时间、存档、读档接着跑、重开
	for unused in 2400: view._process(0.25)
	_check(rules.sold > 0, "新场景能接着卖")
	_check(view.save_now(false) == OK, "存档成功")
	var reopened: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	reopened.store = ShopSave.new(TEA, save_path)
	root.add_child(reopened)
	await process_frame
	reopened.set_process(false)
	_check(is_equal_approx(reopened.rules.clock, rules.clock) and reopened.rules.sold == rules.sold, "读档回到同一时刻")
	for unused in 40: reopened._process(0.25)
	reopened.restart()
	_check(reopened.rules.sold == 0 and reopened.rules.clock == 0.0, "重开回到空店")
	reopened.free()
	view.free()
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(save_path)
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("SHOP EXTEND: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _click(button: Button) -> void:
	for unused in 3: await process_frame
	view._refresh(0)
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "按钮看得见、能按：" + (button.text if button != null else "null"))
	if button == null: return
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size / 2.0)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	view._refresh(0)
	await process_frame


func _screen(world: Vector2) -> Vector2:
	return view.get_node("Canvas").get_global_transform_with_canvas() * world


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


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
