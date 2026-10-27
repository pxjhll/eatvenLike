class_name StationState
extends RefCounted
## 一个机位的运行状态（后厨与前厅工位共用）。只用字符串 id 引用 Def，不复制、不修改 Def。

enum Status { ACTIVE, LOCKED, EMPTY_PARALLEL }
enum Phase { IDLE, WAIT_LOAD, PROCESSING, WAIT_UNLOAD, WAIT_WORK }

var slot_id := ""
var def_id := ""
var status: int = Status.ACTIVE
var level := 1
## 入口缓冲 item_id -> 数量
var inputs := {}
## 出口缓冲 item_id -> 数量
var outputs := {}
var phase: int = Phase.IDLE
## 机器加工进度 0..1（人工进度归 Workforce）
var progress := 0.0
var request_id := -1
var supply_timer := 0.0
## 分流轮流送的下一路
var rr_index := 0


static func create(slot: SlotDef) -> StationState:
	var st := StationState.new()
	st.slot_id = slot.id
	st.def_id = slot.station.id
	if slot.initially_locked:
		st.status = Status.LOCKED
	elif slot.parallel_of != "":
		st.status = Status.EMPTY_PARALLEL
	return st


## 前厅固定位点：开局都是价格牌，点一下才解锁（布局基线决定⑧）
static func create_spot(spot: FrontSpotDef) -> StationState:
	var st := StationState.new()
	st.slot_id = spot.id
	st.def_id = spot.station.id
	st.status = Status.LOCKED
	return st


func speed(def: StationDef) -> float:
	return def.level_speed[level - 1] if level <= def.level_speed.size() else 1.0


func max_level(def: StationDef) -> int:
	return mini(def.level_speed.size(), def.upgrade_costs.size() + 1)


func upgrade_problem(def: StationDef) -> String:
	if status != Status.ACTIVE:
		return "工位未启用"
	if level >= max_level(def):
		return "已达等级上限"
	return ""


func upgrade_cost(def: StationDef) -> int:
	return def.upgrade_costs[level - 1]


func to_dict() -> Dictionary:
	return {
		"slot": slot_id,
		"def": def_id,
		"status": status,
		"level": level,
		"inputs": inputs.duplicate(),
		"outputs": outputs.duplicate(),
		"phase": phase,
		"progress": progress,
		"request": request_id,
		"supply_timer": supply_timer,
		"rr": rr_index,
	}


static func from_dict(d: Dictionary) -> StationState:
	var st := StationState.new()
	st.slot_id = String(d.slot)
	st.def_id = String(d.def)
	st.status = int(d.status)
	st.level = int(d.level)
	st.inputs = SaveUtil.int_dict(d.inputs)
	st.outputs = SaveUtil.int_dict(d.outputs)
	st.phase = int(d.phase)
	st.progress = float(d.progress)
	st.request_id = int(d.request)
	st.supply_timer = float(d.supply_timer)
	st.rr_index = int(d.rr)
	return st
