class_name UnlockLineCommand
extends SimCommand
## 整条线一次点解锁：下一阶段 unlock_slots 里的机器连同传送带一起出现（首店流程稿 3）。
## 只用于 line_cost > 0 的阶段；单台买机器的阶段仍走 UnlockStation。


func validate(sim: GameSim) -> String:
	var stage := sim.progress.next_stage()
	if stage == null:
		return "没有可解锁的阶段"
	if stage.line_cost <= 0:
		return "这一阶段要一台一台解锁"
	if sim.economy.revenue < stage.revenue_threshold:
		return "累计营业额不足"
	if not sim.economy.can_spend(stage.line_cost):
		return "金币不足"
	for slot_id in stage.unlock_slots:
		var owner_system := sim.station_owner(slot_id)
		if owner_system == null:
			return "没有这个工位"
		var reason: String = owner_system.validate_unlock(slot_id)
		if reason != "":
			return reason
	return ""


func commit(sim: GameSim) -> void:
	var stage := sim.progress.next_stage()
	sim.economy.spend(stage.line_cost)
	var reached := -1
	for slot_id in stage.unlock_slots:
		sim.station_owner(slot_id).commit_unlock(slot_id)
		reached = sim.progress.mark_unlocked(slot_id)
	assert(reached >= 0)
	sim.front_hall.set_menu_stage(reached)
	sim.push_events([{"type": "line_unlocked", "stage": reached}])
