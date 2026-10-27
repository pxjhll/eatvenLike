class_name LayoutSystem
extends RefCounted
## 后厨布局：已生效的设备（实例 id、定义 id、格子）、传送带路径、布局草稿、摆放合法性、一键部署。
## 不管物料、加工进度、金币、员工。不持有其他系统的引用。
##
## 布局模式里所有改动只写草稿；时间不走，所以取消 = 丢掉草稿（基线 §19、契约第 4 节）。

var _config: ShopConfig

## 已生效的设备：{"id": String, "def": String, "cell": Vector2i}
var devices: Array[Dictionary] = []
## 已生效的传送带：{"id", "from", "to", "item", "path": Array[Vector2i]}
var belts: Array[Dictionary] = []
## 布局草稿，只在布局模式里非空：
## {"devices": [...]（新放的带 "new": true）, "next": int, "route": {} 或 null, "failed": []}
var draft := {}


func setup(config: ShopConfig) -> void:
	_config = config


func has_device(device_id: String) -> bool:
	return _find(devices, device_id) != null


func device_def(device_id: String) -> StationDef:
	return _config.device_def(_find(devices, device_id).def)


# ---------------------------------------------------------------- 草稿

func in_draft() -> bool:
	return not draft.is_empty()


func begin_draft() -> void:
	var list := []
	for d in devices:
		list.append({"id": d.id, "def": d.def, "cell": d.cell, "new": false})
	draft = {"devices": list, "next": 1, "route": null, "failed": []}


func discard_draft() -> void:
	draft = {}


func draft_devices() -> Array:
	return draft.devices if in_draft() else []


func validate_place(def_id: String, cell: Vector2i) -> String:
	var def := _config.device_def(def_id)
	if def == null:
		return "没有这种设备"
	return LayoutRules.problem(_config, def, cell, draft.devices)


## 返回草稿里的临时 id
func draft_place(def_id: String, cell: Vector2i) -> String:
	assert(validate_place(def_id, cell) == "")
	var id := "new%d" % int(draft.next)
	draft.next = int(draft.next) + 1
	draft.devices.append({"id": id, "def": def_id, "cell": cell, "new": true})
	_changed()
	return id


func validate_move(device_id: String, cell: Vector2i) -> String:
	var d = _find(draft.devices, device_id)
	if d == null:
		return "没有这台设备"
	var others := []
	for other in draft.devices:
		if other.id != device_id:
			others.append(other)
	return LayoutRules.problem(_config, _config.device_def(d.def), cell, others)


func draft_move(device_id: String, cell: Vector2i) -> void:
	assert(validate_move(device_id, cell) == "")
	_find(draft.devices, device_id).cell = cell
	_changed()


## 只能拿掉本次草稿里新放的（已生效的设备要出售，以后再做）
func validate_remove(device_id: String) -> String:
	var d = _find(draft.devices, device_id)
	if d == null:
		return "没有这台设备"
	return "" if d.new else "已经摆好的设备不能在这里拿掉"


func draft_remove(device_id: String) -> void:
	assert(validate_remove(device_id) == "")
	draft.devices.erase(_find(draft.devices, device_id))
	_changed()


## 一键部署：已开放、草稿里还没有的设备，按推荐位顺序放；推荐位放不下就跳过，留在设备栏
func auto_deploy(open_defs: Array[String]) -> Array[String]:
	var placed: Array[String] = []
	for rec in _config.grid.recommended:
		var def_id := String(rec.station)
		if not def_id in open_defs or _has_def(draft.devices, def_id):
			continue
		if validate_place(def_id, rec.cell) == "":
			placed.append(draft_place(def_id, rec.cell))
	return placed


## 草稿里新设备的总价
func draft_cost() -> int:
	var cost := 0
	for d in draft.devices:
		if d.new:
			cost += _config.device_def(d.def).price
	return cost


## 草稿的寻路结果（算过就缓存，草稿再变才重算）
func draft_route() -> Dictionary:
	if draft.route == null:
		draft.route = BeltRouter.route(_config, draft.devices)
		draft.failed = draft.route.failed
	return draft.route


## 草稿里每台设备的位置都合法（一键部署和移动都校验过，这里再兜一次）
func draft_problem() -> String:
	for d in draft.devices:
		var others := []
		for other in draft.devices:
			if other.id != d.id:
				others.append(other)
		var reason := LayoutRules.problem(_config, _config.device_def(d.def), d.cell, others)
		if reason != "":
			return reason
	return ""


## ConfirmLayout 提交：新设备换成正式 id，草稿替换生效布局。返回新设备的 id 列表。
func commit_draft(new_id: Callable) -> Array[String]:
	var route := draft_route()
	var ids := {}
	var added: Array[String] = []
	devices.clear()
	for d in draft.devices:
		var id: String = d.id
		if d.new:
			id = "d%d" % int(new_id.call())
			ids[d.id] = id
			added.append(id)
		devices.append({"id": id, "def": d.def, "cell": d.cell})
	belts.clear()
	for b in route.belts:
		var from := String(ids.get(b.from, b.from))
		var to := String(ids.get(b.to, b.to))
		belts.append({"id": "%s>%s:%s" % [from, to, b.item], "from": from, "to": to, "item": b.item, "path": b.path.duplicate()})
	draft = {}
	return added


# ---------------------------------------------------------------- 存档与快照

## 草稿不存：布局模式里存档按取消处理（契约第 8 节）
func to_dict() -> Dictionary:
	var ds := []
	for d in devices:
		ds.append({"id": d.id, "def": d.def, "cell": [d.cell.x, d.cell.y]})
	var bs := []
	for b in belts:
		var path := []
		for c in b.path:
			path.append([c.x, c.y])
		bs.append({"id": b.id, "from": b.from, "to": b.to, "item": b.item, "path": path})
	return {"devices": ds, "belts": bs}


func from_dict(d: Dictionary) -> void:
	devices.clear()
	for dd in d.devices:
		devices.append({"id": String(dd.id), "def": String(dd.def), "cell": Vector2i(int(dd.cell[0]), int(dd.cell[1]))})
	belts.clear()
	for bd in d.belts:
		var path: Array[Vector2i] = []
		for c in bd.path:
			path.append(Vector2i(int(c[0]), int(c[1])))
		belts.append({"id": String(bd.id), "from": String(bd.from), "to": String(bd.to), "item": String(bd.item), "path": path})
	draft = {}


## 给表现层：生效布局 + 草稿（布局模式里）
func snapshot() -> Dictionary:
	var out := to_dict()
	if in_draft():
		var ds := []
		for d in draft.devices:
			ds.append({"id": d.id, "def": d.def, "cell": [d.cell.x, d.cell.y], "new": d.new})
		var route := draft_route()
		var bs := []
		for b in route.belts:
			var path := []
			for c in b.path:
				path.append([c.x, c.y])
			bs.append({"id": b.id, "from": b.from, "to": b.to, "item": b.item, "path": path})
		out.draft = {"devices": ds, "belts": bs, "cost": draft_cost(), "failed": route.failed.duplicate(true), "problem": draft_problem()}
	return out


# ---------------------------------------------------------------- 内部

func _changed() -> void:
	draft.route = null
	draft.failed = []


func _find(list: Array, device_id: String):
	for d in list:
		if d.id == device_id:
			return d
	return null


func _has_def(list: Array, def_id: String) -> bool:
	for d in list:
		if d.def == def_id:
			return true
	return false
