extends SceneTree

const TestSession := preload("res://tests/shop_test_session.gd")
## 奶茶店跑在通用店铺场景里，用真实点按走一遍（旧 render_shop_ui / render_tea_business / render_tuning 搬过来）：
## 空店只画柠檬水台的虚线框，点框开解锁面板，开张、开煮茶机、在原料柜面板买茶叶箱；员工页招人直接上后厨；
## 点柜台买座位、发传单；机器面板升级、原料升级涨价；买传送带；手动存档再读档一模一样；
## 菜单暂停、换页不改暂停、Esc 收面板；重开先确认、取消不动、确认才重开；调参面板改得动、还原得回去。
##   godot --headless --path . -s tests/render_shop_tea.gd

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
var view: Node2D
var hud: Control
var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()
var save_path := "user://shop-tea-gui-%d.json" % OS.get_process_id()


func _initialize() -> void:
	Input.use_accumulated_input = false
	OS.add_logger(errors)
	call_deferred("_run")


func _rules() -> ShopRules:
	return view.rules


func _run() -> void:
	root.size = Vector2i(720, 1280)
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(save_path)
	view = _open(ShopRules.new(TEA))
	await process_frame
	view.set_process(false)
	hud = view.ui

	# 空店：只有柠檬水台的虚线框，买得起就有红 ↑
	view._refresh(0)
	_check(not _rules().is_open() and int(_rules().gold) == 50, "新店从空店、50 金币开始")
	_check(_frame("lemonade").is_visible_in_tree() and not _frame("boil").is_visible_in_tree(), "只显示下一台（柠檬水台）的虚线框")
	_check(_frame("lemonade").can_unlock, "买得起的框上有红 ↑")
	await _click(view._station_buttons.lemonade)
	_check(hud.page == "station" and hud.page_node("station").station_id == "lemonade", "点框打开柠檬水台的解锁面板")
	await _click(hud.page_node("station").unlock_button)
	_check(_rules().is_open() and int(_rules().gold) == 40, "开张花 10 金币")
	await _click(hud.tab("shop"))
	view._refresh(0)
	_check(_frame("boil").is_visible_in_tree() and not _frame("lemonade").is_visible_in_tree(), "开张以后只显示煮茶机的框")
	_run_until(func() -> bool: return _rules().sold > 0, 120.0)
	_check(_rules().revenue > 0, "开张以后真的卖出去")

	# 煮茶机 → 原料柜买茶叶箱
	_rules().gold = float(_rules().next_stage_cost())
	await _click(view._station_buttons.boil)
	await _click(hud.page_node("station").unlock_button)
	_check(_rules().station_unlocked("boil") and not _rules().station_unlocked("seal"), "煮茶机按阶段价格单独开")
	await _click(hud.tab("shop"))
	_rules().gold = 20.0
	view._refresh(0)
	_check(view._station_buttons.has("supply") and view._station_buttons.supply.is_visible_in_tree(), "原料柜上有框，等着买茶叶箱")
	await _click(view._station_buttons.supply)
	_check(hud.page_node("station").station_id == "supply", "点原料柜打开原料柜面板")
	var box: Button = hud.page_node("station").material_buttons.get("tea_leaf")
	await _click(box)
	_check(bool(_rules().boxes.tea_leaf), "在原料柜面板里买到茶叶箱")
	await _click(hud.tab("shop"))

	# 员工页招人：有后厨名额就直接上岗，开局的人留在柜台
	_rules().gold = 100.0
	await _click(hud.tab("staff"))
	await _click(hud.page_node("staff").hire_button)
	_check(_rules().workers.size() == 2 and _rules().workers[0].post == "counter", "招来的人直接上后厨，开局的人守柜台")
	await _click(hud.tab("shop"))
	_run_until(func() -> bool: return int(_rules().sold_by_dish.black_tea) > 0, 240.0)
	_check(int(_rules().sold_by_dish.black_tea) > 0, "煮好的红茶卖出去")

	# 点柜台：买座位、发传单
	_rules().gold = 1000.0
	await _click(view._seats)
	_check(hud.page == "station" and hud.page_node("station").station_id == "counter", "点柜台打开柜台面板")
	var seats := _rules().seat_total()
	await _click(hud.page_node("station").seat_button)
	_check(_rules().seat_total() > seats, "柜台面板里买座位")
	await _click(hud.page_node("station").flyer_button)
	_check(_rules().flyer_pending > 0 or _rules().flyer_wave > 0.0, "柜台面板里发传单")
	await _click(hud.tab("shop"))

	# 机器面板升级、原料升级涨价
	await _tap("boil")
	var level := _rules().level("boil")
	await _click(hud.page_node("station").upgrade_button)
	_check(_rules().level("boil") == level + 1, "煮茶机面板里升级")
	await _click(hud.tab("shop"))
	await _tap("supply")
	var black := _rules().dish_price("black_tea")
	await _click(hud.page_node("station").material_buttons.get("tea_leaf"))
	_check(_rules().dish_price("black_tea") > black, "原料柜面板里升茶叶，红茶涨价")
	await _click(hud.tab("shop"))

	# 开到调奶台，买封口机 → 外带架的传送带
	_rules().gold = 100000.0
	for id in ["seal", "mix"]: _rules().unlock(id)
	_rules().unlock_box("milk")
	view._refresh(0)
	var belt: String = _rules().connection_rows()[0].id
	_check(view._station_buttons.has("connection:" + belt) and view._station_buttons["connection:" + belt].is_visible_in_tree(), "调奶台以后传送带有虚线框")
	if view._station_buttons.has("connection:" + belt):
		await _click(view._station_buttons["connection:" + belt])
		_check(_rules().belts.get(belt, false), "点框买下传送带")
	await _click(hud.tab("shop"))

	# 点顶栏目标打开目标页
	await _click(hud.get_node("%Goal"))
	_check(hud.page == "goals", "点目标打开目标页")
	await _click(hud.tab("shop"))

	# 手动存档 → 新场景读档：店和员工都一样
	_run_until(func() -> bool: return false, 30.0)
	_check(view.save_now(false) == OK, "存档")
	var saved := _rules().to_dict()
	view.free()
	view = _open(null, true)
	# 刚读进来、还没走一帧时比；调参倍率存在 tuning.cfg（和存档分开），不比
	var loaded := _rules().to_dict()
	var differing: Array = saved.keys().filter(func(k: String) -> bool: return k != "tune" and var_to_str(saved[k]) != var_to_str(loaded.get(k)))
	_check(differing.is_empty(), "读档：整店状态和员工一模一样（不一样的：%s）" % [differing.map(func(k: String) -> String: return "%s %s→%s" % [k, saved[k], loaded.get(k)])])
	_check(view.guide_enabled and not view.recorder.enabled and not view.tuning.persist, "显式引导测试不录制、不持久化调参")
	view.set_process(false)
	view.free()
	view = _open(ShopRules.new(TEA))
	await process_frame
	view.set_process(false)
	hud = view.ui
	_rules().unlock("lemonade")

	# 菜单：暂停、换页不改暂停、Esc 收面板不取消暂停
	await _click(hud.get_node("%Menu"))
	_check(hud.page == "menu", "菜单打开")
	await _click(hud.page_node("menu").pause_button)
	_check(_rules().paused, "菜单里暂停营业")
	await _click(hud.tab("goals"))
	_check(_rules().paused, "换页不会取消暂停")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	Input.flush_buffered_events()
	await process_frame
	_check(hud.page == "shop" and _rules().paused, "Esc 收起面板，不取消暂停")
	hud.open_page("menu")
	await _click(hud.page_node("menu").pause_button)
	_check(not _rules().paused, "再按一下继续营业")

	# 重开：先确认，取消什么都不变，确认才清掉店内员工和培养；试玩记录另起一局
	_rules().gold = 1000.0
	_check(_rules().hire() == "" and _rules().upgrade("staff/front") == "", "重开前招募员工并购买培养")
	var record_path := "user://shop-tea-gui-recorder-%d.txt" % OS.get_process_id()
	if FileAccess.file_exists(record_path): DirAccess.remove_absolute(record_path)
	view.recorder.file_path = record_path
	view.recorder.enabled = true
	view.recorder.setup(_rules())
	_run_until(func() -> bool: return false, 90.0)
	_check(_rules().sold > 0, "重开之前已营业并录下收入")
	var before := _rules().to_dict()
	await _click(hud.page_node("menu").restart_button)
	_check(hud.page == "restart", "重新开始先问一句")
	await _click(hud.page_node("restart").cancel_button)
	_check(_rules().to_dict() == before, "取消重开什么都不变")
	hud.open_page("restart")
	await _click(hud.page_node("restart").confirm_button)
	_check(not _rules().is_open() and int(_rules().gold) == 50 and hud.page == "shop", "确认以后重开成空店，回到店铺")
	_check(_rules().roster.size() == 1 and _rules().level("staff/front") == 0, "重开清掉店内招募员工和培养等级")
	var reset_save: ShopRules = view.store.load_game()
	_check(reset_save.roster.size() == 1 and reset_save.level("staff/front") == 0, "重开结果已保存")
	var reset_rows: PackedStringArray = view.recorder.text().split("\n", false)
	var last_row: Dictionary = JSON.parse_string(reset_rows[reset_rows.size() - 1])
	_check(last_row.has("session") and int(last_row.t) == 0, "重开记录新的会话起点")
	var line_count: int = view.recorder.line_count()
	_run_until(func() -> bool: return false, 59.75)
	_check(view.recorder.line_count() == line_count, "重开后不足一分钟不采样")
	view._process(0.25)
	reset_rows = view.recorder.text().split("\n", false)
	last_row = JSON.parse_string(reset_rows[reset_rows.size() - 1])
	_check(view.recorder.line_count() == line_count + 1 and int(last_row.t) == 60, "重开后第一条采样在一分钟")
	_check(float(last_row.get("income", -1)) == 0.0 and int(last_row.get("cups", -1)) == 0 and int(last_row.get("lost", -1)) == 0, "重开后采样没有沿用上一局的收入、销量和流失")
	view.recorder.enabled = false
	DirAccess.remove_absolute(record_path)

	# 调参面板：菜单底下的按钮打开，滑杆改得动规则层，还原、收起
	var panel: PanelContainer = view.tuning
	_check(panel != null and not panel.visible, "调参面板开局收着")
	_check(view.recorder != null and not view.recorder.enabled, "测试场景不写试玩记录")
	hud.open_page("menu")
	await _click(hud.page_node("menu").footer.find_child("Tuning", true, false))
	_check(panel.visible, "调参按钮打开面板")
	var seat := _rules().seat_seconds()
	panel.set_value("seat", 0.5)
	_check(is_equal_approx(_rules().seat_seconds(), seat * 0.5), "用餐时间减半，客人坐一半时间")
	var interval := _rules()._order_interval()
	panel.set_value("customer", 2.0)
	_check(is_equal_approx(_rules()._order_interval(), interval * 2.0), "来客间隔拉长一倍")
	panel.set_value("customer", 9.0)
	_check(is_equal_approx(_rules().tuned("customer"), 3.0), "滑杆有上限")
	await _click(panel.find_child("Reset", true, false))
	_check(is_equal_approx(_rules().seat_seconds(), seat) and is_equal_approx(_rules()._order_interval(), interval), "还原回设计数值")
	await _click(panel.find_child("Close", true, false))
	_check(not panel.visible, "收起面板")

	view.free()
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(save_path)
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("SHOP TEA GUI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## Explicit fixture services; a null rules argument reopens its isolated shop save.
func _open(rules: ShopRules = null, guides := false) -> Node2D:
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(TEA, save_path, rules, ShopSave.new(TEA, save_path))
	scene.session.guide_enabled = guides
	root.add_child(scene)
	return scene


## 点店里的机器（先把它滚进画面）
func _tap(id: String) -> void:
	var rect: Rect2 = view.anchors.station_rects()[id]
	view.reveal_world(rect)
	await process_frame
	await _press(_screen(rect.get_center()))
	_check(hud.page == "station" and hud.page_node("station").station_id == id, "点 %s 打开它的面板" % id)


func _frame(id: String) -> Control:
	return view._station_buttons.get(id)


func _run_until(done: Callable, limit: float) -> void:
	var spent := 0.0
	while not done.call() and spent < limit:
		view._process(0.25)
		spent += 0.25


func _screen(world: Vector2) -> Vector2:
	return view.get_node("Canvas").get_global_transform_with_canvas() * world


func _click(button: Control) -> void:
	for unused in 4: await process_frame
	view._refresh(0)
	var ok: bool = button != null and button.is_visible_in_tree() and not (button is BaseButton and button.disabled)
	_check(ok, "按钮看得见、能按：" + (String(button.get("text")) if button != null else "null"))
	if not ok: return
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
	await process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
