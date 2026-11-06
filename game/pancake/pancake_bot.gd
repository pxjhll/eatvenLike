extends RefCounted
## 每分钟看一次的玩家：发传单、开下一台、人手忙就招人、按卡点买升级。设计稿“基准玩家”。

const Sim := preload("res://game/pancake/pancake_sim.gd")

var visit := 60.0
var save_frac := 0.25


## 跑一局，返回事件时刻和统计。
func play(seed: int, minutes := 22.0, overrides := {}) -> Dictionary:
	var sim := Sim.new(seed)
	for k in overrides: sim.cfg[k] = overrides[k]
	sim.reset()
	var times := {}
	var busy := 0.0
	var griddle_busy := 0.0
	var samples := 0
	var next_visit := 1.0
	var dt := 0.1
	var done_at := -1.0
	while sim.clock < minutes * 60.0:
		sim.step(dt)
		samples += 1
		for s in sim.staff:
			if s.phase != "idle": busy += 1.0 / sim.staff.size()
		if sim.griddle_user != -1: griddle_busy += 1.0
		if done_at < 0.0 and sim.shop_complete(): done_at = sim.clock
		if sim.clock < next_visit: continue
		next_visit += visit
		var staff_load := busy / maxf(1.0, samples)
		var griddle_load := griddle_busy / maxf(1.0, samples)
		busy = 0.0
		griddle_busy = 0.0
		samples = 0
		if sim.queue.size() <= 1: sim.send_flyers()
		for _i in 6:
			var nxt: String = sim.next_unlock()
			if not nxt.is_empty() and sim.unlock(nxt):
				times[nxt] = sim.clock
				continue
			if sim.staff.size() < sim.staff_slots() and staff_load > 0.7 and sim.hire():
				times["hire%d" % sim.staff.size()] = sim.clock
				continue
			var opts := []
			for key in sim.cfg.upgrades:
				if sim.upgrade_available(key): opts.append([sim.upgrade_cost(key), key])
			if opts.is_empty(): break
			opts.sort()
			var pick: Array = opts[0]
			if griddle_load > 0.7:
				for o in opts:
					if o[1] == "rear_equipment": pick = o
			var target := sim.unlock_cost(nxt) if not nxt.is_empty() else 0
			var is_pref: bool = pick[1] == "rear_equipment" and griddle_load > 0.7
			if not nxt.is_empty() and pick[0] > save_frac * target and not is_pref: break
			if not sim.upgrade(pick[1]): break
	return {"times": times, "sold": sim.total_sold(), "lost": sim.lost, "earned": sim.earned, "gold": sim.gold,
		"tasks": sim.tasks_done(), "done_at": done_at, "levels": sim.levels.duplicate(), "sim": sim}
