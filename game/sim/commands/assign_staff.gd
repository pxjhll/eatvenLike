class_name AssignStaffCommand
extends SimCommand
## 调岗。target 是前厅位点 id、后厨设备 id（要员工的那几种，一台一人），
## 或空字符串（下岗，回到员工栏）。拖到已经有人的满位上要用 SwapStaff。

var staff_id: String
var target: String


func _init(staff_id_: String, target_: String) -> void:
	staff_id = staff_id_
	target = target_


func validate(sim: GameSim) -> String:
	if not sim.workforce.has_staff(staff_id):
		return "没有这名员工"
	if target == "":
		return ""
	var capacity := 0
	if sim.front_hall.has_spot(target):
		if not sim.front_hall.is_active(target):
			return "这个工位还没解锁"
		capacity = sim.front_hall.post_capacity(target)
	elif sim.production.has_slot(target):
		capacity = 1 if sim.production.station_def(target).needs_staff() else 0
	else:
		return "没有这个工位"
	if capacity <= 0:
		return "这个工位不要员工"
	if sim.workforce.post_occupancy(target) >= capacity and not _already_there(sim):
		return "这个工位满了"
	return ""


func commit(sim: GameSim) -> void:
	if target == "":
		sim.workforce.assign_post(staff_id, "", "")
	else:
		sim.workforce.assign_post(staff_id, target, sim.station_owner(target).station_def(target).zone)


func _already_there(sim: GameSim) -> bool:
	for s in sim.workforce.staff:
		if s.staff_id == staff_id:
			return s.post == target
	return false
