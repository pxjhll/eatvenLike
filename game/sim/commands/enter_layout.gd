class_name EnterLayoutCommand
extends SimCommand
## 进入布局模式：全店暂停，后厨出现推荐位虚线框，之后的改动都写进草稿。


func validate(sim: GameSim) -> String:
	return sim.validate_kitchen_access()


func commit(sim: GameSim) -> void:
	sim.layout.begin_draft()
	sim.mode = GameSim.Mode.LAYOUT
