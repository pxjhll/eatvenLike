extends SceneTree
## 录旧模拟（main 73b0ae3）的基准结果，供第 2–4 个 PR 新规则层对照（规格 §7）：
##   godot --headless --path . -s tests/baselines/record_baselines.gd [-- --check]
## 同一机器人（每分钟看一次的玩家）、固定种子、同一套操作规则。写出 tests/baselines/<店>_73b0ae3.json：
##   unlocks   各次解锁 / 招人的时刻（秒）
##   checkpoints 第 5 / 10 / 20 / 30（/ 45）分钟的营业额、销量（分菜）、金币、员工数、阶段
##   completed_at 完店时刻（秒，-1 = 30 分钟内没完）
##   segments  每段（阶段）的分段指标：时长、进店、满队秒数、流失、员工 制作 / 走路 / 空闲 占比、出餐数、主要瓶颈
##   actions   机器人每一次操作（时刻 + 命令），新规则层照这串命令重放
## --check：重跑一遍，和已存的 json 不一致就退出码 1（旧模拟在删除前不允许被改动）。

const TeaSim := preload("res://game/tea_playtest/tea_shop_sim.gd")
## 奶茶店按 30 分钟设计，这个机器人比较保守，多跑到 45 分钟看完店时间
const MINUTES := {"tea": 45.0}
const CHECKPOINTS := [5, 10, 20, 30, 45]
const DIR := "res://tests/baselines/"


func _initialize() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	var failed := false
	# 煎饼摊旧模拟已删（第 4 个 PR）：pancake_73b0ae3.json 冻结不再重录，整店回放照它对
	for pair in [["tea", record_tea()]]:
		var path: String = DIR + "%s_73b0ae3.json" % pair[0]
		var text := JSON.stringify(pair[1], "\t", false)
		if check:
			var old := FileAccess.get_file_as_string(path)
			var same: bool = old.strip_edges() == text.strip_edges()
			print("%s %s" % ["一致" if same else "不一致", path])
			failed = failed or not same
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(text + "\n")
			file.close()
			print("写出 %s（完店 %.1f 分钟）" % [path, float(pair[1].completed_at) / 60.0])
	quit(1 if failed else 0)


# ---------- 公共：分段记账 ----------

class Ledger:
	var segments: Array = []
	var seg: Dictionary = {}
	var actions: Array = []
	var unlocks: Dictionary = {}
	var checkpoints: Dictionary = {}

	func open(stage: int, clock: float) -> void:
		if not seg.is_empty(): close(clock)
		seg = {"stage": stage, "start": snappedf(clock, 0.1), "arrived": 0, "full_seconds": 0.0, "lost": 0,
			"work": 0.0, "walk": 0.0, "idle": 0.0, "sold": 0, "waiting": {}}

	func close(clock: float) -> void:
		var total: float = seg.work + seg.walk + seg.idle
		var out := {"stage": seg.stage, "start": seg.start, "seconds": snappedf(clock - seg.start, 0.1),
			"arrived": seg.arrived, "full_seconds": snappedf(seg.full_seconds, 0.1), "lost": seg.lost, "sold": seg.sold,
			"staff_work": snappedf(seg.work / maxf(total, 0.001), 0.001), "staff_walk": snappedf(seg.walk / maxf(total, 0.001), 0.001),
			"staff_idle": snappedf(seg.idle / maxf(total, 0.001), 0.001)}
		# 主要瓶颈：员工最常在哪等 / 满队时间占比
		var worst := ""
		var most := 0.0
		for key in seg.waiting:
			if seg.waiting[key] > most:
				most = seg.waiting[key]
				worst = key
		out["top_wait"] = worst
		out["top_wait_share"] = snappedf(most / maxf(total, 0.001), 0.001)
		out["full_share"] = snappedf(seg.full_seconds / maxf(clock - seg.start, 0.001), 0.001)
		segments.append(out)
		seg = {}

	func act(clock: float, command: String) -> void:
		actions.append([snappedf(clock, 0.1), command])


# ---------- 奶茶店 ----------

