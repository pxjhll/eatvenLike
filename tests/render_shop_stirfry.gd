extends SceneTree
## 小炒饭馆（订单明细店 serve）在正式界面里跑：客人排队 → （自取店）走到出餐口等 → 去座位坐下吃 → 离店；
## 后厨做好的、出餐口上的、桌上的菜都画出来。送桌和自取两种入座规则各跑一遍，全程不能有运行时报错。

const TestSession := preload("res://tests/shop_test_session.gd")
const STIRFRY: SpecShop = preload("res://content/shops/stirfry/shop.tres")
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
	scene.session = TestSession.make(spec, prefix, null, null, null, CAMPAIGN)
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
	var pickup_id := ServeFlow.pickup_of(spec)
	var window: Vector2 = spec.layout.points[pickup_id]
	var seen := {}
	var every_guest_drawn := true
	var dishes_drawn := false
	for unused in 2400:
		scene._process(0.25)
		for g: Dictionary in scene.rules.serve.guests:
			var id := int(g.id)
			if not scene._customers.has(id):
				every_guest_drawn = false
				continue
			var pos: Vector2 = scene._customer_positions[id]
			var seat: Vector2 = scene.anchors.point("Seats/" + ServeFlow.seat_point(spec, int(g.seat))) if int(g.seat) >= 0 else Vector2.INF
			if g.state == "await" and pos.distance_to(window) < 260.0: seen.await_at_window = true
			if g.state == "eating" and float(g.eat_left) < scene.rules.seat_seconds() - 15.0 and pos.distance_to(seat) <= 2.0: seen.eating_at_seat = true
			if g.state == "queue": seen.queue = true
		var visible_cups := scene._cups.filter(func(c: Sprite2D) -> bool: return c.visible).size()
		for good: Dictionary in scene.rules.serve.goods:
			if String(good.at).begins_with(ServeFlow.SEAT) and visible_cups > 0: dishes_drawn = true
		if seen.has("eating_at_seat") and dishes_drawn and (rule != "self_pickup" or seen.has("await_at_window")) and scene.rules.sold >= 3: break
	_check(every_guest_drawn, rule + ": 规则层里每位客人都有人物")
	_check(seen.has("queue"), rule + ": 有客人排队")
	_check(seen.has("eating_at_seat"), rule + ": 用餐的客人坐在分到的座位上")
	_check(dishes_drawn, rule + ": 桌上的菜画出来了")
	if rule == "self_pickup": _check(seen.has("await_at_window"), rule + ": 自取的客人站在出餐口前等")
	_check(scene.rules.sold >= 3, rule + ": 正式界面里卖出了 %d 份" % scene.rules.sold)
	_check(scene.save_now(false) == OK, rule + ": 能存档")
	scene.free()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
