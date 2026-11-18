extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const LegacySave := preload("res://tests/fixtures/legacy_shops/reference_save.gd")

const TestSession := preload("res://tests/shop_test_session.gd")
## 通用店铺场景里的奶茶店引导（数据驱动，§6.3），用真实点按走一遍：欢迎卡、柠檬水、第一杯、开店上手卡、
## 后面的开线、原料箱、后厨招人、客人等急、加料线以后的多招人；重开游戏记得看过哪些。
## 和旧场景的 render_guide.gd 一一对应（旧场景删掉时这个留下）。

const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/current/tea/shop.tres")
const CURRENT_TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
class RollBottleneck extends ShopView:
	func _guide_slow_machine() -> String:
		return "roll"

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
	await _tea_contextual_guides()
	await _pancake_first_sale()
	await _pancake_late_guides()
	await _pancake_roll_hint()
	await _pancake_skip_tutorial(false)
	await _pancake_skip_tutorial(true)
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(save_path)
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("SHOP GUIDE GUI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _tea_contextual_guides() -> void:
	var path := save_path + "-current-tea"
	var store := ShopSave.new(CURRENT_TEA, path)
	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	view.session = TestSession.make(CURRENT_TEA, path, null, store)
	view.session.guide_enabled = true
	await _reopen(view)
	hud = view.ui
	guide = view.guide
	_check(guide.active == "tea_opening_notice" and guide._show_notice and not view.frozen() and not hud.popups.has_card(),
		"正式奶茶店直接进店面，开张提示不暂停、不弹卡")
	await _click(view._station_buttons.lemonade)
	_check(hud.page == "station" and not guide._bubble.visible, "开张提示不挡设备面板，也不留在面板上")
	await _click(hud.page_node("station").unlock_button)
	await _click(hud.tab("shop"))
	_run_until(func() -> bool: return _rules().sold > 0, 120.0)
	_check(_rules().sold > 0 and guide.active.is_empty() and not hud.popups.has_card(), "首杯自动卖出，没有首单或上手教学")
	_rules().gold = 20000.0
	guide.refresh(0.0)
	_check(guide.active.is_empty(), "金币够开下一台时，基础开线教学不弹")
	await _click(view._station_buttons.boil)
	await _click(hud.page_node("station").unlock_button)
	await _click(hud.tab("shop"))
	_check(guide.active == "tea_kitchen_roles" and guide._show_notice and not view.frozen(), "煮茶机开通后解释前后厅分工")
	var clock := _rules().clock
	view._process(0.25)
	_check(_rules().clock > clock, "分工提示出现时营业继续")
	await _click(hud.tab("staff"))
	guide.refresh(5.0)
	_check(hud.page == "staff" and guide.active == "tea_kitchen_roles" and not guide._bubble.visible,
		"短提示不抢员工页，隐藏期间也不消耗显示时间")
	await _click(hud.tab("shop"))
	guide.refresh(4.0)
	guide.refresh(0.0)
	guide.refresh(0.0)
	_check(guide.seen.has("tea_kitchen_roles") and guide.active == "box_tea_leaf" and not view.frozen(), "分工提示到时收起，缺茶叶时提示去原料柜")
	await _click(view._station_buttons.supply)
	await _click(hud.page_node("station").material_buttons.tea_leaf)
	await _click(hud.tab("shop"))
	_check(guide.active == "kitchen" and guide._show_notice and not view.frozen(), "茶叶箱买好后，缺后厨才提示招募或派岗")
	await _click(hud.tab("staff"))
	await _click(hud.page_node("staff").hire_button)
	await _click(hud.tab("shop"))
	_check(_rules().kitchen_staff() == 1 and guide.active.is_empty(), "后厨有人上岗后，缺人提示自动消失")
	_run_until(func() -> bool: return int(_rules().sold_by_dish.black_tea) > 0, 240.0)
	_check(int(_rules().sold_by_dish.black_tea) > 0 and not guide.seen.has("tea_sealing"), "堂食红茶可正常售出，且不触发封口提示")
	_check(_rules().unlock("seal").is_empty(), "用正式规则解锁封口机")
	guide.refresh(0.0)
	_check(guide.active.is_empty(), "单独解锁封口机不触发提示")
	_run_until(func() -> bool: return guide.active == "tea_sealing", 240.0)
	_check(guide.active == "tea_sealing" and view.view.has_order_requiring_processing("seal") and not view.frozen(),
		"实际接到需要封口的订单后，才出现封口说明")
	guide.refresh(4.0)
	guide.refresh(0.0)
	_check(guide.seen.has("tea_sealing") and not guide._bubble.visible, "封口提示自动收起并记为看过")

	view.free()
	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	view.session = TestSession.make(CURRENT_TEA, path, null, ShopSave.new(CURRENT_TEA, path))
	view.session.guide_enabled = true
	await _reopen(view)
	_check(view.guide.seen.has("tea_sealing") and view.guide.active.is_empty() and view.rules.kitchen_staff() == 1,
		"正式存档恢复营业进度，已看提示不重复")
	view.free()
	DirAccess.remove_absolute(path)


func _pancake_first_sale() -> void:
	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	var owner := ShopRules.new(PANCAKE, 42)
	view.session = TestSession.make(PANCAKE, save_path + "-first-sale", owner)
	view.session.guide_enabled = true
	await _reopen(view)
	hud = view.ui
	guide = view.guide
	_check(hud.popups.current().get("portrait") is AtlasTexture and not hud.popups.current().portrait_right,
		"煎饼摊欢迎卡使用店长全身立绘")
	await _capture("calico-welcome")
	await _click(hud.popups.button(hud.popups.primary_index()))
	_check(guide._dialogue_visible and guide._dialogue_heading.text == "先点豆浆机" and guide.freezes(),
		"豆浆机引导带店长和可点区域")
	await _capture("calico-unlock")
	await _click(view._station_buttons.soy_milk)
	await _click(hud.page_node("station").unlock_button)
	await _click(hud.tab("shop"))
	var employee: Node2D = view._actors[owner.workers[0].id]
	var canvas: Node2D = view.get_node("Canvas")
	var world_to_guide := guide.get_global_transform_with_canvas().affine_inverse() * canvas.get_global_transform_with_canvas()
	var head := world_to_guide * (employee.position - Vector2(0, float(employee._height) * employee.scale.y))
	_check(guide._bubble.visible and guide._bubble.position.y + guide._bubble.size.y < head.y, "首单提示在员工活动区上方")
	_check(not guide.freezes() and guide._point == Vector2.INF, "首单提示无箭头，员工继续营业")
	_check(guide._dialogue_visible and guide._dialogue_heading.text == "开张啦！", "等待首单沿用立绘提示")
	await _capture("calico-waiting", 0.0)
	var started_at := owner.clock
	_run_until(func() -> bool: return not guide._bubble.visible, 3.5)
	_check(owner.clock >= started_at + 2.75 and owner.clock <= started_at + 3.5 and owner.sold == 0, "首单提示约三秒收起，店铺时钟继续推进")
	_run_until(func() -> bool: return owner.sold > 0, 30.0)
	_check(owner.sold == 1 and guide.seen.has("opening"), "员工自动完成第一单并结束开张引导")
	guide.refresh(0)
	_check(guide.active == "first_sale" and guide._dialogue_visible and not guide.freezes(), "实际卖出首单才显示恭喜")
	await _capture("calico-sold", 0.0)
	guide.refresh(3.0)
	guide.refresh(0.0)
	_check(guide.seen.has("first_sale") and not guide._bubble.visible, "首单恭喜到时收起")
	_check(employee.frame_actor.action == "idle" and employee.frame_actor.direction == 0, "首单收银后员工朝向柜台外的顾客")
	_run_until(func() -> bool: return employee.frame_actor.action == "walk", 30.0)
	_check(employee.frame_actor.action == "walk", "员工接到下一单后继续行走")
	view.free()

func _pancake_late_guides() -> void:
	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	var owner := ShopRules.new(PANCAKE, 42)
	owner.gold = 260
	owner.unlock("soy_milk")
	owner.unlock("rear_equipment")
	owner.sold = 5
	view.session = TestSession.make(PANCAKE, save_path + "-late-guide", owner)
	view.session.guide_enabled = true
	await _reopen(view)
	hud = view.ui
	guide = view.guide
	_check(guide.seen.has("welcome") and guide.seen.has("opening") and guide.active == "box_flour",
		"旧档跳过开张和首单，缺面粉时先显示原料提示")
	_check(guide._dialogue_visible and guide._pointer_bounds.has_area() and not guide.freezes(), "面粉提示有箭头但继续营业")
	await _capture("calico-daily", 0.0)
	_check(guide._bubble.size.y < 180.0, "原料提示保持紧凑")
	await _click(view._station_buttons.raw_ingredients)
	_check(hud.page == "station" and not guide._bubble.visible, "原料台可以直接打开，面板不被遮住")
	await _click(hud.page_node("station").material_buttons.flour)
	_check(owner.boxes.flour and guide.seen.has("box_flour"), "原料买好即结束提示")
	for step in PANCAKE.guide:
		if step.id != "shop_done": guide.seen[step.id] = true
	guide.active = ""
	owner.clock = 1122.0
	owner.completed_at = 1122.0
	owner.revenue = 3260
	owner.stage_index = PANCAKE.stages.size() - 1
	for id in ["fryer", "topping", "bag"]: owner.unlocked[id] = true
	for material in owner.boxes: owner.boxes[material] = true
	owner.sold_by_dish = {"soy": 75, "plain": 42, "guozi": 31, "floss": 18, "family": 13}
	owner.levels["soy_milk"] = 6
	owner.levels["rear_equipment"] = 7
	owner.levels["topping"] = 6
	hud.open_page("shop")
	guide.refresh(0)
	var card: Dictionary = hud.popups.current()
	_check(owner.shop_complete() and card.get("id") == "guide:shop_done" and card.get("portrait_right"),
		"正式首店完店卡从右侧展示店长")
	_check(card.get("stats", []) == [["clock", "完店用时", "18 分 42 秒"], ["coin", "总营业额", "3260 金币"]],
		"完店数据来自经营记录")
	await _capture("calico-completed", 0.0)
	await _click(hud.popups.button(0))
	_check(guide.seen.has("shop_done") and not hud.popups.has_card(), "接着营业关闭完店卡")
	view.free()


func _pancake_roll_hint() -> void:
	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	var owner := ShopRules.new(PANCAKE, 42)
	owner.unlock("soy_milk")
	view.session = TestSession.make(PANCAKE, save_path + "-pancake", owner)
	await _reopen(view)
	hud = view.ui
	guide = view.guide
	var original_view: ShopView = view.view
	view.view = RollBottleneck.new(owner)
	guide.enabled = true
	for step in PANCAKE.guide:
		if step.id != "lost_machine": guide.seen[step.id] = true
	guide._start("lost_machine")
	guide.refresh(0)
	await process_frame
	_check(not view.anchors.rect("Stations/roll/Tap").has_area(), "卷饼没有可点的区域")
	_check(not view.frozen() and guide._point == Vector2.INF, "没有目标时不暂停，也不画指向屏幕中央的箭头")
	_check(guide._bubble.visible and not guide._bubble_text.text.contains("点它升级"), "没有升级入口时显示一般经营提示")
	var clock := owner.clock
	view._process(0.25)
	_check(owner.clock > clock, "提示还在时店铺继续经营")
	await _touch(guide._bubble_skip.get_global_transform_with_canvas() * (guide._bubble_skip.size / 2.0), true)
	_check(guide.seen.has("lost_machine") and not guide.visible and not view.frozen(), "只有原生触屏事件也能关闭「知道了」")
	view.free()
	original_view = null

func _pancake_skip_tutorial(from_opening: bool) -> void:
	var path := save_path + "-skip-" + str(from_opening)
	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	var owner := ShopRules.new(PANCAKE, 42)
	view.session = TestSession.make(PANCAKE, path, owner)
	view.session.guide_enabled = true
	await _reopen(view)
	hud = view.ui
	guide = view.guide
	if from_opening: await _click(hud.popups.button(hud.popups.primary_index()))
	# Wait for containers to lay out the wrapped text and position the buttons.
	for frame in 4: await process_frame
	var skip: Button = guide._bubble_skip if from_opening else hud.popups.button(0)
	await _touch(skip.get_global_transform_with_canvas() * (skip.size / 2.0), from_opening)
	_check(guide.seen.has("welcome") and guide.seen.has("opening") and not guide.freezes(), "触屏跳过后关闭开场引导")
	_check(not owner.is_open(), "跳过不替玩家购买设备")
	owner.gold = 1000
	owner.unlock("soy_milk")
	owner.unlock("rear_equipment")
	guide.refresh(0)
	_check(guide.active.is_empty() and guide.seen.has("box_flour") and guide.seen.has("lost_machine"), "跳过后招人、原料箱和客人等急教程不再弹")
	_check(not guide.seen.has("shop_done"), "仍可显示完店总结")
	_check(view.save_now(false) == OK, "跳过教程写入存档")
	view.free()
	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	view.session = TestSession.make(PANCAKE, path)
	view.session.guide_enabled = true
	await _reopen(view)
	_check(view.guide.seen.has("box_flour") and view.guide.active.is_empty(), "读档后仍然跳过教程")
	view.free()


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
func _touch(point: Vector2, refresh_while_pressed := false) -> void:
	var emulate := Input.is_emulating_mouse_from_touch()
	Input.emulate_mouse_from_touch = false
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
		if pressed and refresh_while_pressed: guide.refresh(0.016)
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


func _capture(suffix: String, advance := 0.4) -> void:
	if DisplayServer.get_name() == "headless": return
	guide.refresh(advance)
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
