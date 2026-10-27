class_name MoveDeviceCommand
extends SimCommand
## 在草稿里挪动一台设备（已经摆好的也能挪，确认后保留它的进度、缓冲和等级）。

var device_id: String
var cell: Vector2i


func _init(device_id_: String, cell_: Vector2i) -> void:
	device_id = device_id_
	cell = cell_


func layout_only() -> bool:
	return true


func allowed_in_layout() -> bool:
	return true


func validate(sim: GameSim) -> String:
	return sim.layout.validate_move(device_id, cell)


func commit(sim: GameSim) -> void:
	sim.layout.draft_move(device_id, cell)
