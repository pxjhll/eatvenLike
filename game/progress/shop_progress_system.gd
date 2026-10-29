class_name ShopProgressSystem
extends RefCounted
## 已解锁菜品、任务进度、店铺完成度（菜单做全 + 任务列表完成）。
## 只读 GameSim 传入的事件和累计营业额，不管金币。

const EPS := 0.000001

var _config: ShopConfig

## 已解锁到第几阶段（0 = 开店即有的菜）
var stage_index := 0
var unlocked_slots: Array[String] = []
var sold := {}             # dish_id -> 份数
var no_stockout := {}      # dish_id -> 连续不缺货秒数
var stockout := {}         # dish_id -> true
var station_levels := {}   # station def id -> 最高等级
var done_tasks := {}       # task id -> true
var completed := false


func setup(config: ShopConfig) -> void:
	_config = config


func kitchen_open() -> bool:
	return stage_index >= _config.kitchen_unlock_stage


func unlocked_dishes() -> Array[String]:
	var out: Array[String] = []
	for i in stage_index + 1:
		out.append(_stages()[i].dish_id)
	return out


func next_stage() -> ShopStageDef:
	var next := stage_index + 1
	return _stages()[next] if next < _stages().size() else null


## UnlockStation 的校验：机位属于下一阶段，且累计营业额到达门槛
func validate_unlock(slot_id: String, revenue: int) -> String:
	var next := stage_index + 1
	if next >= _stages().size():
		return "没有可解锁的阶段"
	var stage: ShopStageDef = _stages()[next]
	if not slot_id in stage.unlock_slots or slot_id in unlocked_slots:
		return "这个机位不在下一阶段的解锁列表里"
	if revenue < stage.revenue_threshold:
		return "累计营业额不足"
	return ""


## 标记机位已解锁；下一阶段的机位都解锁后进入该阶段，返回新阶段下标，否则返回 -1
func mark_unlocked(slot_id: String) -> int:
	unlocked_slots.append(slot_id)
	var stage: ShopStageDef = _stages()[stage_index + 1]
	for s in stage.unlock_slots:
		if not s in unlocked_slots:
			return -1
	stage_index += 1
	no_stockout[stage.dish_id] = 0.0
	return stage_index


## tick 第 6 步。返回 true 表示本 tick 店铺刚刚完成。
func advance(dt: float, events: Array, _revenue: int) -> bool:
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
	for dish_id in unlocked_dishes():
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
		"unlocked_slots": unlocked_slots.duplicate(),
		"sold": sold.duplicate(),
		"no_stockout": no_stockout.duplicate(),
		"stockout": stockout.keys(),
		"station_levels": station_levels.duplicate(),
		"done_tasks": tasks,
		"completed": completed,
	}


func from_dict(d: Dictionary) -> void:
	stage_index = int(d.stage)
	unlocked_slots = SaveUtil.string_array(d.unlocked_slots)
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
