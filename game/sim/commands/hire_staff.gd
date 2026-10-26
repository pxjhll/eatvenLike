class_name HireStaffCommand
extends SimCommand
## 招一名员工（局内金币）。招来的人先在员工栏里未上岗，拖到工位才干活。

var staff_id := ""


func validate(sim: GameSim) -> String:
	if sim.workforce.hire_def() == null:
		return "这家店不能招人"
	if not sim.economy.can_spend(sim.workforce.hire_cost()):
		return "金币不足"
	return ""


func commit(sim: GameSim) -> void:
	sim.economy.spend(sim.workforce.hire_cost())
	staff_id = sim.workforce.hire(sim.next_id())
	sim.push_events([{"type": "staff_hired", "staff": staff_id}])
