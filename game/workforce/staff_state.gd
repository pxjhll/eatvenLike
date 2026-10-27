class_name StaffState
extends RefCounted
## 一名员工在本店的运行状态。

var staff_id := ""
## 员工模板 id（招来的人共用模板，staff_id 才是唯一的）
var def_id := ""
## 上岗的工位 id（前厅位点 id / 后厨设备实例 id）；空 = 未上岗，在员工栏里
var post := ""
## 工位所在区域（"kitchen" / "front"），只用来取效率倍率
var zone := ""
var request_id := -1
var work_seconds := 0.0
var work_done := 0.0


static func create(id: String, def_id_: String = "") -> StaffState:
	var s := StaffState.new()
	s.staff_id = id
	s.def_id = def_id_ if def_id_ != "" else id
	return s


func is_free() -> bool:
	return request_id == -1


func to_dict() -> Dictionary:
	return {
		"staff": staff_id,
		"def": def_id,
		"post": post,
		"zone": zone,
		"request": request_id,
		"work_seconds": work_seconds,
		"work_done": work_done,
	}


static func from_dict(d: Dictionary) -> StaffState:
	var s := StaffState.create(String(d.staff), String(d.def))
	s.post = String(d.post)
	s.zone = String(d.zone)
	s.request_id = int(d.request)
	s.work_seconds = float(d.work_seconds)
	s.work_done = float(d.work_done)
	return s
