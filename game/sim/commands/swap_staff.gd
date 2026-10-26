class_name SwapStaffCommand
extends SimCommand
## 交换两名员工的岗位（把人拖到已经有人的工位上时用）。

var staff_a: String
var staff_b: String


func _init(staff_a_: String, staff_b_: String) -> void:
	staff_a = staff_a_
	staff_b = staff_b_


func validate(sim: GameSim) -> String:
	if not sim.workforce.has_staff(staff_a) or not sim.workforce.has_staff(staff_b):
		return "没有这名员工"
	if staff_a == staff_b:
		return "同一名员工"
	return ""


func commit(sim: GameSim) -> void:
	sim.workforce.swap(staff_a, staff_b)
