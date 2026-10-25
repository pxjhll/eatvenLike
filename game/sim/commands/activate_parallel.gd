class_name ActivateParallelCommand
extends SimCommand
## 启用固定机位旁的并联槽。

var slot_id: String


func _init(slot_id_: String) -> void:
	slot_id = slot_id_


func validate(sim: GameSim) -> String:
	var reason := sim.validate_kitchen_slots([slot_id])
	if reason != "":
		return reason
	reason = sim.production.validate_parallel(slot_id)
	if reason != "":
		return reason
	if not sim.economy.can_spend(sim.production.station_def(slot_id).parallel_cost):
		return "金币不足"
	return ""


func commit(sim: GameSim) -> void:
	sim.economy.spend(sim.production.station_def(slot_id).parallel_cost)
	sim.production.commit_parallel(slot_id)
