class_name WorkforceSystem
extends RefCounted
## 本店员工：所在工作区、请求认领与释放、人工进度、效率倍率。
## 不管物料和订单，不创建或销毁请求。

const EPS := 0.000001

var _config: ShopConfig
var _defs := {}  # staff_id -> StaffDef（只读）

var staff: Array[StaffState] = []


func setup(config: ShopConfig, roster: Array[StaffDef]) -> void:
	_config = config
	for d in roster:
		_defs[d.id] = d
		staff.append(StaffState.create(d.id, config.staff_start_zones.get(d.id, config.zones[0])))


## 员工 × 工作区 → 速度倍率。全工程只在这里算；以后加特长、稀有度、星级只改这里。
func efficiency(staff_id: String, zone: String) -> float:
	var d: StaffDef = _defs.get(staff_id)
	return d.zone_efficiency.get(zone, 1.0) if d != null else 1.0


func walk_seconds(from_zone: String, to_zone: String) -> float:
	return _config.walk_seconds.get(from_zone + ">" + to_zone, _config.walk_seconds.get(to_zone + ">" + from_zone, 0.0))


func has_zone(zone: String) -> bool:
	return zone in _config.zones


func has_staff(staff_id: String) -> bool:
	return _find(staff_id) != null


func claimed_request_ids() -> Dictionary:
	var out := {}
	for s in staff:
		if s.request_id != -1:
			out[s.request_id] = s.staff_id
	return out


## tick 第 3 步：把「现在可执行」的请求派给同工作区的空闲员工。一个请求只给一名员工。
func dispatch(open: Array) -> void:
	var claimed := claimed_request_ids()
	for s in staff:
		if not s.is_free():
			continue
		for r in open:
			if r.zone == s.zone and not claimed.has(r.id):
				s.request_id = r.id
				s.work_seconds = r.seconds
				s.work_done = 0.0
				claimed[r.id] = s.staff_id
				break


## tick 第 4 步：推进人工进度和走路，返回本 tick 完成的请求
## [{"id", "overshoot"}]，overshoot 是完成后本 tick 还剩的秒数（让请求方接着算，保证步长无关）。
func advance(dt: float) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	for s in staff:
		if s.request_id != -1:
			var eff := efficiency(s.staff_id, s.zone)
			s.work_done += dt * eff
			if s.work_done >= s.work_seconds - EPS:
				completed.append({"id": s.request_id, "overshoot": maxf(0.0, (s.work_done - s.work_seconds) / eff)})
				s.request_id = -1
				s.work_seconds = 0.0
				s.work_done = 0.0
				if s.target_zone != "":
					s.walk_left = walk_seconds(s.zone, s.target_zone)
		elif s.target_zone != "":
			s.walk_left -= dt
			if s.walk_left <= EPS:
				s.zone = s.target_zone
				s.target_zone = ""
				s.walk_left = 0.0
	return completed


## 调岗：正在做人工步骤就做完再走，期间不再认领旧区新请求。
func assign(staff_id: String, zone: String) -> void:
	var s := _find(staff_id)
	if zone == s.zone:
		s.target_zone = ""
		s.walk_left = 0.0
		return
	s.target_zone = zone
	if s.request_id == -1:
		s.walk_left = walk_seconds(s.zone, zone)


func to_dict() -> Dictionary:
	var list := []
	for s in staff:
		list.append(s.to_dict())
	return {"staff": list}


func from_dict(d: Dictionary) -> void:
	staff.clear()
	for sd in d.staff:
		staff.append(StaffState.from_dict(sd))


func _find(staff_id: String) -> StaffState:
	for s in staff:
		if s.staff_id == staff_id:
			return s
	return null
