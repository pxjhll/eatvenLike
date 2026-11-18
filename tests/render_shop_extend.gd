extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const LegacySave := preload("res://tests/fixtures/legacy_shops/reference_save.gd")

const TestSession := preload("res://tests/shop_test_session.gd")
## 扩展验收（规格 §6.2.1）：不改 HUD 核心，从外面加一个页签和它的页面、弹一张奇遇卡、显示一个进行中加成的图标，
## 都要能看见、能点；另外新场景能整局跑下去不报错（读档、存档、重开都走一遍）。

const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/current/tea/shop.tres")
const CURRENT_TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
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
	view.session = TestSession.make(TEA, save_path, LegacyRules.new(TEA), LegacySave.new(TEA, save_path))
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
	reopened.session = TestSession.make(TEA, save_path, null, LegacySave.new(TEA, save_path))
	root.add_child(reopened)
	# _ready 开启自动推进；先停住再等界面帧，比较存档瞬间的状态。
	reopened.set_process(false)
	await process_frame
	_check(is_equal_approx(reopened.rules.clock, rules.clock) and reopened.rules.sold == rules.sold, "读档回到同一时刻")
	for unused in 40: reopened._process(0.25)
	reopened.restart()
	_check(reopened.rules.sold == 0 and reopened.rules.clock == 0.0, "重开回到空店")
	reopened.free()
	view.free()
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(save_path)
	await _check_manager_visit()
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("SHOP EXTEND: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check_manager_visit() -> void:
	var path := save_path + "-manager"
	var old_shop: SpecShop = CURRENT_TEA.duplicate()
	old_shop.events = []
	var old_rules := ShopRules.new(old_shop, 42)
	_check(old_rules.unlock("lemonade").is_empty(), "旧奶茶档按正常方式开张")
	for unused in 960:
		if old_rules.sold >= 7: break
		old_rules.step(0.25)
	_check(old_rules.sold == 7, "旧奶茶档自然卖出七杯")
	_check(ShopSave.new(old_shop, path).save_game(old_rules, 1.0, ["opening"]) == OK, "写入未配置回访的旧档")

	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	view.session = TestSession.make(CURRENT_TEA, path, null, ShopSave.new(CURRENT_TEA, path))
	view.session.guide_enabled = true
	root.add_child(view)
	view.set_process(false)
	await process_frame
	var owner: ShopRules = view.rules
	_check(owner.sold == 7 and owner.pending_events.is_empty(), "内容更新保留旧档进度，七杯未触发")
	view.ui.open_page("goals")
	for unused in 240:
		if not owner.pending_events.is_empty(): break
		view._process(0.25)
	_check(owner.sold >= 8 and owner.pending_events.size() == 1 and not view.guide._bubble.visible,
		"八杯后回访排队，玩家看目标面板时不弹出")
	var gold := owner.gold
	var revenue := owner.revenue
	var sold := owner.sold
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = owner.event_rng.seed
	expected_rng.state = owner.event_rng.state
	var expected := expected_rng.randi_range(30, 50)
	_check(owner.gold == 50.0 - float(owner.shop.stages[0].cost) + revenue, "等待期间钱包只有营业收入")
	_check(view.save_now(false) == OK, "玩家可保存尚未结算的回访")
	view.free()

	view = load("res://presentation/shop/shop_play.tscn").instantiate()
	view.session = TestSession.make(CURRENT_TEA, path, null, ShopSave.new(CURRENT_TEA, path))
	root.add_child(view)
	view.set_process(false)
	await process_frame
	owner = view.rules
	var blocker := {"id": "test-modal", "title": "测试卡片", "buttons": [{"label": "关闭"}]}
	view.ui.popups.push(blocker)
	view._process(0.0)
	_check(owner.gold == gold and owner.pending_events.size() == 1, "有弹卡时继续等待")
	view.ui.popups.remove("test-modal")
	view._process(0.0)
	_check(owner.gold == gold + expected and owner.revenue == revenue and owner.sold == sold and owner.pending_events.is_empty(),
		"回到店面自动按存档随机状态发放三十至五十金币，只加钱包")
	_check(view.guide._bubble.visible and view.guide._dialogue_slot.visible and not view.frozen()
		and "+%d 金币" % expected in view.guide._bubble_text.text, "店长立绘和实际到账金额同时显示，营业继续")
	await process_frame
	view.guide.refresh(0.1)
	await process_frame
	var paper: StyleBoxFlat = view.guide._bubble.get_theme_stylebox("panel")
	_check(view.guide._dialogue_heading.visible and view.guide._dialogue_heading.text == "店长回访"
		and is_equal_approx(paper.bg_color.a, 189.0 / 255.0), "半透明回访通知保留店长标题")
	var portrait: TextureRect = view.guide._dialogue_portrait
	var label: Label = view.guide._bubble_text
	var portrait_rect := portrait.get_global_rect()
	var slot_rect: Rect2 = view.guide._dialogue_slot.get_global_rect()
	_check(portrait.is_visible_in_tree() and portrait.texture == CURRENT_TEA.events[0].notice_portrait
		and portrait_rect.end.x <= label.get_global_rect().position.x, "刷新后立绘仍在正文左侧")
	_check(slot_rect.encloses(portrait_rect) and portrait_rect.get_center().is_equal_approx(slot_rect.get_center())
		and portrait_rect.size.x > 146.0 and portrait_rect.size.y > 125.0, "放大的立绘在左栏居中，不超出提示框")
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	for line in label.text.split("\n"):
		_check(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x, "回访台词和金额在右侧可完整显示")
	_check(view.ui.get_node("%Gold").text == str(int(owner.gold)), "金币栏当帧更新")
	view.guide.refresh(4.0)
	view.guide.refresh(0.0)
	_check(not view.guide._bubble.visible, "回访短消息自动收起")

	var restored := ShopSave.new(CURRENT_TEA, path).load_game()
	_check(restored.gold == gold + expected and "tea_manager_visit" in restored.events_seen
		and restored.pending_events.is_empty(), "金币与一次性标记在同一份存档")
	var duplicate_award := restored.execute_command("resolve_event_notice", {"id": "tea_manager_visit"})
	_check(duplicate_award.code == "event_missing" and restored.gold == gold + expected, "读档后重复请求无法再领")
	view.free()
	DirAccess.remove_absolute(path)

	var late := ShopRules.new(CURRENT_TEA, 42)
	late.gold = 1000.0
	for id in ["lemonade", "boil", "seal"]: late.unlock(id)
	late.sold = 8
	late.run(3.0)
	_check(late.pending_events.is_empty() and late.events_seen.is_empty(), "已进入封口机阶段的档不补发早期回访")

	var gift: SpecEffect = CURRENT_TEA.events[0].effects[0]
	var customer_rng := late.rng.state
	var amounts := {}
	for seed in range(16):
		late.event_rng.seed = seed
		var before := late.gold
		late.apply_effect("event", "manager_gift_probe", gift)
		amounts[late.gold - before] = true
	_check(amounts.size() > 1 and amounts.keys().all(func(amount: float) -> bool: return amount >= 30.0 and amount <= 50.0),
		"多组奇遇种子抽到不同金币数，全部在三十至五十范围内")
	_check(late.rng.state == customer_rng, "随机奖励不消耗顾客和点单随机数")


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
