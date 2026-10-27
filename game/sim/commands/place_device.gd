class_name PlaceDeviceCommand
extends SimCommand
## 从设备栏往后厨草稿里放一台设备。草稿不扣钱，确认时才扣（不变量 13）。

var def_id: String
var cell: Vector2i
## commit 后是草稿里的临时 id
var device_id := ""


func _init(def_id_: String, cell_: Vector2i) -> void:
	def_id = def_id_
	cell = cell_


func layout_only() -> bool:
	return true


func allowed_in_layout() -> bool:
	return true


func validate(sim: GameSim) -> String:
	if not def_id in sim.progress.open_devices():
		return "这台设备还没开放"
	return sim.layout.validate_place(def_id, cell)


func commit(sim: GameSim) -> void:
	device_id = sim.layout.draft_place(def_id, cell)
