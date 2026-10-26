class_name StaffState
extends RefCounted
## 一名员工在本店的运行状态。

var staff_id := ""
## 员工模板 id（招来的人共用模板，staff_id 才是唯一的）
var def_id := ""
## 上岗的工位 id（前厅位点 / 后厨机位）；空 = 未上岗
var post := ""
## 后厨还没进布局模式，仍按工作区派工（PXJ-47 后只剩工位）
var zone := ""
## 调岗目标工作区；非空时不再认领新请求，做完当前步骤再走
var target_zone := ""
var walk_left := 0.0
var request_id := -1
var work_seconds := 0.0
var work_done := 0.0


static func create(id: String, start_zone: String, def_id_: String = "") -> StaffState:
	var s := StaffState.new()
	s.staff_id = id
	s.def_id = def_id_ if def_id_ != "" else id
	s.zone = start_zone
	return s


func is_free() -> bool:
	return request_id == -1 and target_zone == ""


func to_dict() -> Dictionary:
	return {
		"staff": staff_id,
		"def": def_id,
		"post": post,
		"zone": zone,
		"target": target_zone,
		"walk_left": walk_left,
		"request": request_id,
		"work_seconds": work_seconds,
		"work_done": work_done,
	}


static func from_dict(d: Dictionary) -> StaffState:
	var s := StaffState.create(String(d.staff), String(d.zone), String(d.get("def", d.staff)))
	s.post = String(d.get("post", ""))
	s.target_zone = String(d.target)
	s.walk_left = float(d.walk_left)
	s.request_id = int(d.request)
	s.work_seconds = float(d.work_seconds)
	s.work_done = float(d.work_done)
	return s
