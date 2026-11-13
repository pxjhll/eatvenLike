extends SceneTree
## 小炒饭馆（订单明细店 serve）在正式界面里跑：客人排队 → （自取店）走到出餐口等 → 去座位坐下吃 → 离店；
## 后厨做好的、出餐口上的、桌上的菜都画出来。送桌和自取两种入座规则各跑一遍，全程不能有运行时报错。

const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
## Frozen alternate-mode scene regression. Formal entry: render_template_official_session.
const TestSession := preload("res://tests/shop_test_session.gd")
const STIRFRY: SpecShop = preload("res://tests/fixtures/legacy_shops/current/stirfry/shop.tres")
const CAMPAIGN: SpecCampaign = preload("res://tests/fixtures/stirfry/campaign.tres")
const ServeFlow := preload("res://game/rules/serve_flow.gd")
var errors := preload("res://tests/error_counter.gd").new()
var failures := 0
var checks := 0
var paths: Array[String] = []


func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(720, 1280)
	root.get_node("ShopAudio")._can_play = false
	for rule in ["seat_wait", "self_pickup"]: await _business(rule)
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for error in errors.take():
		failures += 1
		print("RUNTIME: " + error)
	OS.remove_logger(errors)
	print("SHOP STIRFRY GUI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _business(rule: String) -> void:
	var spec: SpecShop = STIRFRY.duplicate(true)
	spec.fulfillment.dine_rule = rule
	var prefix := "user://stirfry-gui-%d-%d-%s" % [OS.get_process_id(), Time.get_ticks_usec(), rule]
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(spec, prefix, LegacyRules.new(spec,42), null, null, CAMPAIGN)
	for path in [scene.session.profile.path, scene.session.store.path, scene.session.tuning_path, scene.session.recording_path]:
		if not path in paths: paths.append(path)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	_check(scene.rules != null, rule + ": 小炒饭馆从正式入口开店：" + str(scene.save_status))
	if scene.rules == null:
		scene.free()
		return
	_check(scene.art != null, rule + ": 美术场景装上了")
	scene.rules.unlock("wok_a")
	scene._process(0.25)
	# 双灶：灶台和左锅开张就有，右锅（炒锅B）买了才摆上
	var stove: Node2D = scene.art.get_node("Sortables/Wok")
	_check(stove.get_node("Visual/Stove").is_visible_in_tree() and stove.get_node("Visual/WokLeft").is_visible_in_tree(), rule + ": 开张后灶台和炒锅A 都在")
	_check(not stove.get_node("Visual/Slots/right/WokRight").is_visible_in_tree(), rule + ": 没买炒锅B 时右边没锅")
	# 桌椅跟着买到的座位数摆：开局 6 座 = 前 3 张桌；买一座多出第 4 张桌的左椅
	var dining: Node2D = scene.art.get_node("Sortables/Dining")
	var start_seats: int = scene.rules.seat_total()
	var shown := func(k: int) -> bool: return (dining.get_node("Table%02d" % k) as CanvasItem).is_visible_in_tree()
	_check(shown.call(1) and shown.call(ceili(start_seats / 2.0)) and not shown.call(ceili(start_seats / 2.0) + 1), rule + ": 开局只摆出 %d 座对应的桌子" % start_seats)
	scene.rules.gold = 100000.0
	_check(scene.rules.buy_seat().is_empty(), rule + ": 买一个座位")
	scene._process(0.25)
	var next_table := dining.get_node("Table%02d" % (start_seats / 2 + 1))
	_check(next_table.is_visible_in_tree(), rule + ": 买座位后多摆一张桌")
	_check(not (next_table.get_node("Visual/Seats/1") as CanvasItem).visible or scene.rules.seat_total() % 2 == 0, rule + ": 单数座位只摆一把椅子")
	scene.rules.gold = 0.0
	var pickup_id := ServeFlow.pickup_of(spec)
	var window: Vector2 = spec.layout.points[pickup_id]
	var seen := {}
	var every_guest_drawn := true
	var dishes_drawn := false
	var correct_food_art := true
	var saw_order_art := false
	var saw_carried_art := false
	for unused in 2400:
		scene._process(0.25)
		for actor: Node2D in scene._customers.values():
			if actor._order_cup.visible:
				saw_order_art = true
				correct_food_art = correct_food_art and actor._order_cup.texture.resource_path.begins_with("res://art/stirfry/items/")
		for actor: Node2D in scene._actors.values():
			if actor.carried.visible:
				saw_carried_art = true
				var path: String = actor.carried.texture.resource_path
				correct_food_art = correct_food_art and (path.begins_with("res://art/stirfry/items/") or path=="res://art/stirfry/scene/chopped_scallion_bowl.png")
		for sprite: Sprite2D in scene._cups:
			if sprite.visible:
				var path := sprite.texture.resource_path
				correct_food_art = correct_food_art and (path.begins_with("res://art/stirfry/items/") or path=="res://art/stirfry/scene/chopped_scallion_bowl.png")
		for g: Dictionary in scene.rules.serve.guests:
			var id := int(g.id)
			var key: Variant = "guest:%d"%id if spec.layout.motion_version==1 else id
			if not scene._customers.has(key):
				every_guest_drawn = false
				continue
			var pos: Vector2 = scene._customers[key].position
			var seat: Vector2 = scene.anchors.point("Seats/" + ServeFlow.seat_point(spec, int(g.seat))) if int(g.seat) >= 0 else Vector2.INF
			if g.state == "await" and pos.distance_to(window) < 260.0: seen.await_at_window = true
			if g.state == "eating" and float(g.eat_left) < scene.rules.seat_seconds() - 15.0 and pos.distance_to(seat) <= 2.0: seen.eating_at_seat = true
			if g.state == "queue": seen.queue = true
		for good: Dictionary in scene.rules.serve.goods:
			if not String(good.at).begins_with(ServeFlow.SEAT): continue
			var seat_no := int(String(good.at).substr(ServeFlow.SEAT.length()))
			var table: Vector2 = scene.anchors.point("Tables/table/%d" % (seat_no / 2))
			for cup: Sprite2D in scene._cups:
				# 精灵的落脚点排在桌子前面，画出来的位置要回到桌面上
				if cup.visible and absf(cup.position.x - table.x) <= 50.0 and cup.position.y >= table.y: dishes_drawn = true
		if seen.has("eating_at_seat") and dishes_drawn and (rule != "self_pickup" or seen.has("await_at_window")) and scene.rules.sold >= 3: break
	_check(every_guest_drawn, rule + ": 规则层里每位客人都有人物")
	_check(seen.has("queue"), rule + ": 有客人排队")
	_check(seen.has("eating_at_seat"), rule + ": 用餐的客人坐在分到的座位上")
	_check(dishes_drawn, rule + ": 桌上的菜摆在桌面上")
	_check(saw_order_art and saw_carried_art, rule + ": 实际订单和搬运均出现餐品贴图")
	_check(correct_food_art, rule + ": 订单、搬运、工位和桌面均使用小炒资源，不混入奶茶图")
	if rule == "self_pickup": _check(seen.has("await_at_window"), rule + ": 自取的客人站在出餐口前等")
	_check(scene.rules.sold >= 3, rule + ": 正式界面里卖出了 %d 份" % scene.rules.sold)
	scene.rules.gold = 100000.0
	for unused in 4:
		if scene.rules.next_unlock() == "wok_b": break
		scene.rules.unlock(scene.rules.next_unlock())
	_check(scene.rules.unlock("wok_b").is_empty(), rule + ": 买炒锅B")
	scene._process(0.25)
	_check(stove.get_node("Visual/Slots/right/WokRight").is_visible_in_tree(), rule + ": 买了炒锅B 右锅摆上")
	_check(scene.save_now(false) == OK, rule + ": 能存档")
	scene.free()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
