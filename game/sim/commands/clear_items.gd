class_name ClearItemsCommand
extends SimCommand
## 清空一段传送带上的物料（不退款），Diagnostics 记录清理数量。

var segment_id: String


func _init(segment_id_: String) -> void:
	segment_id = segment_id_


func validate(sim: GameSim) -> String:
	if not sim.production.has_segment(segment_id):
		return "没有这段传送带"
	return sim.validate_kitchen_slots(sim.production.segment_slots(segment_id))


func commit(sim: GameSim) -> void:
	sim.push_events(sim.production.clear_segment(segment_id))
