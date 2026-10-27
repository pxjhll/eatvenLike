class_name AutoDeployCommand
extends SimCommand
## 一键部署：已开放、草稿里还没有的设备放到推荐位；推荐位被占的跳过，留在设备栏。

var placed: Array[String] = []


func layout_only() -> bool:
	return true


func allowed_in_layout() -> bool:
	return true


func commit(sim: GameSim) -> void:
	placed = sim.layout.auto_deploy(sim.progress.open_devices())
