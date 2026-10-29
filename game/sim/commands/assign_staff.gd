class_name AssignStaffCommand
extends SimCommand
## 调岗。target 是前厅位点 id（上岗到这个工位）、工作区名（后厨，暂时仍按工作区）
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
	if sim.front_hall.has_spot(target):
		if not sim.front_hall.is_active(target):
			return "这个工位还没解锁"
		var capacity := sim.front_hall.post_capacity(target)
		if capacity <= 0:
			return "这个工位不要员工"
		if sim.workforce.post_occupancy(target) >= capacity and not _already_there(sim):
			return "这个工位满了"
		return ""
	if target == sim.config.kitchen_zone and sim.validate_kitchen_access() != "":
		return sim.validate_kitchen_access()
	if not sim.workforce.has_zone(target):
		return "没有这个工位"
	return ""


func commit(sim: GameSim) -> void:
	if target == "":
		sim.workforce.assign_post(staff_id, "", "")
	elif sim.front_hall.has_spot(target):
		sim.workforce.assign_post(staff_id, target, sim.front_hall.station_def(target).zone)
	else:
		sim.workforce.assign(staff_id, target)


func _already_there(sim: GameSim) -> bool:
	for s in sim.workforce.staff:
		if s.staff_id == staff_id:
			return s.post == target
	return false
