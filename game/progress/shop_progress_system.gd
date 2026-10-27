class_name ShopProgressSystem
extends RefCounted
## 已开放的阶段（菜品、可买的后厨设备、可解锁的前厅位）、任务进度、店铺完成度。
## 阶段在累计营业额到门槛时自动开放（基线 §28）。只读 GameSim 传入的事件和累计营业额，不管金币。

const EPS := 0.000001

var _config: ShopConfig

## 已开放到第几阶段（0 = 开店即有的菜）
var stage_index := 0
## 本 tick 刚开放的阶段（GameSim 读完就清），-1 = 没有
var opened_stage := -1
var sold := {}             # dish_id -> 份数
var no_stockout := {}      # dish_id -> 连续不缺货秒数
var stockout := {}         # dish_id -> true
var station_levels := {}   # station def id -> 最高等级
var done_tasks := {}       # task id -> true
var completed := false


func setup(config: ShopConfig) -> void:
	_config = config


## 后厨开没开由阶段推导：已开放的阶段里有后厨设备
func kitchen_open() -> bool:
	return not open_devices().is_empty()


## 已开放、能在设备栏里买的后厨设备
func open_devices() -> Array[String]:
	var out: Array[String] = []
	for i in stage_index + 1:
		out.append_array(_stages()[i].kitchen_devices)
	return out


func unlocked_dishes() -> Array[String]:
	var out: Array[String] = []
	for i in stage_index + 1:
		out.append(_stages()[i].dish_id)
	return out


## tick 第 6 步。返回 true 表示本 tick 店铺刚刚完成。
## menu_stage：前厅菜单已经卖到第几阶段（新菜的线搭好才上菜单），只有上了菜单的菜才累计不缺货时间
func advance(dt: float, events: Array, revenue: int, menu_stage: int) -> bool:
	opened_stage = -1
	while stage_index + 1 < _stages().size() and revenue >= _stages()[stage_index + 1].revenue_threshold:
		stage_index += 1
		opened_stage = stage_index
		no_stockout[_stages()[stage_index].dish_id] = 0.0
	for e in events:
		match e.type:
			"sold":
				sold[e.dish] = int(sold.get(e.dish, 0)) + 1
			"stockout_started":
				stockout[e.dish] = true
				no_stockout[e.dish] = 0.0
			"stockout_ended":
				stockout.erase(e.dish)
			"station_level":
				station_levels[e.station] = maxi(int(station_levels.get(e.station, 1)), int(e.level))
	for i in mini(menu_stage, stage_index) + 1:
		var dish_id := _stages()[i].dish_id
		if not stockout.has(dish_id):
			no_stockout[dish_id] = float(no_stockout.get(dish_id, 0.0)) + dt
	for i in stage_index + 1:
		for task in _stages()[i].tasks:
			if not done_tasks.has(task.id) and _task_met(task):
				done_tasks[task.id] = true
	if completed or stage_index < _stages().size() - 1:
		return false
	for stage in _stages():
		for task in stage.tasks:
			if not done_tasks.has(task.id):
				return false
	completed = true
	return true


## 任务进度 0..1，给表现层显示
func task_progress(task: TaskDef) -> float:
	if done_tasks.has(task.id):
		return 1.0
	if task.amount <= 0.0:
		return 0.0
	return clampf(_task_value(task) / task.amount, 0.0, 1.0)


func to_dict() -> Dictionary:
	var tasks := done_tasks.keys()
	tasks.sort()
	return {
		"stage": stage_index,
		"sold": sold.duplicate(),
		"no_stockout": no_stockout.duplicate(),
		"stockout": stockout.keys(),
		"station_levels": station_levels.duplicate(),
		"done_tasks": tasks,
		"completed": completed,
	}


func from_dict(d: Dictionary) -> void:
	stage_index = int(d.stage)
	sold = SaveUtil.int_dict(d.sold)
	no_stockout = SaveUtil.float_dict(d.no_stockout)
	stockout.clear()
	for dish_id in d.stockout:
		stockout[String(dish_id)] = true
	station_levels = SaveUtil.int_dict(d.station_levels)
	done_tasks.clear()
	for task_id in d.done_tasks:
		done_tasks[String(task_id)] = true
	# 存档之后又加了新菜：菜单不再是全的，店铺回到未完成
	completed = bool(d.completed) and stage_index >= _stages().size() - 1


func _stages() -> Array[ShopStageDef]:
	return _config.progression.stages


func _task_met(task: TaskDef) -> bool:
	return _task_value(task) >= task.amount - EPS


func _task_value(task: TaskDef) -> float:
	match task.condition:
		TaskDef.Condition.SELL_COUNT:
			return float(sold.get(task.target_id, 0))
		TaskDef.Condition.NO_STOCKOUT_SECONDS:
			return float(no_stockout.get(task.target_id, 0.0))
		TaskDef.Condition.STATION_LEVEL:
			return float(station_levels.get(task.target_id, 1))
	return 0.0
