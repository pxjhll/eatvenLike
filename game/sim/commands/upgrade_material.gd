class_name UpgradeMaterialCommand
extends SimCommand
## 升级机器上的一个物料槽（原料柜的一种原料、加料机的一种配料）。点开机器的面板里发。

var slot_id: String
var material_id: String


func _init(slot_id_: String, material_id_: String) -> void:
	slot_id = slot_id_
	material_id = material_id_


func validate(sim: GameSim) -> String:
	if not sim.production.has_slot(slot_id):
		return "没有这个工位"
	var reason := sim.validate_kitchen_slots([slot_id])
	if reason != "":
		return reason
	reason = sim.production.validate_material_upgrade(slot_id, material_id)
	if reason != "":
		return reason
	if not sim.economy.can_spend(sim.production.material_upgrade_cost(slot_id, material_id)):
		return "金币不足"
	return ""


func commit(sim: GameSim) -> void:
	sim.economy.spend(sim.production.material_upgrade_cost(slot_id, material_id))
	var level := sim.production.commit_material_upgrade(slot_id, material_id)
	sim.push_events([{"type": "material_level", "slot": slot_id, "material": material_id, "level": level}])