func record_tea() -> Dictionary:
	var sim = TeaSim.new()
	var ledger := Ledger.new()
	var dt: float = sim.STEP
	var next_visit := 1.0
	var completed_at := -1.0
	var last_stage := -1
	var arrived_id: int = sim._next_order
	var sold_before: int = sim.sold
	while sim.elapsed < MINUTES.tea * 60.0 - 0.0001:
		sim.advance(dt)
		var clock: float = sim.elapsed
		if sim.stage_index != last_stage:
			last_stage = sim.stage_index
			ledger.open(last_stage, clock)
		ledger.seg.arrived += sim._next_order - arrived_id
		arrived_id = sim._next_order
		ledger.seg.sold += sim.sold - sold_before
		sold_before = sim.sold
		if sim.station_unlocked("lemonade") and sim.orders.size() >= sim._queue_capacity(): ledger.seg.full_seconds += dt
		for worker in sim.workers:
			if worker.walking: ledger.seg.walk += dt
			elif worker.job.is_empty():
				ledger.seg.idle += dt
				if not worker.ticket.is_empty():
					var key: String = "wait:" + String(worker.ticket.stage)
					ledger.seg.waiting[key] = ledger.seg.waiting.get(key, 0.0) + dt
			else: ledger.seg.work += dt
		if completed_at < 0.0 and sim.shop_complete(): completed_at = clock
		for minute in CHECKPOINTS:
			if not ledger.checkpoints.has(str(minute)) and clock >= minute * 60.0 - 0.0001:
				ledger.checkpoints[str(minute)] = {"revenue": sim.revenue, "sold": sim.sold, "gold": sim.gold,
					"sold_by_dish": sim.sold_by_dish.duplicate(), "staff": sim.workers.size(), "stage": sim.stage_index}
		if clock + 0.0001 < next_visit: continue
		next_visit += 60.0
		_tea_glance(sim, ledger)
	ledger.close(sim.elapsed)
	return {"shop": "tea", "seed": sim.CONFIG.random_seed, "minutes": MINUTES.tea, "bot": "glance_once_a_minute",
		"unlocks": ledger.unlocks, "checkpoints": ledger.checkpoints, "completed_at": snappedf(completed_at, 0.1),
		"segments": ledger.segments, "levels": sim.station_levels.duplicate(), "material_levels": sim.material_levels.duplicate(true),
		"actions": ledger.actions}


func _tea_glance(sim, ledger: Ledger) -> void:
	var clock: float = sim.elapsed
	var p = sim.PROGRESSION
	if not sim.station_unlocked("lemonade"):
		if sim.unlock_station("lemonade").is_empty():
			ledger.unlocks["lemonade"] = snappedf(clock, 0.1)
			ledger.act(clock, "unlock lemonade")
		return
	if sim.orders.size() <= 1 and sim.buy_flyers().is_empty(): ledger.act(clock, "flyer")
	for _i in 8:
		var box: String = sim.pending_box()
		if not box.is_empty():
			if sim.unlock_box(box).is_empty():
				ledger.unlocks["box_" + box] = snappedf(clock, 0.1)
				ledger.act(clock, "box " + box)
				continue
			return
		var target := 0
		if sim.stage_index < p.stages.size() - 1:
			var machine: String = sim.STAGE_MACHINES[sim.stage_index + 1][0]
			target = p.stages[sim.stage_index + 1].line_cost
			if sim.unlock_station(machine).is_empty():
				ledger.unlocks[machine] = snappedf(clock, 0.1)
				ledger.act(clock, "unlock " + machine)
				continue
		if sim.workers.size() < sim.staff_slots():
			var idle: Array = sim.all_workers().filter(func(w: Dictionary) -> bool: return not w.deployed)
			if idle.is_empty() and sim.hire():
				idle = sim.all_workers().filter(func(w: Dictionary) -> bool: return not w.deployed)
				ledger.unlocks["hire%d" % sim.roster.size()] = snappedf(clock, 0.1)
				ledger.act(clock, "hire")
			if not idle.is_empty() and sim.deploy_worker(int(idle[0].id)).is_empty():
				ledger.act(clock, "deploy %d" % int(idle[0].id))
				continue
		# 最便宜的一项；攒钱解锁下一阶段时，超过目标 1/4 的升级先不买（任务要的除外）
		var options: Array = []
		for id in ["lemonade", "boil", "seal", "mix", "press", "topping"]:
			if sim.station_unlocked(id) and sim._upgrade_error(id) == "":
				options.append([sim._upgrade_costs(id)[sim.station_levels[id] - 1], "upgrade " + id])
		for id in sim.material_levels:
			for material in sim.material_levels[id]:
				if sim._material_error(id, material) == "":
					options.append([sim._material_costs(id, material)[sim.material_levels[id][material] - 1], "material %s %s" % [id, material]])
		for side in ["front", "kitchen"]:
			var info: Dictionary = sim.staff_upgrade_info(side)
			if info.error == "": options.append([info.cost, "staff " + side])
		if sim.seat_error() == "": options.append([sim.seat_cost(), "seat"])
		if sim.flyer_upgrade_error() == "": options.append([sim.flyer_upgrade_cost(), "flyer_upgrade"])
		if options.is_empty(): return
		options.sort()
		var tasks_wanted := []
		for stage in p.stages.slice(0, sim.stage_index + 1):
			for t in stage.tasks:
				if t.condition == 2: tasks_wanted.append("upgrade " + sim._canonical(t.target_id))
		var pick: Array = options[0]
		for option in options:
			if option[1] in tasks_wanted and sim.station_levels.get(String(option[1]).get_slice(" ", 1), 99) < 10:
				pick = option
				break
		if target > 0 and pick[0] > 0.25 * target and not pick[1] in tasks_wanted: return
		if not _tea_buy(sim, pick[1]).is_empty(): return
		ledger.act(clock, pick[1])


func _tea_buy(sim, command: String) -> String:
	var parts := command.split(" ")
	match parts[0]:
		"upgrade": return sim.upgrade_station(parts[1])
		"material": return sim.upgrade_material(parts[1], parts[2])
		"staff": return sim.buy_staff_upgrade(parts[1])
		"seat": return sim.buy_seat()
		"flyer_upgrade": return sim.upgrade_flyers()
	return "未知命令"
