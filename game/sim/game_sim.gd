class_name GameSim
extends Node
## 每家店一个：唯一时钟、唯一中介、唯一 ID 与 RNG 来源。
## 按固定步长、固定顺序推进 5 个业务系统，中转它们之间的请求、结果和事件。
## 不保存任何业务真值的副本；命令的校验和提交写在 commands/ 里。

signal tick_finished(snapshot: Dictionary)
signal sale_settled(sale_id: int, amount: int)
signal command_rejected(command: SimCommand, reason: String)
signal shop_completed()

## 模拟步长（秒），工程常量：每秒 10 步。渲染帧只做插值显示。
const STEP_SECONDS := 0.1
## 一帧最多补跑的模拟秒数。切后台回来时不一口气补完离开的时间（会卡顿，也等于提前有了离线收益）
const MAX_CATCHUP_SECONDS := 0.5

## 只有回归测试会改它，用来验证步长无关（不变量 9）
var step_seconds := STEP_SECONDS
var paused := false

var config: ShopConfig
var production: ProductionSystem
var workforce: WorkforceSystem
var front_hall: FrontHallSystem
var economy: EconomySystem
var progress: ShopProgressSystem
var diagnostics: Diagnostics

var tick := 0
var rng := RandomNumberGenerator.new()
var last_snapshot := {}

var _next_id := 1
var _commands: Array[SimCommand] = []
var _events: Array = []
var _accumulator := 0.0


## roster：本店可用的员工（只读名单，由 App 从 Profile 给出）
func setup(shop_config: ShopConfig, roster: Array[StaffDef]) -> void:
	config = shop_config
	rng.seed = config.random_seed
	production = ProductionSystem.new()
	production.setup(config)
	workforce = WorkforceSystem.new()
	workforce.setup(config, roster)
	front_hall = FrontHallSystem.new()
	front_hall.setup(config, rng)
	economy = EconomySystem.new()
	economy.setup(config)
	progress = ShopProgressSystem.new()
	progress.setup(config)
	diagnostics = Diagnostics.new()
	last_snapshot = SimSnapshot.build(self)


func _process(delta: float) -> void:
	if config == null or paused:
		return
	_accumulator = minf(_accumulator + delta, MAX_CATCHUP_SECONDS)
	while _accumulator >= step_seconds:
		_accumulator -= step_seconds
		step()


## 命令在下一个 tick 的第 1 步执行
func submit(command: SimCommand) -> void:
	_commands.append(command)


func next_id() -> int:
	_next_id += 1
	return _next_id - 1


func elapsed_seconds() -> float:
	return tick * step_seconds


## 命令把需要交给 ShopProgress / Diagnostics 的事件放进本 tick
func push_events(events: Array) -> void:
	_events.append_array(events)


## 后厨是否开放由 ShopProgress 的阶段推导，不另存开关
func validate_kitchen_access() -> String:
	return "" if progress.kitchen_open() else "解锁新菜后开放后厨"


## 只拦涉及后厨机位的命令；前厅机位和前厅传送带在开厨前照常可改
func validate_kitchen_slots(slot_ids: Array) -> String:
	for slot_id in slot_ids:
		if production.in_zone(slot_id, config.kitchen_zone):
			return validate_kitchen_access()
	return ""


## 按 StationDef.owner 找到拥有这个机位的系统
func station_owner(slot_id: String) -> RefCounted:
	if production.has_slot(slot_id):
		return production
	if front_hall.has_slot(slot_id):
		return front_hall
	return null


func step() -> void:
	tick += 1
	var dt := step_seconds
	_events = []
	var new_id := next_id

	# 1. 玩家命令：Validate All → Commit All
	var commands := _commands
	_commands = []
	for command in commands:
		_run_command(command)

	# 2. 物流
	var closed_zone := "" if progress.kitchen_open() else config.kitchen_zone
	push_events(production.advance_logistics(dt, closed_zone))

	# 3. 收集请求 → 派工
	workforce.dispatch(production.open_requests() + front_hall.open_requests())

	# 4. 加工、到货、来客、库存事务、人工进度
	push_events(production.advance_stations(dt, new_id, closed_zone))
	var hall := front_hall.advance(dt, rng, new_id, workforce.claimed_request_ids())
	push_events(hall.events)
	for order_id in hall.cancelled:
		production.release(order_id)
	for need in front_hall.stock_needs():
		if production.reserve(need.order_id, need.item, need.count):
			front_hall.on_reserved(need.order_id, new_id)
	push_events(front_hall.update_stockout())
	# 本 tick 新提出的请求也立刻派工，否则每次交接都会晚一个 tick，步长一变产量就变
	workforce.dispatch(production.open_requests() + front_hall.open_requests())
	var sales := []
	for done_work in workforce.advance(dt):
		var request_id: int = done_work.id
		if production.owns_request(request_id):
			push_events(production.on_work_completed(request_id, done_work.overshoot))
		elif front_hall.owns_request(request_id):
			var done := front_hall.on_work_completed(request_id)
			# 出品台现打的那一杯不在库存里，只有从货架取的才扣预留
			if done.from_stock:
				push_events(production.take_reserved(done.order_id))
			sales.append(done)

	# 5. 结算
	for sale in sales:
		var sale_id := next_id()
		if economy.settle(sale_id, sale.price):
			push_events([{"type": "sold", "dish": sale.dish_id, "amount": sale.price}])
			sale_settled.emit(sale_id, sale.price)

	# 6. 任务与完成度
	var just_completed := progress.advance(dt, _events, economy.revenue)
	diagnostics.record(dt, _events)

	# 7. 快照与信号
	last_snapshot = SimSnapshot.build(self)
	tick_finished.emit(last_snapshot)
	if just_completed:
		shop_completed.emit()


func run_seconds(seconds: float) -> void:
	for i in roundi(seconds / step_seconds):
		step()


func _run_command(command: SimCommand) -> void:
	var reason := command.validate(self)
	if reason != "":
		command_rejected.emit(command, reason)
		return
	command.commit(self)


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	return {
		"shop_id": config.id,
		"tick": tick,
		"next_id": _next_id,
		# 64 位整数存成字符串，避免 JSON 数字丢精度
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
		"production": production.to_dict(),
		"workforce": workforce.to_dict(),
		"front_hall": front_hall.to_dict(),
		"economy": economy.to_dict(),
		"progress": progress.to_dict(),
		"diagnostics": diagnostics.to_dict(),
	}


## 先 setup 同一家店的配置，再读入运行状态
func load_dict(d: Dictionary) -> void:
	assert(String(d.shop_id) == config.id, "存档不是这家店的")
	tick = int(d.tick)
	_next_id = int(d.next_id)
	rng.seed = String(d.rng_seed).to_int()
	rng.state = String(d.rng_state).to_int()
	production.from_dict(d.production)
	workforce.from_dict(d.workforce)
	front_hall.from_dict(d.front_hall)
	economy.from_dict(d.economy)
	progress.from_dict(d.progress)
	diagnostics.from_dict(d.diagnostics)
	last_snapshot = SimSnapshot.build(self)
