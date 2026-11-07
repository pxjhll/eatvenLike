extends SceneTree
## 通用规则层整店回归（规格 §7）：把旧模拟基准里机器人的那串操作按原时刻在 ShopRules 上重放，
## 和 tests/baselines/ 里各店的基准（BASELINES）对比 5 / 10 / 20 / 30 分钟营业额、销量、完店时刻，偏差都要在 ±5% 内。
##   godot --headless --path . -s tests/baselines/replay_rules.gd [-- --verbose]
## 退出码 1 = 有一项超出范围。

## 基准里记的时刻（分钟）
const CHECKPOINTS := [5, 10, 20, 30, 45]
const SHOPS := {"tea": "res://content/shops/tea/shop.tres", "pancake": "res://content/shops/pancake/shop.tres"}
## 各店的基准文件：奶茶店仍对 main 73b0ae3 旧模拟录下的；煎饼摊改过数值，用 record_rules.gd 在通用规则上重录
const BASELINES := {"tea": "tea_73b0ae3.json", "pancake": "pancake_rules.json"}
const TOLERANCE := 0.05


func _initialize() -> void:
	var verbose := "--verbose" in OS.get_cmdline_user_args()
	var failed := false
	for id in SHOPS:
		var base: Dictionary = baseline(id)
		var result := replay(load(SHOPS[id]), base)
		var rows := compare(base, result)
		print("== %s ==" % id)
		for row in rows:
			print("  %-28s 旧 %10s  新 %10s  %s" % [row.name, row.old, row.new, "✓" if row.ok else "✗ 超出 ±5%"])
			failed = failed or not row.ok
		if verbose:
			print("  失败的操作：", result.failed_actions)
			for seg in result.segments: print("  ", seg)
	quit(1 if failed else 0)


static func baseline(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/baselines/" + BASELINES[id]))


static func replay(shop: SpecShop, base: Dictionary) -> Dictionary:
	var rules := ShopRules.new(shop)
	var ledger = Ledger.new()
	var minutes: float = base.minutes
	var actions: Array = base.actions
	var next_action := 0
	var completed_at := -1.0
	var last_stage := -2
	var single: bool = shop.fulfillment.handoff == "single"
	var arrived_before := rules.arrivals()
	var sold_before := rules.sold
	var failed_actions: Array = []
	while rules.clock < minutes * 60.0 - 0.0001:
		rules.step(ShopRules.STEP)
		var clock := rules.clock
		var stage: int = rules.stage_index if rules.is_open() or not single else -1
		if stage != last_stage:
			last_stage = stage
			ledger.open(stage, clock)
		ledger.seg.arrived += rules.arrivals() - arrived_before
		arrived_before = rules.arrivals()
		ledger.seg.sold += rules.sold - sold_before
		sold_before = rules.sold
		if rules.is_open() and rules.queue_size() >= rules.queue_capacity(): ledger.seg.full_seconds += ShopRules.STEP
		for worker in rules.workers:
			if worker.walking: ledger.seg.walk += ShopRules.STEP
			elif worker.phase == "work" or not worker.job.is_empty(): ledger.seg.work += ShopRules.STEP
			else: ledger.seg.idle += ShopRules.STEP
		if completed_at < 0.0 and rules.shop_complete(): completed_at = clock
		for minute in CHECKPOINTS:
			if not ledger.checkpoints.has(str(minute)) and clock >= minute * 60.0 - 0.0001:
				ledger.checkpoints[str(minute)] = {"revenue": snappedf(rules.revenue, 0.1), "sold": rules.sold, "gold": snappedf(rules.gold, 0.1),
					"sold_by_dish": rules.sold_by_dish.duplicate(), "staff": rules.workers.size(), "stage": rules.stage_index}
		while next_action < actions.size() and float(actions[next_action][0]) <= clock + 0.0001:
			var command: String = actions[next_action][1]
			var error := run_command(rules, command)
			if not error.is_empty(): failed_actions.append("%s %s：%s" % [actions[next_action][0], command, error])
			next_action += 1
	ledger.close(rules.clock)
	return {"checkpoints": ledger.checkpoints, "completed_at": snappedf(completed_at, 0.1), "segments": ledger.segments,
		"failed_actions": failed_actions}


## 旧机器人的命令 → ShopRules 命令
static func run_command(rules: ShopRules, command: String) -> String:
	var parts := command.split(" ")
	match parts[0]:
		"unlock": return rules.unlock(parts[1])
		"box": return rules.unlock_box(parts[1])
		"hire": return rules.hire()
		"deploy": return rules.deploy_worker(int(parts[1]))
		"upgrade": return rules.upgrade(parts[1])
		"material": return rules.upgrade(parts[1] + "/" + parts[2])
		"staff": return rules.upgrade("staff/" + parts[1])
		"seat": return rules.buy_seat()
		"flyer_upgrade": return rules.upgrade("flyer")
		"flyer": return rules.send_flyers()
	return "未知命令"


static func compare(base: Dictionary, result: Dictionary) -> Array:
	var rows: Array = []
	for minute in CHECKPOINTS:
		var key := str(minute)
		if not base.checkpoints.has(key) or not result.checkpoints.has(key): continue
		for field in ["revenue", "sold"]:
			var old := float(base.checkpoints[key][field])
			var new := float(result.checkpoints[key][field])
			rows.append({"name": "%d 分钟 %s" % [minute, field], "old": "%.0f" % old, "new": "%.0f" % new, "ok": _close(old, new)})
	var old_done := float(base.completed_at)
	var new_done := float(result.completed_at)
	rows.append({"name": "完店（分钟）", "old": "%.1f" % (old_done / 60.0), "new": "%.1f" % (new_done / 60.0),
		"ok": (old_done < 0.0) == (new_done < 0.0) and (old_done < 0.0 or _close(old_done, new_done))})
	return rows


static func _close(old: float, new: float) -> bool:
	if absf(old) < 20.0: return absf(new - old) <= 2.0
	return absf(new - old) / absf(old) <= TOLERANCE


## 分段记账：和录基准时（旧模拟，main 73b0ae3）同一种记法
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
