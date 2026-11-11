extends SceneTree
## 小炒饭馆节奏机器人（临时，不进 main）：每分钟看一眼，先买下一阶段，再招人，再买座位/最便宜的升级（为下一阶段攒钱时只买 ≤25% 的）。
const SEEDS := [0, 1, 2, 3, 4, 5, 6, 7]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var modes: Array = args[0].split(",") if args.size() > 0 else ["save", "spend"]
	for m in modes:
		var rows := []
		for seed in SEEDS: rows.append(run(make_shop(m), seed, m))
		summarize(m, rows)
	quit()

func make_shop(m: String) -> SpecShop:
	var s: SpecShop = load("res://content/shops/stirfry/shop.tres").duplicate(true)
	for part in m.split("+"):
		match part:
			"more", "more6": # 后厨位 2/3/4/4/5/5，多招两人
				var slots := [2, 3, 4, 4, 5, 5]
				for i in s.stages.size(): s.stages[i].staff_slots["kitchen"] = slots[i]
				for k in ["fox", "dog"]:
					var kind: SpecStaffKind = s.staff.kinds[0].duplicate(true)
					kind.id = k
					s.staff.kinds.append(kind)
					s.staff.hire_pool.append(k)
				s.staff.hire_costs.assign([60, 120, 200, 300])
				if part == "more6":
					s.staff.hire_costs.assign([60, 120, 160, 220])
			"walk2": for k in s.staff.kinds: k.stats["walk"] = 360.0
			"carry2": for k in s.staff.kinds: k.stats["carry"] = 2.0
			"work15": for k in s.staff.kinds: k.stats["work"] = 1.5
			"t20": for st in s.stages: for t in st.tasks: if t.amount == 30: t.amount = 20
			"t15": for st in s.stages: for t in st.tasks: if t.amount >= 25 and t.target != "soup": t.amount = 15 if t.amount == 30 else 20
	return s

func run(shop: SpecShop, seed: int, mode: String) -> Dictionary:
	var rules := ShopRules.new(shop, seed)
	var next_visit := 1.0
	var out := {"done": -1.0, "stages": [], "tasks": {}, "hires": [], "seats": 0, "lost": 0, "revenue": 0.0, "buys": 0, "idle": 0.0, "peak_queue": 0, "load": {}, "late": 0.0}
	var last_stage := -1
	while rules.clock < 70 * 60.0:
		rules.step(ShopRules.STEP)
		if rules.stage_index >= 4:
			for key in rules.serve.jobs:
				var j: Dictionary = rules.serve.jobs[key]
				var tag := "%s:%s" % [j.kind, j.to] if j.kind != "home" else "idle"
				out.load[tag] = float(out.load.get(tag, 0.0)) + ShopRules.STEP
			out.late += ShopRules.STEP
		if rules.is_open() and rules.stage_index != last_stage:
			last_stage = rules.stage_index
			out.stages.append(rules.clock)
		for row in rules.task_rows():
			if row.complete and not out.tasks.has(row.id): out.tasks[row.id] = rules.clock
		if rules.shop_complete():
			out.done = rules.clock
			break
		if rules.clock + 0.0001 < next_visit: continue
		next_visit += 60.0
		out.peak_queue = maxi(out.peak_queue, rules.queue_size())
		if rules.queue_size() <= 1: rules.send_flyers()
		for _i in 8:
			var nxt := rules.next_unlock()
			if not nxt.is_empty() and rules.unlock(nxt) == "":
				out.buys += 1
				continue
			if rules.hire_error() == "" and rules.hire() == "":
				var post := ""
				if mode.contains("seat"): post = "wok_a" if out.hires.is_empty() else "wok_b"
				var derr := rules.deploy_worker(rules.roster[-1].id, post)
				if derr != "": print("deploy ", post, " ", derr)
				out.hires.append(rules.clock)
				continue
			var opts := []
			if rules.seat_error() == "": opts.append([rules.seat_cost(), "#seat"])
			for st in shop.stations:
				if st.tracks.is_empty() or not rules.station_unlocked(st.id): continue
				if rules.upgrade_error(st.id) == "": opts.append([rules.upgrade_cost(st.id), st.id])
			if opts.is_empty(): break
			opts.sort()
			var pick: Array = opts[0]
			var target: int = rules.next_stage_cost() if not nxt.is_empty() else 0
			if mode.begins_with("save") and not nxt.is_empty() and pick[0] > 0.25 * target: break
			var err: String = rules.buy_seat() if pick[1] == "#seat" else rules.upgrade(pick[1])
			if err != "": break
			out.buys += 1
			if pick[1] == "#seat": out.seats += 1
	out.lost = rules.lost
	out.revenue = rules.revenue
	out.served = int(rules.serve.get("served", 0)) if rules.serve is Dictionary else 0
	out.gold = rules.gold
	var left := []
	for st in shop.stations:
		if st.tracks.is_empty(): continue
		if rules.upgrade_cost(st.id) >= 0: left.append("%s Lv%d" % [st.id, rules.level(st.id)])
	if rules.seat_cost() >= 0: left.append("座位没买完")
	out.left = left
	return out

func summarize(name: String, rows: Array) -> void:
	print("== ", name)
	for r in rows:
		var st := ", ".join(r.stages.map(func(t): return "%.1f" % (t / 60.0)))
		var tk := []
		for k in r.tasks: tk.append("%s %.1f" % [k, r.tasks[k] / 60.0])
		print("完店 %5.1f | 阶段 %s | 任务 %s | 招人 %s | 座位+%d | 买 %d | 流失 %d 服务 %d | 营业额 %.0f 余 %.0f | 队列峰 %d | 未满级 %s" % [
			r.done / 60.0, st, ", ".join(tk), ", ".join(r.hires.map(func(t): return "%.1f" % (t / 60.0))), r.seats, r.buys, r.lost, r.served, r.revenue, r.gold, r.peak_queue, r.left])
	var agg := {}
	var late := 0.0
	for r in rows:
		late += r.late
		for k in r.load: agg[k] = float(agg.get(k, 0.0)) + r.load[k]
	var keys := agg.keys()
	keys.sort_custom(func(a, b): return agg[a] > agg[b])
	print("宫保阶段起人手占用（人·秒/秒）：", ", ".join(keys.map(func(k): return "%s %.2f" % [k, agg[k] / maxf(1.0, late)])))
	var done := rows.map(func(r): return r.done / 60.0)
	var m := 0.0
	for x in done: m += x
	print("平均完店 %.1f 分（%.1f–%.1f）" % [m / done.size(), done.min(), done.max()])
