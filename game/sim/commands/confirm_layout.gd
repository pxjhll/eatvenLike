class_name ConfirmLayoutCommand
extends SimCommand
## 确认布局：扣新设备的钱，草稿生效，传送带按草稿铺好，回到经营模式。

var added: Array[String] = []


func layout_only() -> bool:
	return true


func allowed_in_layout() -> bool:
	return true


func validate(sim: GameSim) -> String:
	var reason := sim.layout.draft_problem()
	if reason != "":
		return reason
	if not sim.layout.draft_route().failed.is_empty():
		return "有传送带铺不通"
	if not sim.economy.can_spend(sim.layout.draft_cost()):
		return "金币不足"
	return ""


func commit(sim: GameSim) -> void:
	sim.economy.spend(sim.layout.draft_cost())
	added = sim.layout.commit_draft(sim.next_id)
	sim.production.apply_layout(sim.layout.devices, sim.layout.belts)
	sim.mode = GameSim.Mode.BUSINESS
	sim.push_events([{"type": "layout_confirmed", "added": added.duplicate()}])
