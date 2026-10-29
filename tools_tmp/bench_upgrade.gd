extends SceneTree
const USim = preload("res://tools_tmp/upgrade_sim.gd")
const CFG = preload("res://content/tea/tea.tres")
const HAUL := ["load_boil", "unload_boil", "transfer_to_topping", "carry_to_seal", "load_seal_belt", "carry_to_shelf", "load_shelf_belt"]
const MANUAL := ["brew_start", "brew_take", "topping"]

var originals := {}

func station_def(id: String):
	for slot in CFG.slots:
		if slot.station.id == id: return slot.station
	for spot in CFG.front_spots:
		if spot.station.id == id: return spot.station

func snapshot() -> void:
	for id in ["cabinet", "brewer", "milk_station", "topping", "lemonade_stand"]:
		var d = station_def(id)
		originals[id] = [d.level_speed.duplicate(), d.upgrade_costs.duplicate()]
		for m in d.materials: originals[id + ":" + m.id] = [m.level_bonus.duplicate(), m.upgrade_costs.duplicate()]

func restore() -> void:
	for id in ["cabinet", "brewer", "milk_station", "topping", "lemonade_stand"]:
		var d = station_def(id)
		d.level_speed = originals[id][0].duplicate(); d.upgrade_costs = originals[id][1].duplicate()
		for m in d.materials:
			m.level_bonus = originals[id + ":" + m.id][0].duplicate(); m.upgrade_costs = originals[id + ":" + m.id][1].duplicate()

func set_station(id: String, costs: Array, keep_speed: bool) -> void:
	var d = station_def(id)
	var c: Array[int] = []
	for x in costs: c.append(int(x))
	d.upgrade_costs = c
	var s: Array[float] = []
	for i in costs.size() + 1: s.append(d.level_speed[mini(i, d.level_speed.size() - 1)] if keep_speed else 1.0)
	d.level_speed = s

func set_material(id: String, mat: String, costs: Array) -> void:
	var m = station_def(id).material(mat)
	var c: Array[int] = []
	for x in costs: c.append(int(x))
	m.upgrade_costs = c
	var b: Array[float] = []
	for i in costs.size() + 1: b.append(1.0)
	m.level_bonus = b

func geo(first: float, ratio: float, n: int) -> Array:
	var out := []
	for i in n: out.append(int(round(first * pow(ratio, i) / 5.0) * 5))
	return out

func options(sim) -> Array:
	var out := []
	for id in ["lemonade", "boil", "mix", "topping", "supply"]:
		var info = sim.station_info(id)
		if not info.unlocked: continue
		if info.upgrade_cost > 0 and info.upgrade_error in ["", "金币不足，需要 %d" % info.upgrade_cost]:
			out.append({"kind": "st", "id": id, "m": "", "cost": info.upgrade_cost})
		for m in info.materials:
			if m.upgrade_cost > 0 and (m.upgrade_error == "" or m.upgrade_error.begins_with("金币不足")):
				out.append({"kind": "mat", "id": id, "m": m.id, "cost": m.upgrade_cost})
	for w in sim.workers:
		if w.level < 4: out.append({"kind": "train", "id": str(w.id), "m": "", "cost": sim.train_cost(w.id)})
	return out

