class_name RemoveDraftDeviceCommand
extends SimCommand
## 把本次草稿里新放的设备拿回设备栏。

var device_id: String


func _init(device_id_: String) -> void:
	device_id = device_id_


func layout_only() -> bool:
	return true


func allowed_in_layout() -> bool:
	return true


func validate(sim: GameSim) -> String:
	return sim.layout.validate_remove(device_id)


func commit(sim: GameSim) -> void:
	sim.layout.draft_remove(device_id)
