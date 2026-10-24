class_name UpgradeStationCommand
extends SimCommand
## 升级工位：按 StationDef.owner 路由到 Production 或 FrontHall。

var slot_id: String


func _init(slot_id_: String) -> void:
	slot_id = slot_id_


func validate(sim: GameSim) -> String:
	var owner_system := sim.station_owner(slot_id)
	if owner_system == null:
		return "没有这个工位"
	var reason: String = owner_system.validate_upgrade(slot_id)
	if reason != "":
		return reason
	if not sim.economy.can_spend(owner_system.upgrade_cost(slot_id)):
		return "金币不足"
	return ""


func commit(sim: GameSim) -> void:
	var owner_system := sim.station_owner(slot_id)
	sim.economy.spend(owner_system.upgrade_cost(slot_id))
	var level: int = owner_system.commit_upgrade(slot_id)
	sim.push_events([{"type": "station_level", "station": owner_system.station_def(slot_id).id, "level": level}])
