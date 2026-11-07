extends SceneTree
## 排查用：旧模拟和 ShopRules 按同一串机器人操作逐帧对比，打印前 3 处分歧（金币、销量、来客、排队、员工位置）。
##   godot --headless --path . -s tests/baselines/diff_old_sim.gd
## 只剩奶茶店（煎饼摊旧模拟第 4 个 PR 删了）；奶茶店旧模拟删除时（第 5 个 PR）一起删。
const TeaSim := preload("res://game/tea_playtest/tea_shop_sim.gd")
const Replay := preload("res://tests/baselines/replay_rules.gd")

func _initialize() -> void:
	var which := "tea"
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/baselines/%s_73b0ae3.json" % which))
	var rules := ShopRules.new(load("res://content/shops/%s/shop.tres" % which))
	var old = TeaSim.new()
	var actions: Array = base.actions
	var next_action := 0
	var reported := 0
	for tick in int(base.minutes * 600):
		if which == "tea": old.advance(0.1)
		else: old.step(0.1)
		rules.step(0.1)
		var clock: float = rules.clock
		var a := _state_old(old, which)
		var b := _state_new(rules)
		if str(a) != str(b):
			print("t=%.1f\n 旧 %s\n 新 %s" % [clock, a, b])
			print(_detail_old(old, which), "\n", _detail_new(rules))
			reported += 1
			if reported >= 3: break
		while next_action < actions.size() and float(actions[next_action][0]) <= clock + 0.0001:
			var command: String = actions[next_action][1]
			_old_command(old, which, command)
			Replay.run_command(rules, command)
			next_action += 1
	quit()

func _state_old(o, which: String) -> Dictionary:
	if which == "tea":
		var ws := []
		for w in o.workers: ws.append([w.id, Vector2(w.pos).snappedf(1.0), w.job.get("count", 0)])
		return {"gold": snappedf(o.gold, 0.1), "sold": o.sold, "n": o._next_order, "q": o.orders.size(), "w": ws}
	var ss := []
	for s in o.staff: ss.append([s.id, Vector2(s.pos).snappedf(1.0), s.phase, s.task_label])
	return {"gold": snappedf(o.gold, 0.1), "sold": o.total_sold(), "n": o._next_customer_id, "q": o.queue.size(), "w": ss}

func _state_new(r: ShopRules) -> Dictionary:
	if r.shop.fulfillment.handoff != "single":
		var ws := []
		for w in r.workers: ws.append([w.id, Vector2(w.pos).snappedf(1.0), w.job.get("count", 0)])
		return {"gold": snappedf(r.gold, 0.1), "sold": r.sold, "n": r._next_order, "q": r.orders.size(), "w": ws}
	var ss := []
	for s in r.workers: ss.append([s.id, Vector2(s.pos).snappedf(1.0), s.phase, s.task_label])
	return {"gold": snappedf(r.gold, 0.1), "sold": r.total_sold(), "n": r._next_customer_id, "q": r.queue.size(), "w": ss}

func _old_command(sim, which: String, command: String) -> void:
	var parts := command.split(" ")
	if which == "pancake":
		match parts[0]:
			"unlock": sim.unlock(parts[1])
			"hire": sim.hire()
			"upgrade": sim.upgrade(parts[1])
			"flyer": sim.send_flyers()
		return
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

func _detail_old(o, which: String) -> String:
	if which != "tea": return ""
	var t := []
	for w in o.workers: t.append([w.id, w.job, w.ticket])
	return "旧 stations %s\n 旧 jobs %s\n 旧 shelf %s" % [o.stations, t, o.shelf_stock]

func _detail_new(r: ShopRules) -> String:
	if r.shop.fulfillment.handoff == "single": return ""
	var t := []
	for w in r.workers: t.append([w.id, w.job, w.ticket])
	return "新 stations %s\n 新 jobs %s\n 新 shelf %s" % [r.stations, t, r.shelf_stock]