func run(label: String, limit: float, buy: bool) -> void:
	var sim = USim.new()
	var t := 0.0
	var log := []
	var labor := {}
	var windows := []
	var last_rev := 0
	var buys := 0
	var last_buy := 0.0
	var max_gap := 0.0
	var gap_at := 0
	var sold_out := -1
	var stage_t := {}
	var spend := 0
	while t < limit:
		if not sim.station_unlocked("lemonade"): sim.unlock_station("lemonade")
		var pending := false
		if sim.stage_index < 3:
			var nxt = USim.PROGRESSION.stages[sim.stage_index + 1]
			var key: String = ["boil", "mix", "topping"][sim.stage_index]
			if sim.unlock_station(key) == "": stage_t[sim.stage_index] = int(t)
			elif sim.revenue >= nxt.revenue_threshold: pending = true
		if not pending and sim.stage_index >= 1 and sim.hire_cost() > 0:
			if sim.hire():
				for w in sim.all_workers():
					if not w.deployed: sim.deploy_worker(w.id)
				log.append("%ds 招人(%d人)" % [t, sim.workers.size()])
				last_buy = t
		if buy and not pending and sim.hire_cost() < 0:
			var opts := options(sim)
			if opts.is_empty() and sim.stage_index == 3 and sold_out < 0: sold_out = int(t)
			opts.sort_custom(func(a, b): return a.cost < b.cost)
			if not opts.is_empty() and sim.gold >= opts[0].cost:
				var o = opts[0]
				var ok := false
				if o.kind == "st": ok = sim.upgrade_station(o.id) == ""
				elif o.kind == "mat": ok = sim.upgrade_material(o.id, o.m) == ""
				else: ok = sim.train(int(o.id))
				if ok:
					buys += 1; spend += o.cost
					if t - last_buy > max_gap and t > 60: max_gap = t - last_buy; gap_at = int(t)
					last_buy = t
		for i in 10:
			sim.advance(0.1)
			if t >= limit - 300:
				for w in sim.workers:
					var k := "idle"
					if w.phase != "idle":
						var kind: String = w.job.get("kind", "")
						k = "serve" if kind == "serve" else ("haul" if kind in HAUL else ("manual" if kind in MANUAL else kind))
					labor[k] = labor.get(k, 0.0) + 0.1
		t += 1.0
		if int(t) % 120 == 0:
			windows.append("%.1f" % ((sim.revenue - last_rev) / 120.0)); last_rev = sim.revenue
	var lost: int = sim._next_order - 1 - sim.sold - sim.orders.size()
	var tot := 0.0
	for k in labor: tot += labor[k]
	var lp := []
	for k in ["haul", "serve", "manual", "idle"]: lp.append("%s %d%%" % [k, int(labor.get(k, 0.0) * 100 / maxf(1, tot))])
	var prices := []
	for d in ["lemonade", "black_tea", "plain_milk_tea", "pearl_milk_tea", "taro_milk_tea"]: prices.append("%d" % sim._dish_price(d))
	print("== ", label)
	print("  阶段解锁(红茶/调奶/加料)秒 ", stage_t.values(), "  ", " ".join(log))
	print("  每120秒金/秒 ", " ".join(windows))
	print("  营业额 %d  售出 %d  流失 %d  均价 %.1f  升级+培养 %d 次 花 %d  买空 %s  最长等待 %ds(于%ds)" % [sim.revenue, sim.sold, lost, float(sim.revenue) / maxf(1, sim.sold), buys, spend, str(sold_out), int(max_gap), gap_at])
	print("  末价 柠/红/原/珍/芋 ", "/".join(prices), "  末300秒人工 ", ", ".join(lp))
	print("  等级 ", sim.station_levels, " ", sim.material_levels, " 员工Lv ", sim.workers.map(func(w): return w.level))

func setup_a2(pct: float) -> void:
	USim.V = {"price": true, "pct": {"lemonade": pct, "boil": pct, "mix": pct, "tea_leaf": pct, "milk": pct}}
	set_station("lemonade_stand", geo(20, 1.4, 9), false)
	set_station("brewer", geo(60, 1.35, 9), false)
	set_station("milk_station", geo(80, 1.35, 9), false)
	set_station("cabinet", [], false)
	set_material("cabinet", "tea_leaf", geo(50, 1.5, 4))
	set_material("cabinet", "milk", geo(60, 1.5, 4))

func _init() -> void:
	snapshot()
	var L := 1800.0
	for pct in [0.06, 0.08]:
		setup_a2(pct)
		run("A2 加价型 10级 每级+%d%%" % int(pct * 100), L, true)
	setup_a2(0.06)
	USim.V.batch = [5, 10]
	run("A2+B 6%% + 煮茶锅Lv5/Lv10 批量+1", L, true)
	restore()
	quit()
