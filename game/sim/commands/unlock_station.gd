class_name UnlockStationCommand
extends SimCommand
## 解锁 LOCKED 机位（买新机器带出新菜）。

var slot_id: String


func _init(slot_id_: String) -> void:
	slot_id = slot_id_


func validate(sim: GameSim) -> String:
	var reason := sim.progress.validate_unlock(slot_id, sim.economy.revenue)
	if reason != "":
		return reason
	var owner_system := sim.station_owner(slot_id)
	if owner_system == null:
		return "没有这个工位"
	if not sim.economy.can_spend(owner_system.station_def(slot_id).unlock_cost):
		return "金币不足"
	return owner_system.validate_unlock(slot_id)


func commit(sim: GameSim) -> void:
	var owner_system := sim.station_owner(slot_id)
	sim.economy.spend(owner_system.station_def(slot_id).unlock_cost)
	owner_system.commit_unlock(slot_id)
	var stage := sim.progress.mark_unlocked(slot_id)
	if stage >= 0:
		sim.front_hall.set_menu_stage(stage)
