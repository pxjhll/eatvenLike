extends SceneTree
## 在通用规则层上录煎饼摊的整店基准（旧模拟已删，改数值以后用它重录）：
##   godot --headless --path . -s tests/baselines/record_rules.gd [-- --check]
## 机器人和录旧基准时同一套决策（每分钟看一眼：先买新机器要的原料箱、再解锁、员工忙就招人、买最便宜的升级（机器、原料/口味、员工、传单、座位），
## 鏊子忙时优先升鏊子，攒钱解锁时超过目标 1/4 的升级先不买）。录下操作序列以后用 replay_rules 重放算出各项结果，
## 写出 tests/baselines/pancake_rules.json，格式和 *_73b0ae3.json 一样。
## --check：重录一遍和已存的比，不一致退出码 1。

const Replay := preload("res://tests/baselines/replay_rules.gd")
## Historical v0 economy; formal v1 rhythm is reported separately.
const SHOP: SpecShop = preload("res://tests/fixtures/legacy_shops/pancake.tres")
const MINUTES := 30.0


func _initialize() -> void:
	var data := record(SHOP)
	var path: String = "res://tests/baselines/" + Replay.BASELINES[SHOP.id]
	var text := JSON.stringify(data, "\t", false)
	if "--check" in OS.get_cmdline_user_args():
		var same := FileAccess.get_file_as_string(path).strip_edges() == text.strip_edges()
		print("%s %s" % ["一致" if same else "不一致", path])
		quit(0 if same else 1)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text + "\n")
	file.close()
	print("写出 %s（完店 %.1f 分钟）" % [path, float(data.completed_at) / 60.0])
	quit()


static func record(shop: SpecShop) -> Dictionary:
	var rules := ShopRules.new(shop)
	var actions: Array = []
	var unlocks := {}
	var next_visit := 1.0
	var busy := 0.0
	var griddle := 0.0
	var samples := 0
	var hand := ""
	for st in shop.stations:
		if st.block == "hand" and int(st.params.get("users", 0)) > 0: hand = st.id
	while rules.clock < MINUTES * 60.0 - 0.0001:
		rules.step(ShopRules.STEP)
		var clock := rules.clock
		samples += 1
		for w in rules.workers:
			if w.walking or w.phase == "work" or not w.job.is_empty(): busy += 1.0 / rules.workers.size()
		if not hand.is_empty() and rules.stations.has(hand) and int(rules.stations[hand].get("user", -1)) != -1: griddle += 1.0
		if clock + 0.0001 < next_visit: continue
		next_visit += 60.0
		var staff_load := busy / maxf(1.0, samples)
		var hand_load := griddle / maxf(1.0, samples)
		busy = 0.0
		griddle = 0.0
		samples = 0
		var at := snappedf(clock, 0.1)
		if rules.queue_size() <= 1 and rules.send_flyers() == "": actions.append([at, "flyer"])
		for _i in 6:
			# 新机器要用的原料箱先买（买了才能卖新菜）
			var box := rules.pending_box()
			if not box.is_empty() and rules.unlock_box(box) == "":
				unlocks["box " + box] = at
				actions.append([at, "box " + box])
				continue
			var nxt := rules.next_unlock()
			if not nxt.is_empty() and rules.unlock(nxt) == "":
				unlocks[nxt] = at
				actions.append([at, "unlock " + nxt])
				continue
			if rules.workers.size() < rules.staff_slots() and staff_load > 0.7 and rules.hire() == "":
				unlocks["hire%d" % rules.workers.size()] = at
				actions.append([at, "hire"])
				continue
			# 能花钱的地方：机器升级、员工升级、传单升级、买座位（价格、命令）
			var opts := []
			for st in shop.stations:
				if not st.tracks.is_empty() and rules.station_unlocked(st.id) and rules.upgrade_error(st.id) == "":
					opts.append([rules.upgrade_cost(st.id), "upgrade " + st.id])
				for m in st.materials:
					var key := st.id + "/" + m.id
					if m.track != null and not m.track.levels.is_empty() and rules.upgrade_error(key) == "":
						opts.append([rules.upgrade_cost(key), "material %s %s" % [st.id, m.id]])
			for t in shop.staff.tracks:
				if rules.upgrade_error("staff/" + t.id) == "": opts.append([rules.upgrade_cost("staff/" + t.id), "staff " + t.id])
			if rules.upgrade_error("flyer") == "": opts.append([rules.upgrade_cost("flyer"), "flyer_upgrade"])
			if rules.buy_group() != null and rules.seat_error() == "": opts.append([rules.seat_cost(), "seat"])
			if opts.is_empty(): break
			opts.sort()
			var pick: Array = opts[0]
			var prefer := hand_load > 0.7 and opts.any(func(o: Array) -> bool: return o[1] == "upgrade " + hand)
			if prefer: pick = opts.filter(func(o: Array) -> bool: return o[1] == "upgrade " + hand)[0]
			var target := rules.next_stage_cost() if not nxt.is_empty() else 0
			if not nxt.is_empty() and pick[0] > 0.25 * target and not prefer: break
			if Replay.run_command(rules, pick[1]) != "": break
			actions.append([at, pick[1]])
	var base := {"minutes": MINUTES, "actions": actions}
	var result := Replay.replay(shop, base)
	var levels := {}
	for st in shop.stations:
		if not st.tracks.is_empty(): levels[st.id] = rules.level(st.id)
	return {"shop": shop.id, "seed": shop.random_seed, "minutes": MINUTES, "bot": "glance_once_a_minute",
		"unlocks": unlocks, "checkpoints": result.checkpoints, "completed_at": result.completed_at,
		"segments": result.segments, "levels": levels, "actions": actions}
