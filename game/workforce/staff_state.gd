class_name StaffState
extends RefCounted
## 一名员工在本店的运行状态。

var staff_id := ""
var zone := ""
## 调岗目标；非空时不再认领新请求，做完当前步骤再走
var target_zone := ""
var walk_left := 0.0
var request_id := -1
var work_seconds := 0.0
var work_done := 0.0


static func create(id: String, start_zone: String) -> StaffState:
	var s := StaffState.new()
	s.staff_id = id
	s.zone = start_zone
	return s


func is_free() -> bool:
	return request_id == -1 and target_zone == ""


func to_dict() -> Dictionary:
	return {
		"staff": staff_id,
		"zone": zone,
		"target": target_zone,
		"walk_left": walk_left,
		"request": request_id,
		"work_seconds": work_seconds,
		"work_done": work_done,
	}


static func from_dict(d: Dictionary) -> StaffState:
	var s := StaffState.create(String(d.staff), String(d.zone))
	s.target_zone = String(d.target)
	s.walk_left = float(d.walk_left)
	s.request_id = int(d.request)
	s.work_seconds = float(d.work_seconds)
	s.work_done = float(d.work_done)
	return s
