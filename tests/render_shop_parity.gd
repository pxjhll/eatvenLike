extends SceneTree
## 新旧奶茶店界面逐字对照（“重构只换结构，不换手感”）：旧场景跑旧模拟，新场景跑规则层，按同一份基准操作
## 一起往前走；每隔一段时间把两边的每一个面板页打开，面板里看得见的字、按钮上的字、目标栏、金币都要一样。
## 旧场景删除时（第 5 个 PR）这个对照改成存下来的文字基准。

const TeaSim := preload("res://game/tea_playtest/tea_shop_sim.gd")
const Replay := preload("res://tests/baselines/replay_rules.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const CHECK_EVERY := 90.0
var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()


func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(720, 1280)
	var old: Node2D = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	old.sim = TeaSim.new()
	root.add_child(old)
	var new: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	new.rules = ShopRules.new(TEA)
	root.add_child(new)
	await process_frame
	old.set_process(false)
	new.set_process(false)
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/baselines/tea_73b0ae3.json"))
	var actions: Array = base.actions
	var next := 0
	var t := 0.0
	var next_check := 30.0
	var reported := 0
	while t < float(base.minutes) * 60.0 and reported < 12:
		old.sim.advance(0.1)
		new.rules.step(0.1)
		t += 0.1
		while next < actions.size() and float(actions[next][0]) <= new.rules.clock + 0.0001:
			_old_command(old.sim, actions[next][1])
			Replay.run_command(new.rules, actions[next][1])
			next += 1
		if t < next_check: continue
		next_check += CHECK_EVERY
		var pages: Array = ["goals", "staff"]
		for st in TEA.stations: pages.append("station:" + st.id)
		for page in pages:
			_open(old, page)
			_open(new, page)
			await process_frame
			old._refresh(0.0)
			new._refresh(0.0)
			await process_frame
			var a := _texts(old)
			var b := _texts(new)
			checks += 1
			if a != b:
				failures += 1
				reported += 1
				print("FAIL %d 秒 %s\n  旧 %s\n  新 %s" % [int(t), page, a, b])
		_open(old, "shop")
		_open(new, "shop")
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("SHOP UI PARITY: %d pages compared, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _open(scene: Node2D, page: String) -> void:
	if page.begins_with("station:"): scene.ui.open_station(page.substr(8))
	else: scene.ui.open_page(page)


## 看得见的字：顶栏金币和目标、面板标题、面板里每个 Label 和 Button（按树的顺序）
func _texts(scene: Node2D) -> Array:
	var hud: Control = scene.ui
	var out: Array = [hud.get_node("%Gold").text, hud.get_node("%GoalText").text]
	_collect(hud.get_node("%Sheet"), out)
	return out


func _collect(node: Node, out: Array) -> void:
	if node is CanvasItem and not node.visible: return
	if node is Label and not String(node.text).is_empty(): out.append(node.text)
	elif node is Button and not String(node.text).is_empty(): out.append("[%s%s]" % [node.text, " ×" if node.disabled else ""])
	for child in node.get_children(): _collect(child, out)


func _old_command(sim, command: String) -> void:
	var parts := command.split(" ")
	match parts[0]:
		"unlock": sim.unlock_station(parts[1])
		"box": sim.unlock_box(parts[1])
		"hire": sim.hire()
		"deploy": sim.deploy_worker(int(parts[1]))
		"upgrade": sim.upgrade_station(parts[1])
		"material": sim.upgrade_material(parts[1], parts[2])
		"staff": sim.buy_staff_upgrade(parts[1])
		"seat": sim.buy_seat()
		"flyer_upgrade": sim.upgrade_flyers()
		"flyer": sim.buy_flyers()
