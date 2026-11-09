extends SceneTree

const TestSession := preload("res://tests/shop_test_session.gd")
## 煎饼摊跑在通用店铺场景里（第 4 个 PR），用真实点按走一遍：
## 从跨店记录进店、引导（欢迎 → 点豆浆机开张 → 第一单 → 招第二个人 → 开张完成）、原画按开店进度显示、
## 人物按脚底前后遮挡、客人排队和坐坐垫、点柜台发传单、完店 → 结店总结 → 去奶茶店、读档接着开。

const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const Profile := preload("res://game/app/profile.gd")
var view: Node2D
var hud: Control
var guide: Control
var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()
var save_path := "user://shop-pancake-gui-%d.json" % OS.get_process_id()
var profile_path := "user://profile-pancake-gui-%d.json" % OS.get_process_id()


func _initialize() -> void:
	Input.use_accumulated_input = false
	OS.add_logger(errors)
	call_deferred("_run")


func _rules() -> ShopRules:
	return view.rules


func _stall(id: int) -> CanvasItem:
	return view.art.get_node("Stall").source_node(id)


func _run() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		print("SHOP PANCAKE GUI: timed out before completing checks")
		quit(1))
	root.size = Vector2i(720, 1280)
	for path in [save_path, profile_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var profile := Profile.new(profile_path)
	profile.reset_all()
	_check(profile.shop == "pancake", "新玩家从煎饼摊开始")
	view = _open(profile)
	await process_frame
	view.set_process(false)
	hud = view.ui
	guide = view.guide
	_check(_rules().shop.id == "pancake" and guide.enabled, "按跨店记录进煎饼摊，放引导")

	# 原画：开店前只有固定摆设和前台；面粉箱、加料台、柜台上的袋子盒子都没摆
	view._refresh(0)
	_check(_stall(46).is_visible_in_tree(), "前台开局就在")
	_check(not _stall(161).is_visible_in_tree() and not _stall(21).is_visible_in_tree(), "豆浆机、鏊子没开之前看不见")
	_check(not _stall(27).is_visible_in_tree() and not _stall(140).visible, "面粉箱和面粉的字没买之前藏着")
	_check(not _stall(200).is_visible_in_tree() and not _stall(210).is_visible_in_tree(), "加料台、柜台袋子盒子没开之前看不见")
	_check(view.anchors.points("Waiting").is_empty() and view.anchors.point("Exit") != Vector2.INF, "客人从左边进、下边走：有出口锚点，不用旧的等候点")
	for id in [165, 164, 163]: _check(not _stall(id).is_visible_in_tree(), "坐垫 %d 开局不摆" % id)

	# 引导：欢迎卡 → 指豆浆机的虚线框 → 面板里的解锁键
	guide.refresh(0)
	_check(guide.active == "welcome" and hud.popups.has_card("guide:welcome") and view.frozen(), "先弹欢迎卡，店停着")
	await _click(hud.popups.button(hud.popups.primary_index()))
	_check(guide.active == "opening" and guide._hole.intersects(_local(view._station_buttons.soy_milk)), "手指指着豆浆机的虚线框")
	await _click(view._station_buttons.soy_milk)
	_check(hud.page == "station" and guide._hole.intersects(_local(hud.page_node("station").unlock_button)), "面板里手指移到解锁键")
	await _click(hud.page_node("station").unlock_button)
	_check(_rules().is_open() and _stall(161).is_visible_in_tree(), "开张：豆浆机摆出来")
	await _click(hud.tab("shop"))
	_check(not guide.freezes() and guide._bubble.visible, "等第一单边卖边提示，不压暗")
	_run_until(func() -> bool: return _rules().sold > 0, 120.0)
	guide.refresh(0)
	_check(_rules().sold > 0 and guide.active == "", "第一单卖出去，引导收起")

	# 客人：在柜台前排队（点完单没坐垫的人也留在队里，排在前面），豆浆机后面的员工被柜台挡住
	_run_until(func() -> bool: return _rules().customers.any(func(c: Dictionary) -> bool: return c.state in ["queue", "paid"]), 60.0)
	view._process(0.1)
	var line: Array = _rules().customers.filter(func(c: Dictionary) -> bool: return c.state == "paid")
	var queued: int = int(line[0].id) if not line.is_empty() else int(_rules().queue[0])
	for unused in 60: view._refresh(0.25)
	var first: Node2D = view._customers.get(queued)
	_check(first != null and first.position.distance_to(view.anchors.points("Queue")[0]) < 2.0, "排第一的客人站在队伍第一位")
	_check(first != null and first.z_index > _stall(46).z_index, "柜台前的客人画在柜台上面")
	var staff: Node2D = view._actors.values()[0]
	_check(staff.z_index < _stall(46).z_index, "柜台后面的员工画在柜台下面")
	_check(view._station_buttons.rear_equipment.z_index + view.get_node("Canvas/WorldLabels").z_index > 1678, "解锁框在所有人物上面")

	# 开鏊子：引导指“员工”页签和招人键，招到人出“开张完成”
	_rules().gold = 60.0
	await _click(view._station_buttons.rear_equipment)
	await _click(hud.page_node("station").unlock_button)
	_check(_rules().station_unlocked("rear_equipment") and _stall(21).is_visible_in_tree() and not _stall(27).is_visible_in_tree(), "开鏊子：鏊子摆出来，面粉箱还没买")
	_check(not _stall(165).is_visible_in_tree(), "坐垫要自己买，开鏊子不白送")
	_rules().gold = 60.0
	_check(_rules().buy_seat() == "" and _rules().seat_error() == "下一阶段开放更多座位", "第 2 段只能买第一批 2 个坐垫")
	view._refresh(0)
	_check(_stall(165).is_visible_in_tree() and not _stall(164).is_visible_in_tree(), "买了第一批坐垫就摆出来")
	# 坐下的客人一直坐在同一个坐垫上，直到拿到餐离开
	var seat_of := {}
	var moved := 0
	for unused in 400:
		view._process(0.25)
		for id in view._seat_of:
			if seat_of.has(id) and seat_of[id] != view._seat_of[id]: moved += 1
			seat_of[id] = view._seat_of[id]
	_check(not seat_of.is_empty() and moved == 0, "坐下的客人不换坐垫（坐过 %d 位，换位 %d 次）" % [seat_of.size(), moved])
	await _click(hud.tab("shop"))
	_rules().gold = 60.0
	guide.refresh(0)
	_check(guide.active == "hire" and guide._hole.intersects(_local(hud.tab("staff"))), "开鏊子后手指指着“员工”页签")
	await _click(hud.tab("staff"))
	_check(guide._hole.intersects(_local(hud.page_node("staff").hire_button)), "员工页里手指移到招人键")
	await _click(hud.page_node("staff").hire_button)
	_check(_rules().workers.size() == 2, "招到第二个人，直接上岗")
	await _click(hud.tab("shop"))
	guide.refresh(0)
	_check(guide.active == "done" and hud.popups.has_card("guide:done"), "招到人出“开张完成”卡")
	await _click(hud.popups.button(hud.popups.primary_index()))
	_rules().gold = 60.0
	guide.refresh(0)
	_check(guide.active == "box_flour" and guide._hole.intersects(_local(view._station_buttons.raw_ingredients)), "鏊子要面粉：手指指着原料台")
	await _click(view._station_buttons.raw_ingredients)
	await _click(hud.page_node("station").material_buttons.get("flour"))
	view._refresh(0)
	_check(bool(_rules().boxes.flour) and _stall(27).is_visible_in_tree() and _stall(140).visible, "买了面粉箱：面粉袋和字摆出来")
	await _click(hud.tab("shop"))
	guide.refresh(0)
	_check(guide.active == "" and not hud.popups.has_card(), "引导走完")

	# 点柜台：面板里发传单，传单没有升级就不显示升级那一行
	await _press(_screen(view.anchors.rect("Stations/front_counter/Tap").get_center() + Vector2(200, 40)))
	_check(hud.page == "station" and hud.page_node("station").station_id == "front_counter", "点柜台打开柜台面板")
	var flyer_button: Button = _find_button(hud.page_node("station"), "发传单")
	await _click(flyer_button)
	_check(_rules().flyer_left > 0, "发了传单，客人陆续来")
	await _click(hud.tab("shop"))

	# 点鏊子：面板写每份几秒
	await _press(_screen(view.anchors.rect("Stations/rear_equipment/Tap").get_center()))
	_check(hud.page == "station" and hud.page_node("station").station_id == "rear_equipment", "点鏊子打开鏊子面板")
	_check(_texts(hud.get_node("%Sheet")).any(func(t: String) -> bool: return t.contains("10.0 秒")), "鏊子面板写着每份 10 秒")
	await _click(hud.tab("shop"))

	# 存档、读档：开着的台子、员工、看过的引导都还在
	_check(view.save_now(false) == OK, "存档")
	view.free()
	view = _open(Profile.new(profile_path))
	await process_frame
	view.set_process(false)
	hud = view.ui
	guide = view.guide
	guide.refresh(0)
	_check(_rules().station_unlocked("rear_equipment") and _rules().workers.size() == 2, "读档：鏊子开着、两个人")
	_check(guide.active == "" and not hud.popups.has_card(), "读档：看过的引导不再弹")
	view._refresh(0)
	_check(_stall(21).is_visible_in_tree(), "读档：画面跟着开")

	# 调参面板：跳到上一家 / 下一家店（第一家没有上一家）
	view.change_scene_on_leave = false
	_check(view.jump_shop(-1) == "", "第一家店没有上一家")
	_check(view.jump_shop(1) == "tea" and view.profile.shop == "tea" and not view.profile.fresh_shop, "跳到下一家奶茶店")
	_check(FileAccess.file_exists(save_path), "跳店前存好煎饼摊")
	_check(view.profile.select_shop("pancake") == OK, "通过跨店提交切回煎饼摊")
	# 接受跳店后的场景已经结束其会话；从刚持久化的 Profile 重开，继续验证结店。
	view.free()
	view = _open(Profile.new(profile_path))
	await process_frame
	view.set_process(false)
	hud = view.ui
	guide = view.guide
	guide.refresh(0)

	# 完店：弹完店卡，目标页出“结店”，总结卡第一下只提醒，第二下去奶茶店
	_rules().gold = 99999
	for id in ["fryer", "topping", "bag"]: _rules().unlock(id)
	for id in ["soy_milk", "rear_equipment", "topping"]:
		while _rules().upgrade_cost(id) >= 0: _rules().upgrade(id)
	for dish in ["ham", "floss", "bacon", "family"]:
		while _rules().upgrade_cost("topping/" + dish) >= 0: _rules().upgrade("topping/" + dish)
	while _rules().buy_seat() == "": pass
	for row in _rules().task_rows():
		var task: SpecTask = null
		for stage in PANCAKE.stages:
			for t in stage.tasks:
				if t.id == row.id: task = t
		if task != null and task.condition == "sell_count": _rules().sold_by_dish[task.target] = int(task.amount)
	view._process(0.25)
	view._refresh(0)
	_check(_rules().completed_at >= 0.0, "任务都完成就算完店")
	_check(_stall(163).is_visible_in_tree(), "加料段 9 个坐垫全摆出来")
	_check(_stall(200).is_visible_in_tree() and _stall(210).is_visible_in_tree(), "加料台、柜台袋子盒子都摆出来")
	for tray in [201, 202, 203, 204]: _check(_stall(tray).is_visible_in_tree(), "口味开了，料盘 %d 摆出来" % tray)
	guide.refresh(0)
	_check(guide.active == "shop_done" and hud.popups.has_card("guide:shop_done"), "弹完店卡")
	var primary: Button = hud.popups.button(hud.popups.primary_index())
	_check(primary.text == "去下一家店" and _find_button(hud.popups, "接着营业") != null, "完店卡：主按钮去下一家店，次按钮接着营业")
	await _click(primary)
	_check(hud.popups.has_card("summary") and hud.popups._title.text.contains("煎饼果子摊"), "结店总结卡")
	_check(_texts(hud.popups).any(func(t: String) -> bool: return t.contains("评分")), "总结里有评分")
	var left := []
	view.change_scene_on_leave = false
	view.shop_left.connect(func(id: String) -> void: left.append(id))
	await _click(hud.popups.button(1))
	_check(hud.popups.has_card("summary") and hud.popups.button(1).text.contains("都不保留") and left.is_empty(), "第一下只提醒什么都不保留")
	await _click(hud.popups.button(1))
	var after := Profile.new(profile_path)
	_check(left == ["tea"] and after.shop == "tea" and after.fresh_shop and after.records.size() == 1, "去奶茶店：跨店记录换到奶茶店，留一条结店纪录")
	_check(not FileAccess.file_exists(save_path), "煎饼摊的店内存档清掉")
	_check(int(after.records[0].get("rating", 0)) >= 1 and String(after.records[0].get("shop", "")) == "pancake", "结店纪录有店名和评分")
	view.free()

	# 进奶茶店：从空店开始
	var tea_save := "user://shop-pancake-gui-tea-%d.json" % OS.get_process_id()
	var tea: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	tea.session = TestSession.make(load("res://content/shops/tea/shop.tres"), tea_save, null, ShopSave.new(load("res://content/shops/tea/shop.tres"), tea_save), after)
	tea.session.guide_enabled = true
	root.add_child(tea)
	await process_frame
	tea.set_process(false)
	_check(tea.rules.shop.id == "tea" and not tea.rules.is_open() and not after.fresh_shop, "奶茶店从空店开始")
	tea.free()
	view = _open(null, ShopRules.new(PANCAKE), false)
	await process_frame
	view.set_process(false)
	hud = view.ui
	guide = view.guide
	guide.enabled = false
	_check(not view.tuning.persist, "数值回归调参不写真实玩家配置")
	_rules().unlocked.soy_milk = true
	# 数值契约：培养后的实际属性与可见员工卡一致，所有人工设备调参都显示基准操作。
	_rules().gold = 99999
	_rules().upgrade("staff/")
	await _click(hud.tab("staff"))
	var staff_page: Control = hud.page_node("staff")
	_check(staff_page._numbers.walk.text == str(int(_rules().walk_speed(_rules().workers[0]))), "培养后可见移速等于执行移速")
	_check(staff_page._levels[0].text.contains("1/"), "员工卡显示店内培养进度")
	_rules().tune.work = 1.25
	view._refresh(0)
	_check(staff_page._numbers.work.text == "1.25", "可见操作倍率保留两位有效小数")
	view.tuning.toggle()
	view.tuning.set_value("rear_equipment", 3.0)
	_check(view.tuning._nows.rear_equipment.text.contains("30.0") and view.tuning._nows.rear_equipment.text.contains("基准"), "调参可见实际人工基准秒数")
	_check(view.tuning._sliders.has("roll") and view.tuning._sliders.has("bag"), "卷饼和打包有可用时间滑杆")
	view.tuning.reset_all()
	view.tuning.toggle()
	await _click(hud.tab("shop"))

	view.free()
	for path in [save_path, profile_path, tea_save]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("SHOP PANCAKE GUI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _open(profile: RefCounted, rules: ShopRules = null, guides := true) -> Node2D:
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(PANCAKE, save_path, rules, ShopSave.new(PANCAKE, save_path), profile)
	scene.session.guide_enabled = guides
	root.add_child(scene)
	return scene


func _run_until(done: Callable, limit: float) -> void:
	var spent := 0.0
	while not done.call() and spent < limit:
		view._process(0.25)
		spent += 0.25


func _find_button(node: Node, text: String) -> Button:
	for child in node.find_children("*", "Button", true, false):
		if child.is_visible_in_tree() and String(child.text) == text: return child
	return null


func _texts(node: Node) -> Array:
	var out: Array = []
	for child in node.find_children("*", "Label", true, false):
		if child.is_visible_in_tree(): out.append(String(child.text))
	return out


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


func _press(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	if not is_instance_valid(view): return
	view._refresh(0)
	guide.refresh(0)
	await process_frame
	guide.refresh(0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
