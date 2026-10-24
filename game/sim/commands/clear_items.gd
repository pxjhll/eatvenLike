class_name ClearItemsCommand
extends SimCommand
## 清空一段传送带上的物料（不退款），Diagnostics 记录清理数量。

var segment_id: String


func _init(segment_id_: String) -> void:
	segment_id = segment_id_


func validate(sim: GameSim) -> String:
	return "" if sim.production.has_segment(segment_id) else "没有这段传送带"


func commit(sim: GameSim) -> void:
	sim.push_events(sim.production.clear_segment(segment_id))
