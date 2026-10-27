class_name WorkforceSystem
extends RefCounted
## 本店员工：招来的人、所在工位（一人一岗）、请求认领与释放、人工进度、效率倍率。
## 不管物料和订单，不创建或销毁请求。
##
## 按工位派工：员工上岗在哪个工位（前厅位点或后厨设备），就只做那个工位的活。
## 后厨员工固定站工位、不走路，调岗立即生效（决定⑫）；正在做的那一份做完再换。

const EPS := 0.000001

var _config: ShopConfig
var _defs := {}  # def_id -> StaffDef（只读）

var staff: Array[StaffState] = []


func setup(config: ShopConfig, roster: Array[StaffDef]) -> void:
	_config = config
	# 空店开局的店一个人都没有，名册里的人不带进来，全靠局内招人
	for d in roster:
		_defs[d.id] = d
		if not config.hires_own_staff:
			staff.append(StaffState.create(d.id, d.id))
	for d in config.hire_defs:
		_defs[d.id] = d


## 员工 × 工作区 → 速度倍率。全工程只在这里算；以后加特长、稀有度、星级只改这里。
func efficiency(staff_id: String, zone: String) -> float:
	var s := _find(staff_id)
	var d: StaffDef = _defs.get(s.def_id if s != null else staff_id)
	return d.zone_efficiency.get(zone, 1.0) if d != null else 1.0


func has_staff(staff_id: String) -> bool:
	return _find(staff_id) != null


func staff_count() -> int:
	return staff.size()


## 这个工位上已经有几个人
func post_occupancy(post: String) -> int:
	var count := 0
	for s in staff:
		if s.post == post:
			count += 1
	return count


func display_name(staff_id: String) -> String:
	var s := _find(staff_id)
	var d: StaffDef = _defs.get(s.def_id if s != null else staff_id)
	return d.display_name if d != null else staff_id


## 第 N 名员工的招人价（N 从 1 起）
func hire_cost() -> int:
	var costs := _config.hire_costs
	if costs.is_empty():
		return 0
	return costs[mini(staff.size(), costs.size() - 1)]


## 招来的人用哪个模板：按顺序取，用完重复最后一个
func hire_def() -> StaffDef:
	var defs := _config.hire_defs
	if defs.is_empty():
		return null
	return defs[mini(staff.size(), defs.size() - 1)]


## HireStaff：新增一名未上岗员工。id 由 GameSim 发号，所以同一个模板可以招多个。
func hire(new_id: int) -> String:
	var d := hire_def()
	assert(d != null, "这家店没配招人模板")
	_defs[d.id] = d
	var staff_id := "staff%d" % new_id
	staff.append(StaffState.create(staff_id, d.id))
	return staff_id


func claimed_request_ids() -> Dictionary:
	var out := {}
	for s in staff:
		if s.request_id != -1:
			out[s.request_id] = s.staff_id
	return out


## tick 第 3 步：把「现在可执行」的请求派给空闲员工。一个请求只给一名员工。
func dispatch(open: Array) -> void:
	var claimed := claimed_request_ids()
	for s in staff:
		if not s.is_free():
			continue
		for r in open:
			if _can_take(s, r) and not claimed.has(r.id):
				s.request_id = r.id
				s.work_seconds = r.seconds
				s.work_done = 0.0
				claimed[r.id] = s.staff_id
				break


## tick 第 4 步：推进人工进度，返回本 tick 完成的请求
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
	return completed


## 上岗；post 为空 = 下岗。正在做的人工步骤照样做完（认领的请求不变），之后只接新工位的活。
## 前厅服务员的走动只是表现。
func assign_post(staff_id: String, post: String, zone: String) -> void:
	var s := _find(staff_id)
	s.post = post
	s.zone = zone


## 拖到有人的工位上时交换两人的岗位
func swap(staff_a: String, staff_b: String) -> void:
	var a := _find(staff_a)
	var b := _find(staff_b)
	var post := a.post
	var zone := a.zone
	a.post = b.post
	a.zone = b.zone
	b.post = post
	b.zone = zone


func to_dict() -> Dictionary:
	var list := []
	for s in staff:
		list.append(s.to_dict())
	return {"staff": list}


func from_dict(d: Dictionary) -> void:
	staff.clear()
	for sd in d.staff:
		staff.append(StaffState.from_dict(sd))


## 请求带工位，只有站在那个工位的人能做
func _can_take(s: StaffState, r: Dictionary) -> bool:
	return s.post != "" and s.post == String(r.post)


func _find(staff_id: String) -> StaffState:
	for s in staff:
		if s.staff_id == staff_id:
			return s
	return null
