class_name AssignStaffCommand
extends SimCommand
## 调岗：员工做完当前人工步骤再去新工作区。

var staff_id: String
var zone: String


func _init(staff_id_: String, zone_: String) -> void:
	staff_id = staff_id_
	zone = zone_


func validate(sim: GameSim) -> String:
	if not sim.workforce.has_staff(staff_id):
		return "没有这名员工"
	if not sim.workforce.has_zone(zone):
		return "没有这个工作区"
	return ""


func commit(sim: GameSim) -> void:
	sim.workforce.assign(staff_id, zone)
