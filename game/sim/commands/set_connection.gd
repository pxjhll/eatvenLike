class_name SetConnectionCommand
extends SimCommand
## 接上或断开一条 ShopConfig 允许的连接。线上已有物料留在原处。

var from_slot: String
var to_slot: String
var connected: bool


func _init(from_slot_: String, to_slot_: String, connected_: bool = true) -> void:
	from_slot = from_slot_
	to_slot = to_slot_
	connected = connected_


func validate(sim: GameSim) -> String:
	var reason := sim.validate_kitchen_slots([from_slot, to_slot])
	if reason != "":
		return reason
	return sim.production.validate_connection(from_slot, to_slot)


func commit(sim: GameSim) -> void:
	sim.production.commit_connection(from_slot, to_slot, connected)
