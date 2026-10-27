class_name CancelLayoutCommand
extends SimCommand
## 取消布局：丢掉草稿，回到经营模式，什么都没变（不变量 12）。


func layout_only() -> bool:
	return true


func allowed_in_layout() -> bool:
	return true


func commit(sim: GameSim) -> void:
	sim.layout.discard_draft()
	sim.mode = GameSim.Mode.BUSINESS
