extends "res://game/tea_playtest/tea_playtest_sim.gd"
## Business rules preserve physical goods from collection to service.
const CONFIG = preload("res://content/tea/tea.tres")
## The shop opens its line one machine group at a time.
const PROGRESSION = preload("res://content/tea/art_shop_progression.tres")
## Once milk opens, only this many black teas are kept on the shelf (the rest of the tea goes to milk).
const BLACK_TEA_CAP := 3
## The pot pauses at these points of each brew until someone stirs it.
const STIR_POINTS := [1.0 / 3.0, 2.0 / 3.0]
const STIR_SECONDS := 1.0
## v2: staged line (black tea stage) changed the station and dish shapes.
## v3: belts became bought segments (belts / belt_clock), shipments route by segment id.
## v4: one machine per stage, ingredient boxes, dine-in seats, takeaway sealed at the sealer, customers never leave.
## v5: multiplicative prices with stars, brewer pot sizes and sealer levels; the lemonade stand stops at Lv5.
## v6: flyer level (customer flow upgrade).
## v14: orders keep the seat a customer waits in; the flyer wave, cooldown and customers still to come are saved.
## v7: front and kitchen staff are separate; per-worker training became the front / kitchen upgrade lists.
## v8: kitchen staff follow orders (worker.ticket); the topping machine tops the flavor that was ordered.
## v9: the press table (fruit teas on a black tea base) and its stage; lemonade to go skips the sealer.
## v10: order_ramp (orders seen since each dish / takeaway opened) so new things ease in.
## v11: the takeaway rack on the shelf (stations.pickup): the kitchen carries sealed cups there and
## the front serves only from the shelf and the lemonade stand.
## v12: the kitchen press table and banana tea are gone; lemon tea is pressed at the front from a lemonade
## and opens between the milk station and the topping machine. One conveyor (sealer → takeaway rack) is for sale.
const SAVE_VERSION := 15
## Sealed takeaway cups the rack on the shelf's lower tier holds.
const PICKUP_CAPACITY := 6
## A newly opened dish (and takeaway once the sealer opens) starts at RAMP_START of its order weight
## and reaches full weight after RAMP_ORDERS customers.
const RAMP_START := 0.25
const RAMP_ORDERS := 12
## The press (手打台) lives in its own file so the legacy GameSim (which builds every slot in tea.tres) never sees it.
## It stands at the front: the front hand pours a lemonade and presses lemon into it for a lemon tea.
const PRESS_DEF = preload("res://content/tea/press_table.tres")
## Kitchen staff follow orders from the pot to the shelf (v0.3 process blocks). Off = the shared task pool
## from before, kept as a fallback and for comparison.
const FOLLOW_ORDERS := true
## Ticket stages: tea from the pot, waiting at the mixer, topping, carrying the finished cup out.
const TICKET_STAGES := ["boil", "mix", "topping", "topped"]
## What the lemonade stand's old levels 6–10 cost; v4 saves above Lv5 get it back.
const LEMONADE_V4_COSTS := [20, 30, 40, 55, 75, 110, 150, 210, 295]
## A waiting customer gets impatient, then angry; they never leave (the face just pushes the player to upgrade).
const BOIL_CAPACITY := 12
const MOOD_IMPATIENT := 15.0
const MOOD_ANGRY := 30.0
## A customer waiting in a seat minds the wait half as much as one standing in line.
const SEATED_PATIENCE := 0.5
const ARTS := ["cat", "raccoon", "fox", "rabbit", "gray_cat", "bear"]
const ALIASES := {"cabinet": "supply", "brewer": "boil", "milk_station": "mix", "lemonade_stand": "lemonade", "press_table": "press"}
const RESOURCE_IDS := {"supply": "cabinet", "boil": "brewer", "mix": "milk_station", "topping": "topping", "press": "press_table", "lemonade": "lemonade_stand", "counter": "counter"}
const DISHES := ["lemonade", "black_tea", "plain_milk_tea", "pearl_milk_tea", "coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea", "lemon_tea"]
## Drinks the front makes itself at the lemonade stand: never on the shelf, never sealed.
const FRONT_DISHES := ["lemonade", "lemon_tea"]
const MACHINE_IDS := ["supply", "boil", "mix", "topping", "press", "seal", "lemonade", "counter"]
## Machines whose levels bring more customers (the cabinet and counter do not).
const FLOW_MACHINES := ["lemonade", "boil", "mix", "topping", "press", "seal"]

var roster: Array = []
var revenue := 0
var stage_index := 0
var shelf_stock: Dictionary = {}
var sold_by_dish: Dictionary = {}
var station_levels: Dictionary = {}
var material_levels: Dictionary = {}
var unlocked_stations: Dictionary = {}
## Ingredient boxes in the cabinet (material id -> bought); the cabinet itself is furniture from the start.
var boxes: Dictionary = {}
## Dine-in seats owned, and the customers sitting in them: {"seat", "dish", "left"}.
var seats := 0
## Flyer level (1 to flyer_customers.size()): a free flyer brings that many customers; upgrades add more and cool down faster.
var flyers := 1
## Seconds left of the current flyer wave, and until the next flyer (saved, so a reload never skips the cooldown).
var flyer_wave := 0.0
var flyer_wait := 0.0
## Time since the last flyer customer walked in, and how many of this wave are still on their way.
var flyer_clock := 0.0
var flyer_pending := 0
## How many items of the front / kitchen upgrade lists are bought (bought in order).
var front_upgrades := 0
var kitchen_upgrades := 0
var diners: Array = []
## Customers who arrived since each dish (and "takeaway") opened, capped at RAMP_ORDERS.
var order_ramp: Dictionary = {}
var _flavor_cursor := 0
## Bought conveyor segments (BeltSlotDef ids) and each one's countdown to its next cup.
var belts: Dictionary = {}
var belt_clock: Dictionary = {}
## The free belt mode is gone (2026-10-30); the segment rules stay so they can come back.
const BELTS_IN_GAME := false
## The one segment the game sells (as a dashed frame, like a machine): sealed cups ride to the takeaway rack.
## The one segment the tea shop sells (user 2026-11-04: this shop needs only one belt).
const GAME_BELTS := ["seal_to_shelf"]
var _belt_courier := false
var _rng: RandomNumberGenerator
var follow_orders := FOLLOW_ORDERS
## Playtest tuning knobs (调参面板): multipliers on top of the .tres numbers, 1.0 = as designed.
## Times (seat, customer, boil, mix, seal, topping, press, lemonade) are multiplied; walk, work and price
## multiply speed / skill / sale price. Not part of the shop save; the panel keeps them in its own file.
const TUNE_KEYS := ["seat", "customer", "boil", "mix", "seal", "topping", "press", "lemonade", "walk", "work", "price"]
const TUNE_MIN := 0.25
const TUNE_MAX := 3.0
var tune: Dictionary = {}

func tuned(key: String) -> float:
	return clampf(float(tune.get(key, 1.0)), TUNE_MIN, TUNE_MAX)

func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = CONFIG.random_seed
	if workers.is_empty(): _add_worker()
	roster = workers.duplicate()
	for worker in roster:
		worker.deployed = true
		worker.source = "初始"
	_initialize_shop()
	_seat_at_counter(workers[0])

func _initialize_shop() -> void:
	gold = CONFIG.starting_gold
	revenue = 0
	stage_index = 0
	sold = 0
	elapsed = 0.0
	_accumulator = 0.0
	_generated = 0
	_shelf_reserved_in = 0
	_shelf_reserved_out = 0
	_next_order = 1
	_order_clock = 0.0
	_flavor_cursor = 0
	belts.clear()
	belt_clock.clear()
	shelf_count = 0
	orders.clear()
	belt_items.clear()
	events.clear()
	paused = false
	# Workers always carry by hand; bought belt segments move goods on their own.
	use_belts = false
	_rng.seed = CONFIG.random_seed
	shelf_stock.clear()
	sold_by_dish.clear()
	for dish in DISHES:
		shelf_stock[dish] = 0
		sold_by_dish[dish] = 0
	station_levels.clear()
	unlocked_stations.clear()
	for id in MACHINE_IDS:
		station_levels[id] = 1
		unlocked_stations[id] = id == "counter"
	unlocked_stations.supply = true
	material_levels = {"supply": {"tea_leaf": 1, "milk": 1}, "topping": {"pearl": 1, "coconut": 1, "redbean": 1, "taro": 1}, "press": {"lemon": 1}}
	boxes = {"tea_leaf": false, "milk": false}
	seats = PROGRESSION.seat_start
	flyers = 1
	flyer_wave = 0.0
	flyer_wait = 0.0
	flyer_clock = 0.0
	flyer_pending = 0
	_full_seconds = 0.0
	front_upgrades = 0
	kitchen_upgrades = 0
	diners.clear()
	order_ramp.clear()
	for dish in DISHES: order_ramp[dish] = 0
	order_ramp.takeaway = 0
	for id in ["boil", "mix", "topping", "seal", "pickup"]:
		stations[id] = {"input": {}, "output": {}, "phase": "idle", "progress": 0.0,
			"label": id, "capacity": 6, "processing": 0, "remaining": 0.0,
			"duration": 0.0, "reserved_in": 0, "reserved_out": {}, "work_reserved": false,
			"processing_item": ""}
	stations.boil.input = {"raw": 0}
	# Room for a full pot of up to six cups plus the next pot's leaves.
	stations.boil.capacity = BOIL_CAPACITY
	stations.boil.output = {"tea": 0}
	stations.mix.input = {"tea": 0}
	stations.mix.output = {"plain_milk_tea": 0}
	stations.topping.input = {"plain_milk_tea": 0}
	# The sealer packs takeaway cups of any kitchen drink, one at a time; the kitchen carries
	# them on to the takeaway rack on the shelf, where the front picks them up.
	stations.pickup.capacity = PICKUP_CAPACITY
	for dish in DISHES:
		stations.seal.input[dish] = 0
		stations.seal.output[dish] = 0
		stations.pickup.output[dish] = 0
		if _is_topped(dish): stations.topping.output[dish] = 0

func _make_worker(index: int) -> Dictionary:
	if ARTS[index] == "bear":
		# Reuse the existing carry worker's balance; only the character identity differs.
		var worker := super._make_worker(1)
		worker.merge({"id": 6, "name": "小熊", "art": "bear"}, true)
		return worker
	if ARTS[index] == "gray_cat":
		var worker := super._make_worker(0)
		worker.merge({"id": 5, "name": "小灰猫", "art": "gray_cat"}, true)
		return worker
	if ARTS[index] != "rabbit": return super._make_worker(index)
	return _rabbit()

## The roster may hold several of one animal, so a staff member's id is its own number, not its art.
func _new_staff(art: String, id: int) -> Dictionary:
	var worker := _make_worker(ARTS.find(art))
	worker.id = id
	return worker

func _rabbit() -> Dictionary:
	var worker := super._make_worker(0)
	worker.merge({"id": 4, "name": "小兔子", "art": "rabbit", "role": "speed",
		"speed": 104.0, "capacity": 2, "skill": 1.0}, true)
	return worker

## A fresh shop starts with only the starting worker: staff don't carry over (the next shop gives
## permanent bonuses instead), so everyone else has to be hired again.
func reset_shop() -> void:
	workers.clear()
	var starter: int = roster[0].id
	roster = [roster[0]]
	for worker in roster:
		var fresh := _new_staff(worker.art, worker.id)
		for key in ["name", "level", "speed", "capacity", "skill", "source"]: fresh[key] = worker[key]
		fresh.deployed = worker.id == starter
		worker.clear()
		worker.merge(fresh)
		if worker.deployed: workers.append(worker)
	_initialize_shop()
	_seat_at_counter(worker_by_id(starter))

## The shop opens with one front-of-house worker at the counter.
func _seat_at_counter(worker: Dictionary) -> void:
	worker.post = "counter"
	worker.pos = Layout.POST_POINTS.counter
	worker.assignment_point = Layout.POST_POINTS.counter

func all_workers() -> Array:
	return roster

func worker_by_id(id: int) -> Dictionary:
	for worker in roster:
		if worker.id == id: return worker
	return {}

func acquire_staff(art: String, source: String) -> String:
	if not art in ARTS: return "未知员工类型"
	if source.strip_edges().is_empty(): return "员工来源不能为空"
	# Preferred ids follow animal order; existing duplicate staff may already occupy one.
	var id := ARTS.find(art) + 1
	# Keep the historical duplicate-id floor stable when more animal types are added.
	var next_id := 6
	for owned in roster:
		next_id = maxi(next_id, owned.id + 1)
		if owned.id == id: id = -1
	var worker := _new_staff(art, id if id > 0 else next_id)
	worker.source = source
	worker.deployed = false
	roster.append(worker)
	_event("acquired", "获得员工：" + worker.name)
	return ""

## Front staff (posted at the counter) only serve; kitchen staff (everyone else) only make and carry.
func deployment_error(id: int, post: String = "") -> String:
	var worker := worker_by_id(id)
	if worker.is_empty(): return "未拥有这位员工"
	if worker.deployed: return ""
	return _role_room(post, id)

## Why one more worker can't join the front (post "counter") or the kitchen (any other post), or "".
func _role_room(post: String, exclude_id: int = -1) -> String:
	var front := post == "counter"
	var count := 0
	for worker in workers:
		if worker.id != exclude_id and (worker.post == "counter") == front: count += 1
	if front:
		if count >= front_slots(): return "前台最多 %d 位，前台升级可以加前台位" % front_slots()
		return ""
	if count >= kitchen_slots():
		var more := ""
		for next in range(stage_index + 1, PROGRESSION.stages.size()):
			if PROGRESSION.stages[next].staff_slots > kitchen_slots():
				more = "，解锁%s后可再派 %d 位" % [PROGRESSION.stages[next].line_name, PROGRESSION.stages[next].staff_slots - kitchen_slots()]
				break
		if kitchen_slots() == 0: return "还没有后厨，解锁%s后才能派后厨员工" % PROGRESSION.stages[1].line_name
		return "后厨最多 %d 位员工%s" % [kitchen_slots(), more]
	return ""

## Kitchen staff: each production line opens more room.
## Someone works the kitchen, but every kitchen hand is seated at a machine: nobody carries between stations.
func no_kitchen_carrier() -> bool:
	var kitchen: Array = workers.filter(func(w: Dictionary) -> bool: return w.post != "counter")
	return not kitchen.is_empty() and kitchen.all(func(w: Dictionary) -> bool: return not w.post.is_empty())

func kitchen_slots() -> int:
	return PROGRESSION.stages[stage_index].staff_slots

## Front staff: one at the start, more from the front upgrade list.
func front_slots() -> int:
	return 1 + _bought("front", "slot")

## Everyone who may work in the shop at once.
func staff_slots() -> int:
	return front_slots() + kitchen_slots()

func _shared_post(post: String) -> bool:
	return post == "counter"

func front_staff() -> int:
	return workers.filter(func(worker): return worker.post == "counter").size()

func kitchen_staff() -> int:
	return workers.size() - front_staff()

## Deploying without a post fills the kitchen first, then the counter.
func deploy_worker(id: int, post: String = "") -> String:
	var worker := worker_by_id(id)
	if not worker.is_empty() and not worker.deployed and post.is_empty() and not _role_room("").is_empty() and _role_room("counter").is_empty(): post = "counter"
	var error := deployment_error(id, post)
	if not error.is_empty(): return error
	if worker.deployed: return ""
	worker.deployed = true
	workers.append(worker)
	if post == "counter": _seat_at_counter(worker)
	_event("deployed", worker.name + "已派出")
	return ""

## The counter takes as many front staff as there are front slots; other posts take one.
func post_owner(post: String, exclude_id: int = -1) -> int:
	if post != "counter": return super.post_owner(post, exclude_id)
	var owners: Array = workers.filter(func(worker): return worker.id != exclude_id and worker.post == "counter")
	return owners[0].id if owners.size() >= front_slots() else -1

func _placement_error(id: int, post: String, point: Vector2) -> String:
	var error := deployment_error(id, post)
	if not error.is_empty(): return error
	var worker := worker_by_id(id)
	# Moving between the counter and the kitchen needs room on the other side.
	if worker.deployed and (post == "counter") != (worker.post == "counter"):
		error = _role_room(post, id)
		if not error.is_empty(): return error
	if not post.is_empty() and not Layout.POST_POINTS.has(post): return "无效岗位"
	if not post.is_empty() and not station_unlocked(post): return "请先解锁设备"
	if not post.is_empty() and post_owner(post, id) != -1: return "岗位已有员工"
	if not is_finite(point.x) or not is_finite(point.y): return "无法放置在这里"
	var map := Layout.grid()
	var cell := map.world_to_cell(point, Layout.CELL)
	if not map.contains_cell(cell) or cell in map.blocked_cells: return "无法放置在这里"
	if Layout.path(point, Layout.POINTS.counter).is_empty(): return "无法到达此处"
	return ""

func deploy_at(id: int, post: String, point: Vector2) -> String:
	var target: Vector2 = Layout.POST_POINTS.get(post, point)
	var error := _placement_error(id, post, target)
	if not error.is_empty(): return error
	deploy_worker(id, post)
	return assign_post(id, post, target)

func assign_post(id: int, post: String, destination: Vector2 = Vector2.INF) -> String:
	var worker := worker_by_id(id)
	if worker.is_empty() or not worker.deployed: return "员工尚未派出"
	var target: Vector2 = Layout.POST_POINTS.get(post, worker.pos if destination == Vector2.INF else destination)
	var error := _placement_error(id, post, target)
	if not error.is_empty(): return error
	return super.assign_post(id, post, target)

func recall_worker(id: int) -> String:
	var worker := worker_by_id(id)
	if worker.is_empty(): return "未拥有这位员工"
	if not worker.deployed: return "员工已在待派遣名册"
	_cancel_job(worker)
	worker.post = ""
	worker.deployed = false
	workers.erase(worker)
	_event("recalled", worker.name + "已收回")
	return ""

func hire_cost() -> int:
	return 35 + maxi(0, roster.size() - 1) * 25

## Recruits come as the animal the roster has fewest of, in ARTS order on a tie.
func next_hire_art() -> String:
	var best: String = ARTS[0]
	var fewest := -1
	for art in ARTS:
		var count := 0
		for worker in roster: count += 1 if worker.art == art else 0
		if fewest < 0 or count < fewest:
			best = art
			fewest = count
	return best

func hire() -> bool:
	var price := hire_cost()
	if gold < price: return false
	if not acquire_staff(next_hire_art(), "招募").is_empty(): return false
	gold -= price
	return true

## Per-worker training is gone: the front and kitchen upgrade lists raise everyone on that side.
func train_cost(_id: int) -> int:
	return -1

func train(_id: int) -> bool:
	return false

const STAFF_UPGRADE_NAMES := {"walk": "走路快 +%d%%", "work": "手脚快 +%d%%", "carry": "一次多搬 1 杯", "slot": "多一个前台位"}

func _upgrade_kinds(side: String) -> Array:
	return PROGRESSION.front_upgrade_kinds if side == "front" else PROGRESSION.kitchen_upgrade_kinds

func _upgrade_costs_for(side: String) -> Array:
	return PROGRESSION.front_upgrade_costs if side == "front" else PROGRESSION.kitchen_upgrade_costs

func _upgrades_bought(side: String) -> int:
	return front_upgrades if side == "front" else kitchen_upgrades

## How many upgrades of one kind the side has bought so far (or would have after `bought` items).
func _bought(side: String, kind: String, bought: int = -1) -> int:
	var count := 0
	var kinds := _upgrade_kinds(side)
	for index in mini(_upgrades_bought(side) if bought < 0 else bought, kinds.size()):
		if kinds[index] == kind: count += 1
	return count

func staff_upgrade_name(kind: String) -> String:
	var text: String = STAFF_UPGRADE_NAMES.get(kind, kind)
	if kind == "walk": return text % roundi(PROGRESSION.walk_step * 100)
	if kind == "work": return text % roundi(PROGRESSION.work_step * 100)
	return text

## The next item on a side's list, or {} when it is all bought.
func staff_upgrade_info(side: String) -> Dictionary:
	var index := _upgrades_bought(side)
	var kinds := _upgrade_kinds(side)
	var rows: Array = []
	for i in kinds.size(): rows.append({"name": staff_upgrade_name(kinds[i]), "cost": _upgrade_costs_for(side)[i], "bought": i < index})
	var info := {"side": side, "bought": index, "total": kinds.size(), "rows": rows,
		"walk": pow(1.0 + PROGRESSION.walk_step, _bought(side, "walk")), "work": pow(1.0 + PROGRESSION.work_step, _bought(side, "work")),
		"carry": _bought(side, "carry"), "slots": front_slots() if side == "front" else kitchen_slots()}
	if index >= kinds.size(): return info.merged({"kind": "", "name": "", "cost": -1, "error": "已全部升级"})
	var cost: int = _upgrade_costs_for(side)[index]
	return info.merged({"kind": kinds[index], "name": staff_upgrade_name(kinds[index]), "cost": cost, "error": "" if gold >= cost else "金币不足"})

func buy_staff_upgrade(side: String) -> String:
	if not side in ["front", "kitchen"]: return "未知升级"
	var info := staff_upgrade_info(side)
	if not info.error.is_empty(): return info.error
	gold -= info.cost
	if side == "front": front_upgrades += 1
	else: kitchen_upgrades += 1
	_event("staff_upgrade", ("前台" if side == "front" else "后厨") + info.name)
	return ""

func _canonical(id: String) -> String:
	return ALIASES.get(id, id)

func _definition(id: String):
	var resource_id: String = RESOURCE_IDS.get(_canonical(id), "")
	if resource_id == PRESS_DEF.id: return PRESS_DEF
	for slot in CONFIG.slots:
		if slot.station.id == resource_id: return slot.station
	for spot in CONFIG.front_spots:
		if spot.station.id == resource_id: return spot.station
	return null

func station_unlocked(id: String) -> bool:
	return unlocked_stations.get(_canonical(id), false)

## Each stage opens one machine; the cabinet is furniture and its boxes are bought separately.
const STAGE_MACHINES := [[], ["boil"], ["seal"], ["mix"], ["press"], ["topping"]]

func _unlock_stage(id: String) -> int:
	for stage in STAGE_MACHINES.size():
		if id in STAGE_MACHINES[stage]: return stage
	return 0

func _unlock_error(id: String) -> String:
	if not id in MACHINE_IDS: return "未知设备"
	if station_unlocked(id): return "设备已经解锁"
	var stage := _unlock_stage(id)
	if stage > 0:
		if not station_unlocked("lemonade"): return "请先解锁柠檬水台"
		# Only the very next line is offered, so its price alone paces the unlocks (no revenue gate).
		if stage > stage_index + 1: return "请先解锁" + PROGRESSION.stages[stage - 1].line_name
	if gold < _unlock_cost(id): return "金币不足，需要 %d" % _unlock_cost(id)
	return ""

func _unlock_cost(id: String) -> int:
	if id == "lemonade":
		for spot in CONFIG.front_spots:
			if spot.station.id == "lemonade_stand": return spot.unlock_cost
	if _unlock_stage(id) > 0: return PROGRESSION.stages[_unlock_stage(id)].line_cost
	return 0

func unlock_station(requested: String) -> String:
	var id := _canonical(requested)
	var error := _unlock_error(id)
	if not error.is_empty(): return error
	gold -= _unlock_cost(id)
	var stage := _unlock_stage(id)
	for key in STAGE_MACHINES[stage] if stage > 0 else [id]: unlocked_stations[key] = true
	stage_index = maxi(stage_index, stage)
	if orders.is_empty():
		for unused in 3: _add_order()
	_event("unlocked", station_info(id).name + "已解锁")
	return ""

func station_info_name(id: String) -> String:
	var definition = _definition(id)
	return definition.display_name if definition != null else ("封口机" if id == "seal" else id)

func _box_def(material: String):
	for definition in _definition("supply").materials:
		if definition.id == material: return definition
	return null

## An ingredient box opens once the machine it feeds is unlocked; until then the machine has nothing to work with.
func box_error(material: String) -> String:
	var definition = _box_def(material)
	if definition == null or not boxes.has(material): return "未知原料箱"
	if boxes[material]: return "原料箱已经解锁"
	var machine := _canonical(definition.box_machine)
	if not station_unlocked(machine): return "请先解锁" + station_info_name(machine)
	if gold < definition.box_cost: return "金币不足，需要 %d" % definition.box_cost
	return ""

func unlock_box(material: String) -> String:
	var error := box_error(material)
	if not error.is_empty(): return error
	gold -= _box_def(material).box_cost
	boxes[material] = true
	_event("box_unlocked", _box_def(material).display_name + "箱已解锁")
	return ""

## The box the player should buy next: its machine is open but the box is not.
func pending_box() -> String:
	for material in ["tea_leaf", "milk"]:
		if not boxes[material] and station_unlocked(_canonical(_box_def(material).box_machine)): return material
	return ""

func _mix_ready() -> bool:
	return station_unlocked("mix") and boxes.milk

func _brew_ready() -> bool:
	return station_unlocked("boil") and boxes.tea_leaf

func seat_cost() -> int:
	var index := (seats - PROGRESSION.seat_start) / maxi(1, PROGRESSION.seat_step)
	return PROGRESSION.seat_costs[index] if index >= 0 and index < PROGRESSION.seat_costs.size() else -1

## How long a dine-in customer sits at this stage: short early so seats turn over, longer as the menu grows.
func seat_seconds(stage: int = -1) -> float:
	var seconds: float = PROGRESSION.stages[stage_index if stage < 0 else stage].seat_seconds
	return (seconds if seconds > 0 else PROGRESSION.seat_seconds) * tuned("seat")

func _longest_seat_seconds() -> float:
	var longest := 0.0
	for index in PROGRESSION.stages.size(): longest = maxf(longest, seat_seconds(index))
	# A save made with a longer tuned dine-in time must still load after the knob is turned back.
	return longest / tuned("seat") * TUNE_MAX

func seat_max() -> int:
	return PROGRESSION.seat_start + PROGRESSION.seat_step * PROGRESSION.seat_costs.size()

func seat_error() -> String:
	if not station_unlocked("lemonade"): return "请先解锁柠檬水台"
	if seat_cost() < 0: return "座位已满"
	if gold < seat_cost(): return "金币不足，需要 %d" % seat_cost()
	return ""

func buy_seat() -> String:
	var error := seat_error()
	if not error.is_empty(): return error
	gold -= seat_cost()
	seats = mini(seats + PROGRESSION.seat_step, seat_max())
	_event("seat_added", "加了 %d 个座位" % PROGRESSION.seat_step)
	return ""

## Seats nobody is sitting in, being served to, or queueing for.
func _spare_seats() -> int:
	var waiting := 0
	for order in orders:
		if int(order.get("seat", -1)) < 0 and not order.get("takeaway", false) and not order.reserved: waiting += 1
	return free_seats() - waiting

## Seats neither occupied (eating, or seated and waiting for their order) nor promised to a
## standing dine-in customer whose cup is on its way.
func free_seats() -> int:
	var promised := 0
	for worker in workers:
		if worker.job.is_empty() or worker.job.kind != "serve" or _to_go(worker.job): continue
		if int(_order_by_id(worker.job.order_id).get("seat", -1)) < 0: promised += 1
	return seats - diners.size() - promised - seated_orders()

## Dine-in customers who found a seat on the way in and wait there for their order.
func seated_orders() -> int:
	var count := 0
	for order in orders:
		if int(order.get("seat", -1)) >= 0: count += 1
	return count

func _order_by_id(id: int) -> Dictionary:
	for order in orders:
		if order.id == id: return order
	return {}

## The lowest seat nobody eats at or waits in.
func _first_open_seat() -> int:
	var taken: Array = diners.map(func(diner: Dictionary) -> int: return diner.seat)
	for order in orders:
		if int(order.get("seat", -1)) >= 0: taken.append(int(order.seat))
	var seat := 0
	while seat in taken: seat += 1
	return seat

## A served cup leaves with the customer: sealed takeaway, or a lemonade poured to go.
func _to_go(job: Dictionary) -> bool:
	if job.src in ["seal", "pickup"]: return true
	for order in orders:
		if order.id == job.order_id: return order.get("takeaway", false)
	return false

## 0 calm, 1 impatient, 2 angry.
func order_mood(order: Dictionary) -> int:
	var wait: float = order.wait * (SEATED_PATIENCE if int(order.get("seat", -1)) >= 0 else 1.0)
	return 2 if wait >= MOOD_ANGRY else (1 if wait >= MOOD_IMPATIENT else 0)

## Timed machines (brewer) upgrade speed; the rest raise the price of the cups they touch.
## The cabinet body has no upgrade (its ingredient slots carry the price). Topping keeps speed + flavors.
func _art_mode(definition) -> bool:
	return definition != null and not definition.art_costs.is_empty()

func _upgrade_costs(id: String) -> Array:
	if id == "seal": return PROGRESSION.seal_costs
	var definition = _definition(id)
	if definition == null or id == "supply": return []
	return definition.art_costs if _art_mode(definition) else definition.upgrade_costs

func _max_level(id: String) -> int:
	if id == "seal": return PROGRESSION.seal_costs.size() + 1
	var definition = _definition(id)
	if definition == null: return 1
	if _art_mode(definition) or id == "supply": return _upgrade_costs(id).size() + 1
	return mini(definition.level_speed.size(), definition.upgrade_costs.size() + 1)

func _material_costs(id: String, material: String) -> Array:
	var definition = _definition(id).material(material)
	return definition.art_costs if _art_mode(definition) else definition.upgrade_costs

func _material_max(id: String, material: String) -> int:
	var definition = _definition(id).material(material)
	return definition.art_costs.size() + 1 if _art_mode(definition) else definition.max_level()

func _upgrade_error(id: String) -> String:
	if not id in MACHINE_IDS: return "未知设备"
	if not station_unlocked(id): return "请先解锁设备"
	var definition = _definition(id)
	if (definition == null and id != "seal") or _upgrade_costs(id).is_empty(): return "设备无需升级"
	var level: int = station_levels[id]
	if level >= _max_level(id): return "设备已满级"
	if gold < _upgrade_costs(id)[level - 1]: return "金币不足，需要 %d" % _upgrade_costs(id)[level - 1]
	return ""

func upgrade_station(requested: String) -> String:
	var id := _canonical(requested)
	var error := _upgrade_error(id)
	if not error.is_empty(): return error
	gold -= _upgrade_costs(id)[station_levels[id] - 1]
	station_levels[id] += 1
	_event("upgraded", station_info(id).name + "已升级")
	return ""

func _material_error(id: String, material: String) -> String:
	if not material_levels.has(id) or not material_levels[id].has(material): return "未知配料"
	if not station_unlocked(id): return "请先解锁设备"
	if boxes.has(material) and not boxes[material]: return "请先解锁%s箱" % _definition(id).material(material).display_name
	var definition = _definition(id).material(material)
	if station_levels[id] < definition.unlock_level: return "设备需升到 Lv%d" % definition.unlock_level
	var level: int = material_levels[id][material]
	if level >= _material_max(id, material): return "配料已满级"
	var costs := _material_costs(id, material)
	if gold < costs[level - 1]: return "金币不足，需要 %d" % costs[level - 1]
	return ""

func upgrade_material(requested: String, material: String) -> String:
	var id := _canonical(requested)
	var error := _material_error(id, material)
	if not error.is_empty(): return error
	var definition = _definition(id).material(material)
	gold -= _material_costs(id, material)[material_levels[id][material] - 1]
	material_levels[id][material] += 1
	_event("material_upgraded", definition.display_name + "已升级")
	return ""

func station_info(requested: String) -> Dictionary:
	var id := _canonical(requested)
	var definition = _definition(id)
	var level: int = station_levels.get(id, 1)
	var name: String = definition.display_name if definition != null else ("封口机" if id == "seal" else "未知设备")
	var upgrade_cost := -1
	if level < _max_level(id): upgrade_cost = _upgrade_costs(id)[level - 1]
	var materials: Array = []
	if definition != null:
		for material in definition.materials:
			var mat_level: int = material_levels[id][material.id]
			var mat_costs := _material_costs(id, material.id)
			var mat_max := _material_max(id, material.id)
			var row := {"id": material.id, "name": material.display_name, "level": mat_level,
				"upgrade_cost": mat_costs[mat_level - 1] if mat_level < mat_max else -1,
				"upgrade_error": _material_error(id, material.id), "unlock_level": material.unlock_level,
				"bonus": material.bonus(mat_level), "next_bonus": material.bonus(mat_level + 1) if mat_level < material.max_level() else -1.0,
				"base_price": _base_price(material.item_id)}
			if boxes.has(material.id):
				var machine := _canonical(material.box_machine)
				row.merge({"box": true, "box_unlocked": boxes[material.id], "box_cost": material.box_cost,
					"box_error": box_error(material.id), "box_machine": station_info_name(machine)})
			if _art_mode(material): row.merge(_price_preview(id, material.id, mat_level < mat_max))
			elif row.base_price > 0:
				# Flavor rows preview the real cup price, every other bonus on that cup included.
				row.price_now = _dish_price(material.item_id)
				row.price_next = -1
				if mat_level < mat_max:
					material_levels[id][material.id] += 1
					row.price_next = _dish_price(material.item_id)
					material_levels[id][material.id] -= 1
			materials.append(row)
	var descriptions := {"supply": "店里的原料柜。茶叶箱、牛奶箱跟着机器解锁，升级提高售价", "boil": "人工装料、煮茶、取茶；开局一锅 2 杯，升级轮流加杯和提速", "mix": "自动将茶汤调成原味奶茶；开了以后茶汤分给红茶和奶茶", "topping": "人工加料；升级开放新口味（椰果、红豆、芋泥），每开一种来的客人更多", "press": "前台员工接一杯柠檬水，再亲手捣柠檬，做成柠檬茶；外带不用封口；升级提高柠檬茶售价", "seal": "外带的杯子都要来这里封口；升级封得更快，5 级加一个封口位", "lemonade": "服务员到展示柜现取柠檬水，外带不用封口；升级提高柠檬水售价", "counter": "客人在这里点单取杯。堂食要有空座位，加座位能多坐几位"}
	var effects := {"boil": "煮茶速度", "mix": "售价", "topping": "新口味", "press": "售价", "lemonade": "售价", "seal": "封口速度"}
	var speeds: Array = [1.0]
	if definition != null: speeds = definition.art_speeds if _art_mode(definition) and not definition.art_speeds.is_empty() else definition.level_speed
	var next_flavor := ""
	if definition != null:
		for material in definition.materials:
			if material.unlock_level == level + 1: next_flavor = material.display_name
	var stage := _unlock_stage(id)
	var seating := {}
	# Dine-in seats are bought at the counter.
	if id == "counter":
		seating = {"seats": seats, "seat_max": seat_max(), "diners": diners.size() + seated_orders(), "seat_cost": seat_cost(), "seat_error": seat_error(),
			"flyer_cost": flyer_cost(), "flyer_error": flyer_error(), "flyer_wave": flyer_wave, "flyer_wait": flyer_wait,
			"flyer_seconds": PROGRESSION.flyer_seconds, "flyer_customers": flyer_customers(), "flyer_cooldown": flyer_cooldown(),
			"flyer_level": flyers, "flyer_max": flyer_max_level(), "flyer_upgrade_cost": flyer_upgrade_cost(),
			"flyer_upgrade_error": flyer_upgrade_error(), "flyer_pending": flyer_pending,
			"next_flyer_customers": flyer_customers(flyers + 1), "next_flyer_cooldown": flyer_cooldown(flyers + 1), "flow": flow_multiplier(),
			# A full line means more customers would only wait outside: the kitchen is the limit.
			"queue_full": orders.size() >= _queue_capacity()}
	# Each upgrade does one thing: the machines that hold the line back (brewer, sealer) get faster,
	# the rest make each cup dearer, and the topping machine opens the next flavor (a new dish on the menu).
	seating.kind = "capacity" if id in ["boil", "seal"] else "menu" if id == "topping" else ("price" if id in ["mix", "supply", "press", "lemonade"] else "")
	seating.stars = stars(id)
	seating.max_stars = 2 if id == "seal" else (definition.art_star_levels.size() if definition != null else 0)
	seating.next_star = upgrade_cost >= 0 and stars(id, level + 1) > stars(id)
	seating.star_mult = definition.art_star_mult if definition != null else 1.0
	if id == "boil":
		seating.batch = brew_batch()
		seating.next_batch = brew_batch(level + 1) if upgrade_cost >= 0 else -1
	if id == "seal":
		seating.merge({"slots": seal_slots(), "next_slots": seal_slots(level + 1) if upgrade_cost >= 0 else -1,
			"seconds": seal_seconds(), "next_seconds": seal_seconds(level + 1) if upgrade_cost >= 0 else -1.0}, true)
	var line: Array = []
	if stage > 0:
		for key in STAGE_MACHINES[stage]: line.append(_definition(key).display_name if _definition(key) != null else "封口机")
	return {"id": id, "name": name, "unlocked": station_unlocked(id), "level": level, "stage": stage,
		"description": descriptions.get(id, ""), "unlock_cost": _unlock_cost(id), "unlock_error": _unlock_error(id),
		"upgrade_cost": upgrade_cost, "upgrade_error": _upgrade_error(id), "materials": materials,
		"effect": effects.get(id, ""), "speed": speeds[mini(level, speeds.size()) - 1],
		"next_speed": speeds[level] if upgrade_cost >= 0 and level < speeds.size() else -1.0, "next_unlock": next_flavor,
		"unlock_revenue": 0,
		"line_name": PROGRESSION.stages[stage].line_name if stage > 0 else name, "line_members": line,
		"unlock_note": PROGRESSION.stages[stage].unlock_note if stage > 0 else "",
		"dish_name": dish_name(PROGRESSION.stages[stage].dish_id), "dish_price": _base_price(PROGRESSION.stages[stage].dish_id),
		"price": _price_preview(id, "", upgrade_cost >= 0) if _art_mode(definition) and definition.art_price_step > 0 else {},
		"seconds": definition.art_seconds / speeds[level - 1] if _timed(definition) else -1.0,
		"next_seconds": definition.art_seconds / speeds[level] if _timed(definition) and upgrade_cost >= 0 else -1.0}.merged(seating, true)

## A machine whose levels shorten a timed step (the brewer): price machines keep one fixed time.
func _timed(definition) -> bool:
	return _art_mode(definition) and definition.art_seconds > 0 and not definition.art_speeds.is_empty()

## What one more level is worth, shown on a sample cup the player already sells.
func _price_preview(id: String, material: String, has_next: bool) -> Dictionary:
	var source = _definition(id) if material.is_empty() else _definition(id).material(material)
	var dishes: Array = source.art_price_dishes
	var step: float = source.art_price_step
	var sample := ""
	for dish in ["lemonade", "black_tea", "plain_milk_tea", "lemon_tea"]:
		if dish in dishes: sample = dish
	for dish in ["lemon_tea", "plain_milk_tea", "black_tea", "lemonade"]:
		if dish in dishes and _dish_unlocked(dish):
			sample = dish
			break
	var names: Array = []
	if "lemonade" in dishes: names.append("柠檬水")
	if "black_tea" in dishes: names.append("红茶")
	if "plain_milk_tea" in dishes: names.append("奶茶")
	if "lemon_tea" in dishes: names.append("柠檬茶")
	# Price the next level with the same combined bonus and single rounding as real sales.
	var now := _dish_price(sample)
	var next := -1
	if has_next:
		var levels: Dictionary = station_levels if material.is_empty() else material_levels[id]
		var key := id if material.is_empty() else material
		levels[key] += 1
		next = _dish_price(sample)
		levels[key] -= 1
	return {"scope": "、".join(names), "step": roundi(step * 100), "sample": dish_name(sample), "now": now, "next": next}

func _base_price(dish: String) -> int:
	for definition in CONFIG.dishes:
		if definition.id == dish: return definition.price
	return 0

func goal_progress() -> Dictionary:
	if not station_unlocked("lemonade"): return {"text": "解锁柠檬水台，开始营业", "current": 0, "target": 1}
	var box := pending_box()
	if not box.is_empty(): return {"text": "解锁%s箱" % _box_def(box).display_name, "current": mini(gold, _box_def(box).box_cost), "target": _box_def(box).box_cost}
	if stage_index < PROGRESSION.stages.size() - 1:
		var stage = PROGRESSION.stages[stage_index + 1]
		return {"text": "攒金币 · 解锁" + stage.line_name, "current": mini(gold, stage.line_cost), "target": stage.line_cost}
	for row in task_rows():
		if not row.complete: return {"text": row.name, "current": row.current, "target": row.target}
	return {"text": "经营任务已全部完成", "current": 1, "target": 1}

func dish_name(id: String) -> String:
	for dish in CONFIG.dishes:
		if dish.id == id: return dish.display_name
	return {"raw": "茶叶", "tea": "茶汤"}.get(id, id)

func task_rows() -> Array:
	var rows: Array = []
	for stage in PROGRESSION.stages:
		for task in stage.tasks:
			var current: float = station_levels.get(_canonical(task.target_id), 0) if task.condition == 2 else sold_by_dish.get(task.target_id, 0)
			rows.append({"name": task.display_name, "current": current, "target": task.amount, "complete": current >= task.amount})
	return rows

## Every task of every stage is done: the first shop is complete (the next shop is not built yet).
func shop_complete() -> bool:
	if stage_index < PROGRESSION.stages.size() - 1: return false
	for row in task_rows():
		if not row.complete: return false
	return true

func current_goal() -> String:
	if not station_unlocked("lemonade"): return "支付 10 金币解锁柠檬水台，开始营业"
	var box := pending_box()
	if not box.is_empty(): return "支付 %d 金币在原料柜解锁%s箱" % [_box_def(box).box_cost, _box_def(box).display_name]
	if stage_index < PROGRESSION.stages.size() - 1:
		var stage = PROGRESSION.stages[stage_index + 1]
		return "支付 %d 金币解锁%s" % [stage.line_cost, stage.line_name]
	for row in task_rows():
		if not row.complete: return "%s（%d / %d）" % [row.name, row.current, row.target]
	return "经营任务已全部完成，继续营业"

func _speed(id: String) -> float:
	if id == "seal": return PROGRESSION.seal_speeds[mini(station_levels.seal, PROGRESSION.seal_speeds.size()) - 1]
	var definition = _definition(id)
	if definition == null or id == "supply": return 1.0
	if _art_mode(definition): return 1.0 if definition.art_speeds.is_empty() else definition.art_speeds[station_levels[id] - 1]
	return definition.level_speed[station_levels[id] - 1]

func _material_bonus(id: String, material: String) -> float:
	var definition = _definition(id).material(material)
	return 1.0 if _art_mode(definition) else definition.bonus(material_levels[id][material])

func _machine_duration(key: String) -> float:
	match key:
		"boil":
			var seconds: float = _definition("boil").art_seconds
			return (seconds if seconds > 0 else 7.0) / _speed("boil") / _speed("supply") / _material_bonus("supply", "tea_leaf") * tuned("boil")
		"mix": return 4.0 / _speed("mix") / _material_bonus("supply", "milk") * tuned("mix")
	return seal_seconds()

## Time per takeaway cup at the sealer: faster per level, and each extra slot (stars at Lv5 / Lv10) adds another cup at once.
func seal_seconds(level: int = -1) -> float:
	var lv: int = station_levels.seal if level < 0 else level
	var speed: float = PROGRESSION.seal_speeds[mini(lv, PROGRESSION.seal_speeds.size()) - 1]
	return PROGRESSION.seal_seconds / speed / seal_slots(lv) * tuned("seal")

func seal_slots(level: int = -1) -> int:
	var lv: int = station_levels.seal if level < 0 else level
	return PROGRESSION.seal_slots[mini(lv, PROGRESSION.seal_slots.size()) - 1]

## Cups per pot: the brewer starts with two and odd levels add one (up to six).
func _brew_batch() -> int:
	return brew_batch()

func brew_batch(level: int = -1) -> int:
	var batch: Array = _definition("boil").art_batch
	if batch.is_empty(): return 3
	var lv: int = station_levels.boil if level < 0 else level
	return batch[mini(lv, batch.size()) - 1]

## Star levels a station has reached; each multiplies the price of the drinks it touches.
func stars(id: String, level: int = -1) -> int:
	if id == "seal": return seal_slots(level) - 1
	var definition = _definition(id)
	if definition == null: return 0
	var lv: int = station_levels.get(id, 1) if level < 0 else level
	var count := 0
	for star in definition.art_star_levels:
		if lv >= star: count += 1
	return count

func _action_duration(job: Dictionary, worker: Dictionary) -> float:
	if job.src == "supply" and job.item in FRONT_DISHES:
		# A lemon tea is a lemonade poured at the stand, then pressed with lemon by the same hand.
		var pour: float = _definition("lemonade").cycle_seconds / _speed("lemonade") * tuned("lemonade")
		if job.item == "lemon_tea": pour += PRESS_DEF.art_seconds / _speed("press") * tuned("press")
		return pour / _skill(worker)
	if job.kind == "topping": return _topping_seconds() * job.count / _skill(worker) / _speed("topping") * tuned("topping")
	if job.kind == "stir": return STIR_SECONDS / _skill(worker)
	if job.kind == "load_boil": return 0.6 / _skill(worker) / _speed("supply") / _material_bonus("supply", "tea_leaf")
	return super._action_duration(job, worker)

## Seconds of hand work per cup at the topping machine (its art_seconds; 2 when unset).
func _topping_seconds() -> float:
	var seconds: float = _definition("topping").art_seconds
	return seconds if seconds > 0 else 2.0

func _order_interval() -> float:
	return PROGRESSION.stages[stage_index].customer_interval / flow_multiplier() * tuned("customer")

## Customers come faster with each stage and with each flavor on the menu beyond the first (flavor_flow each).
## level_flow (machine levels) is kept as a switch and is 0: upgrades raise output, not traffic.
## A flyer adds its own customers on top (see _flyer_customers).
func flow_multiplier() -> float:
	var flavors := 0
	for material in _definition("topping").materials:
		if _dish_unlocked(material.item_id): flavors += 1
	return (1.0 + PROGRESSION.flavor_flow * maxi(0, flavors - 1)) * (1.0 + PROGRESSION.level_flow * machine_levels())

## Levels bought on the machines that draw customers (each counts once above Lv1).
func machine_levels() -> int:
	var total := 0
	for id in FLOW_MACHINES:
		if station_unlocked(id): total += station_levels.get(id, 1) - 1
	return total

## Flyers are free: only the cooldown limits them.
func flyer_cost() -> int:
	return 0

func flyer_max_level() -> int:
	return PROGRESSION.flyer_customers.size()

## Customers one flyer brings, and the cooldown, at a flyer level (default: the current one).
func flyer_customers(level: int = -1) -> int:
	var lv := flyers if level < 0 else level
	return PROGRESSION.flyer_customers[clampi(lv, 1, flyer_max_level()) - 1]

func flyer_cooldown(level: int = -1) -> float:
	var lv := flyers if level < 0 else level
	return PROGRESSION.flyer_cooldowns[clampi(lv, 1, PROGRESSION.flyer_cooldowns.size()) - 1]

func flyer_error() -> String:
	if not station_unlocked("lemonade"): return "请先解锁柠檬水台"
	if flyer_wave > 0.0: return "传单正在起效，还有 %d 秒" % ceili(flyer_wave)
	if flyer_wait > 0.0: return "传单还要等 %d 秒才能再发" % ceili(flyer_wait)
	return ""

func buy_flyers() -> String:
	var error := flyer_error()
	if not error.is_empty(): return error
	flyer_wave = PROGRESSION.flyer_seconds
	flyer_wait = flyer_cooldown()
	# Customers of an earlier flyer still waiting outside (the line was full) keep their place.
	flyer_pending += flyer_customers()
	flyer_clock = 0.0
	_event("flyers", "传单发出去了，接下来 %d 秒内来 %d 位客人" % [int(PROGRESSION.flyer_seconds), flyer_pending])
	return ""

func flyer_upgrade_cost() -> int:
	if flyers >= flyer_max_level(): return -1
	return PROGRESSION.flyer_upgrade_costs[flyers - 1]

func flyer_upgrade_error() -> String:
	if not station_unlocked("lemonade"): return "请先解锁柠檬水台"
	var cost := flyer_upgrade_cost()
	if cost < 0: return "传单已升满"
	if gold < cost: return "金币不足，需要 %d" % cost
	return ""

func upgrade_flyers() -> String:
	var error := flyer_upgrade_error()
	if not error.is_empty(): return error
	gold -= flyer_upgrade_cost()
	flyers += 1
	_event("flyer_upgrade", "传单升级：一次招来 %d 位客人，间隔 %d 秒" % [flyer_customers(), int(flyer_cooldown())])
	return ""

## How long the standing line has been full without a break, and smoothed shares (about the last
## 20 seconds) of the brewer brewing and of kitchen / front staff standing idle. Not saved.
var _full_seconds := 0.0
var _boil_busy := 0.0
var _kitchen_idle := 1.0
var _front_idle := 1.0
const HINT_AFTER := 20.0
const HINT_SMOOTH := 0.1 / 20.0

func _track_bottleneck() -> void:
	var full: bool = orders.size() - seated_orders() >= PROGRESSION.stages[stage_index].queue_capacity
	_full_seconds = _full_seconds + STEP if full else 0.0
	var boil: Dictionary = stations.get("boil", {})
	var brewing := 1.0 if not boil.is_empty() and int(boil.processing) > 0 and boil.phase != "awaiting_take" else 0.0
	_boil_busy = lerpf(_boil_busy, brewing, HINT_SMOOTH)
	var idle := {"front": [0, 0], "kitchen": [0, 0]}
	for worker in workers:
		var side := "front" if worker.post == "counter" else "kitchen"
		idle[side][1] += 1
		if worker.job.is_empty(): idle[side][0] += 1
	if idle.kitchen[1] > 0: _kitchen_idle = lerpf(_kitchen_idle, float(idle.kitchen[0]) / idle.kitchen[1], HINT_SMOOTH)
	if idle.front[1] > 0: _front_idle = lerpf(_front_idle, float(idle.front[0]) / idle.front[1], HINT_SMOOTH)

## When the line has stayed full for a while: which drink piles up, what holds it back, and where to
## fix it ("target": a station id, or "staff_front" / "staff_kitchen"). Empty while the line keeps moving.
func bottleneck_hint() -> Dictionary:
	var hint := _bottleneck()
	if not hint.is_empty(): hint.short = "%s排长队 · %s" % [hint.drink, hint.fix]
	return hint

func _bottleneck() -> Dictionary:
	if _full_seconds < HINT_AFTER: return {}
	var waiting := {}
	for order in orders:
		if not order.reserved: waiting[order.dish] = int(waiting.get(order.dish, 0)) + 1
	var top := ""
	for dish in waiting:
		if top.is_empty() or waiting[dish] > waiting[top]: top = dish
	if top.is_empty(): return {}
	var drink := dish_name(top)
	if top in FRONT_DISHES:
		# Front drinks are made by hand at the stand: only more or faster front staff pour them sooner.
		return {"drink": drink, "fix": "升级前台员工", "text": "前台跟不上，%s排起了长队：升级前台员工或多招一位" % drink, "target": "staff_front"}
	if kitchen_staff() <= 0: return {"drink": drink, "fix": "派员工去后厨", "text": "没有后厨员工，%s做不出来：派一位员工去后厨" % drink, "target": "staff_kitchen"}
	if _boil_busy > 0.85: return {"drink": drink, "fix": "升级煮茶机", "text": "%s做不过来，煮茶机一直在煮：升级煮茶机" % drink, "target": "boil"}
	if _kitchen_idle < 0.15: return {"drink": drink, "fix": "升级后厨员工", "text": "后厨跑不过来，%s排起了长队：升级后厨员工或多招一位" % drink, "target": "staff_kitchen"}
	return {"drink": drink, "fix": "升级煮茶机", "text": "%s做不过来：升级煮茶机" % drink, "target": "boil"}

## Room in the standing line. Customers waiting in a seat do not stand in it.
func _queue_capacity() -> int:
	return PROGRESSION.stages[stage_index].queue_capacity + seated_orders()

func _tick() -> void:
	if follow_orders: _drop_stuck_tickets()
	flyer_wait = maxf(0.0, flyer_wait - STEP)
	_flyer_customers()
	super._tick()
	_track_bottleneck()
	_run_belts()
	for index in range(diners.size() - 1, -1, -1):
		diners[index].left -= STEP
		if diners[index].left <= 0.000001: diners.remove_at(index)
	# Customers never leave. Once the sealer is open, someone who wants to sit but finds no seat takes it away.
	if station_unlocked("seal"):
		var free := free_seats()
		for order in orders:
			if order.reserved or order.get("takeaway", false) or int(order.get("seat", -1)) >= 0: continue
			if free > 0: free -= 1
			else: order["takeaway"] = true

func _shelf_capacity() -> int:
	# ShopConfig defines capacity per item, while the base audit needs a total.
	var flavors := 0
	for dish in DISHES:
		if _is_kitchen_dish(dish) and _dish_unlocked(dish): flavors += 1
	return dish_cap() * maxi(1, flavors)

func shelf_limit() -> int:
	return _shelf_capacity()

func _shelf_item_free(item: String) -> int:
	var committed: int = shelf_stock.get(item, 0)
	for worker in workers:
		if worker.job.is_empty() or _shelf_item(worker.job.item) != item: continue
		if worker.job.dst == "shelf": committed += worker.job.count
		# Carried service cups retain their original shelf slot until delivery,
		# allowing a recall to return exactly that flavor without overflowing it.
		if worker.job.src == "shelf": committed += worker.carry_count
	for shipment in belt_items:
		if shipment.dst == "shelf" and shipment.item == item: committed += shipment.count
	return dish_cap() - committed

## Cups of one drink the shelf holds. Following orders, every cup is made for someone in line, so it holds a full line.
func dish_cap() -> int:
	return maxi(CONFIG.shelf_capacity, _queue_capacity()) if follow_orders else CONFIG.shelf_capacity

func _candidate(kind: String, source: String, destination: String, item: String, worker: Dictionary, priority: float, belt: String = "") -> Dictionary:
	var job := super._candidate(kind, source, destination, item, worker, priority, belt)
	if not job.is_empty() and destination == "shelf":
		job.count = mini(job.count, _shelf_item_free(_shelf_item(item)))
		if job.count <= 0: return {}
	return job

func _dish_unlocked(dish: String, needs_kitchen_hand := true) -> bool:
	if dish == "lemonade": return station_unlocked("lemonade")
	if dish == "lemon_tea": return station_unlocked("lemonade") and station_unlocked("press")
	# Kitchen drinks go on the menu only once someone works the kitchen. Customers never leave, so
	# orders nobody can make would fill the queue, stop lemonade sales and leave no money to hire.
	if needs_kitchen_hand and kitchen_staff() <= 0: return false
	if dish == "black_tea": return _brew_ready()
	# Every milk tea needs the whole chain: brewed tea (brewer + tea leaf box) and milk (mixer + milk box).
	if dish == "plain_milk_tea": return _brew_ready() and _mix_ready()
	for material in _definition("topping").materials:
		if material.item_id == dish: return _brew_ready() and _mix_ready() and station_unlocked("topping") and station_levels.topping >= material.unlock_level
	return false

## How far a new dish (or takeaway) has eased in: RAMP_START right after it opens, 1.0 after RAMP_ORDERS customers.
func ramp(key: String) -> float:
	return lerpf(RAMP_START, 1.0, clampf(float(order_ramp.get(key, 0)) / RAMP_ORDERS, 0.0, 1.0))

## This stage's order weight for each dish on the menu, new dishes scaled down while they ease in.
func order_weights() -> Dictionary:
	var result := {}
	var weights: Dictionary = PROGRESSION.stages[stage_index].order_weights
	for dish in weights:
		if _dish_unlocked(dish): result[dish] = weights[dish] * ramp(dish)
	return result

func takeaway_share() -> float:
	return PROGRESSION.stages[stage_index].takeaway_share * ramp("takeaway")

func _add_order() -> void:
	if _rng == null or not station_unlocked("lemonade"): return
	var weights := order_weights()
	var total := 0.0
	for dish in weights: total += weights[dish]
	if total <= 0: return
	var sample := _rng.randf() * total
	var selected := "lemonade"
	for dish in weights:
		sample -= weights[dish]
		if sample <= 0:
			selected = dish
			break
	# Customers would rather sit down: one who finds a free seat sits and orders from there. With every
	# seat taken they stand in line, and once the sealer is open they take the drink to go instead.
	var spare := _spare_seats()
	var seat := _first_open_seat() if spare > 0 else -1
	var takeaway := station_unlocked("seal") and spare <= 0
	for dish in weights: order_ramp[dish] = mini(int(order_ramp.get(dish, 0)) + 1, RAMP_ORDERS)
	if station_unlocked("seal"): order_ramp.takeaway = mini(int(order_ramp.get("takeaway", 0)) + 1, RAMP_ORDERS)
	orders.append({"id": _next_order, "wait": 0.0, "reserved": false, "dish": selected, "takeaway": takeaway, "seat": seat})
	_next_order += 1

## While a flyer works, its customers walk in one by one, spread over flyer_seconds, and order from the
## whole menu like anyone else. One who finds the line full waits outside and comes in when there is room.
func _flyer_customers() -> void:
	if flyer_wave > 0.0: flyer_wave = maxf(0.0, flyer_wave - STEP)
	if flyer_pending <= 0: return
	flyer_clock += STEP
	if flyer_clock < PROGRESSION.flyer_seconds / maxf(1.0, float(flyer_customers())): return
	if orders.size() >= _queue_capacity(): return
	flyer_clock = 0.0
	flyer_pending -= 1
	_add_order()

func _source_point(job: Dictionary) -> Vector2:
	# Lemonade and lemon tea are poured (and pressed) at the stand.
	if job.item in FRONT_DISHES and job.src == "supply": return Layout.POINTS.lemonade
	# The takeaway rack is the shelf's lower tier: picked up where the shelf is.
	if job.src == "pickup": return Layout.POINTS.shelf
	return super._source_point(job)

func _destination_point(job: Dictionary) -> Vector2:
	if job.dst == "pickup": return Layout.POINTS.shelf
	return super._destination_point(job)

func _available(source: String, item: String) -> int:
	if source == "supply": return 999
	if source == "shelf":
		var reserved := 0
		for worker in workers:
			if not worker.job.is_empty() and worker.job.src == "shelf" and worker.job.item == item and worker.carry_count == 0: reserved += worker.job.count
		return int(shelf_stock.get(item, 0)) - reserved
	var station: Dictionary = stations[source]
	var stock: Dictionary = station.input if _input_item(source, item) else station.output
	return int(stock.get(item, 0)) - int(station.reserved_out.get(item, 0))

## Items a station keeps in its input until a hand works them: leaves in the pot, plain milk tea at the topping machine.
func _input_item(station: String, item: String) -> bool:
	return (station == "boil" and item == "raw") or (station == "topping" and item == "plain_milk_tea")

func _jobs(worker: Dictionary) -> Array:
	var result: Array = []
	if worker.assignment_pending: return result
	for post in ["boil", "topping"]:
		if not station_unlocked(post) or (not worker.post.is_empty() and worker.post != post): continue
		if post_owner(post, worker.id) != -1: continue
		var station: Dictionary = stations[post]
		if station.work_reserved: continue
		var kind := ""
		var item := "raw" if post == "boil" else "plain_milk_tea"
		var count := 0
		if post == "topping" and _available(post, item) > 0:
			kind = "topping"
			count = mini(_carry(worker), mini(_available(post, item), 999 if follow_orders else _topping_room()))
		elif post == "boil" and station.processing == 0 and _available(post, "raw") >= _brew_batch():
			kind = "brew_start"
			count = _brew_batch()
		elif post == "boil" and station.phase == "stir":
			kind = "stir"
			count = station.processing
			item = "tea"
		elif post == "boil" and station.phase == "awaiting_take" and station.processing > 0:
			kind = "brew_take"
			count = station.processing
			item = "tea"
		if not kind.is_empty() and count > 0: result.append({"kind": kind, "src": post, "dst": post, "item": item, "count": count, "priority": {"topping": 72.0, "stir": 80.0}.get(kind, 55.0), "belt": "", "order_id": -1})
	if follow_orders and worker.post in ["topping", "boil"]: return _follow_seated(worker, result)
	if worker.post == "topping": return _topping_segment(worker, result)
	if worker.post == "boil": return _boil_segment(worker, result)
	if not worker.post.is_empty() and worker.post != "counter": return result
	# Bought belts (old saves, tests) still move goods by the task-pool rules.
	if worker.post.is_empty(): return _follow_jobs(worker, result) if follow_orders and not _belt_courier else _kitchen_jobs(worker, result)
	# Front staff only serve: lemonade and lemon tea from the stand, cups from the shelf, sealed takeaway from the rack on the shelf.
	var seats_left := free_seats()
	for order in orders:
		if order.reserved: continue
		# Sealed takeaway cups wait on the shelf's takeaway rack; dine-in cups need a free seat.
		# Lemonade and lemon tea are made at the stand and handed over unsealed, to go or not
		# (a lemonade an old save left sealed goes first).
		var source: String = "pickup" if order.get("takeaway", false) else "shelf"
		if order.dish in FRONT_DISHES: source = "pickup" if order.get("takeaway", false) and _available("pickup", order.dish) > 0 else "supply"
		var standing_dine_in: bool = not order.get("takeaway", false) and int(order.get("seat", -1)) < 0
		if standing_dine_in and seats_left <= 0: continue
		var serve := _candidate("serve", source, "counter", order.dish, worker, 110)
		if serve.is_empty(): continue
		if standing_dine_in: seats_left -= 1
		serve.count = 1
		serve.order_id = order.id
		serve.priority += minf(20, order.wait * 0.1)
		result.append(serve)
	return result

## Kitchen staff make drinks and carry takeaway cups to the sealer; they never serve customers.
func _kitchen_jobs(worker: Dictionary, result: Array) -> Array:
	_append_pack_jobs(worker, result)
	if not station_unlocked("boil"): return result
	if post_owner("boil") == -1 or _belt_courier: _append_boil_hops(worker, result)
	if not _mix_ready(): return _boost_kitchen(result)
	if station_unlocked("topping"):
		var original_need := false
		for order in orders:
			if order.dish == "plain_milk_tea" and not order.reserved: original_need = true
		if original_need and _flavor_inventory("plain_milk_tea") < 1:
			var original := _candidate("carry_to_shelf", "mix", "shelf", "plain_milk_tea", worker, 68)
			if not original.is_empty(): original.count = 1
			result.append(original)
		if _topping_segment_open(): result.append(_candidate("transfer_to_topping", "mix", "topping", "plain_milk_tea", worker, 62))
	else:
		result.append(_candidate("carry_to_shelf", "mix", "shelf", "plain_milk_tea", worker, 84))
	if _topping_segment_open():
		for dish in DISHES:
			if _is_topped(dish): result.append(_candidate("carry_to_shelf", "topping", "shelf", dish, worker, 84))
	return _boost_kitchen(result)

## Takeaway cups still to be packed for each drink: waiting takeaway orders minus cups already at or headed to the sealer.
func _pack_need(dish: String) -> int:
	var need := 0
	for order in orders:
		if order.get("takeaway", false) and not order.reserved and order.dish == dish: need += 1
	return need - _sealed_supply(dish)

## Takeaway cups of a drink already packed or on their way: headed to or at the sealer, carried to the rack, or on it.
func _sealed_supply(dish: String) -> int:
	var seal: Dictionary = stations.seal
	var pickup: Dictionary = stations.pickup
	var count: int = int(seal.input[dish]) + int(seal.output[dish]) - int(seal.reserved_out.get(dish, 0))
	count += int(pickup.output[dish]) - int(pickup.reserved_out.get(dish, 0))
	if seal.processing_item == dish: count += seal.processing
	count += _riding_to_pickup(dish)
	for other in workers:
		if other.job.is_empty() or _shelf_item(other.job.item) != dish: continue
		if other.job.kind in ["carry_to_seal", "carry_to_pickup"]: count += other.job.count
	return count

## Sealed cups of a drink on the conveyor to the takeaway rack: already packed, just not there yet.
func _riding_to_pickup(dish: String) -> int:
	var count := 0
	for shipment in belt_items:
		if shipment.dst == "pickup" and shipment.item == dish: count += shipment.count
	return count

## A takeaway cup is fetched from the shelf and carried to the sealer; sealed cups go on to the
## takeaway rack on the shelf, the only place the front picks them up.
func _append_pack_jobs(worker: Dictionary, result: Array) -> void:
	if not station_unlocked("seal"): return
	# Once the conveyor is bought it carries sealed cups to the rack; staff leave that hop alone.
	if _belt_courier or not _belted("seal", "pickup"):
		for dish in DISHES:
			result.append(_candidate("carry_to_pickup", "seal", "pickup", dish, worker, 105))
	for dish in DISHES:
		if not _is_kitchen_dish(dish): continue
		var need := _pack_need(dish)
		if need <= 0: continue
		var job := _candidate("carry_to_seal", "shelf", "seal", dish, worker, 100)
		if job.is_empty(): continue
		job.count = mini(job.count, need)
		result.append(job)

func _append_boil_hops(worker: Dictionary, result: Array) -> void:
	if boxes.tea_leaf: result.append(_candidate("load_boil", "supply", "boil", "raw", worker, 26))
	if _mix_ready():
		result.append(_candidate("unload_boil", "boil", "mix", "tea", worker, 47))
		# Tea is split between black tea and the milk machine; customers waiting on black tea come first,
		# otherwise a line full of black tea orders would starve while the shelf fills with milk tea.
		var waiting := _waiting("black_tea")
		var short: bool = waiting > _flavor_inventory("black_tea")
		var room := maxi(BLACK_TEA_CAP, waiting) - _flavor_inventory("black_tea")
		var black := _candidate("carry_to_shelf", "boil", "shelf", "tea", worker, 95 if short else 50)
		if room <= 0: black = {}
		elif not black.is_empty(): black.count = mini(black.count, room)
		result.append(black)
	else:
		result.append(_candidate("carry_to_shelf", "boil", "shelf", "tea", worker, 84))

# A worker seated at the brewer loads tea leaves, brews, stirs and carries the tea on.
func _boil_segment(worker: Dictionary, result: Array) -> Array:
	_append_boil_hops(worker, result)
	return _boost_kitchen(_without_belted(result))

# A worker seated at the topping machine runs its whole segment: fetching plain
# milk tea from the mixer, adding toppings, and carrying finished cups to the shelf.
func _topping_segment(worker: Dictionary, result: Array) -> Array:
	result.append(_candidate("transfer_to_topping", "mix", "topping", "plain_milk_tea", worker, 62))
	for dish in DISHES:
		if _is_topped(dish): result.append(_candidate("carry_to_shelf", "topping", "shelf", dish, worker, 84))
	return _boost_kitchen(_without_belted(result))

const SEATED_BONUS := 1.3

func _side(worker: Dictionary) -> String:
	return "front" if worker.post == "counter" else "kitchen"

func _walk_speed(worker: Dictionary) -> float:
	return worker.speed * (SEATED_BONUS if worker.post in ["topping", "boil"] else 1.0) * pow(1.0 + PROGRESSION.walk_step, _bought(_side(worker), "walk")) * tuned("walk")

func _skill(worker: Dictionary) -> float:
	return worker.skill * (SEATED_BONUS if worker.post in ["topping", "boil"] else 1.0) * pow(1.0 + PROGRESSION.work_step, _bought(_side(worker), "work")) * tuned("work")

func _carry(worker: Dictionary) -> int:
	return worker.capacity + _bought(_side(worker), "carry")

# Mobile staff leave the topping segment's hops to whoever is seated there.
func _topping_segment_open() -> bool:
	return post_owner("topping") == -1 or _belt_courier

func _post_job(post: String, job: Dictionary) -> bool:
	if _is_operation(job): return job.src == post
	if post == "boil": return job.kind == "load_boil" or (job.kind in ["unload_boil", "carry_to_shelf"] and job.src == "boil")
	return post == "topping" and ((job.kind == "transfer_to_topping") or (job.kind == "carry_to_shelf" and job.src == "topping"))

# Customers waiting on an empty shelf flavor pull mobile staff back into the kitchen;
# otherwise a lone worker serving lemonade would never start the new line.
func _boost_kitchen(result: Array) -> Array:
	var starving := 0
	for order in orders:
		if not order.reserved and _is_kitchen_dish(order.dish) and shelf_stock.get(order.dish, 0) == 0: starving += 1
	if starving == 0: return result
	for job in result:
		if not job.is_empty() and job.kind != "serve": job.priority += minf(90.0, 45.0 * starving)
	return result

# ---- Following orders (process blocks v0.3) ----
# A kitchen hand takes the oldest order nobody is making yet (and the orders right behind it for the
# same drink, as many as they can carry) and follows those cups from the pot to the shelf or sealer.
# The pot is shared stock: loading leaves, starting, stirring and emptying it are jobs for whoever is free,
# or for a follower waiting there on empty tea.

func _is_kitchen_dish(dish: String) -> bool:
	return dish in DISHES and not dish in FRONT_DISHES

func _is_topped(dish: String) -> bool:
	for material in _definition("topping").materials:
		if material.item_id == dish: return true
	return false

## Kitchen drinks for each dish that are already made or being followed, and not yet promised to a customer.
func _kitchen_supply() -> Dictionary:
	var supply := {}
	for dish in DISHES:
		supply[dish] = 0
		if not _is_kitchen_dish(dish): continue
		var seal: Dictionary = stations.seal
		var pickup: Dictionary = stations.pickup
		supply[dish] += maxi(0, _available("shelf", dish)) + int(seal.input[dish]) + int(seal.output[dish]) - int(seal.reserved_out.get(dish, 0))
		supply[dish] += int(pickup.output[dish]) - int(pickup.reserved_out.get(dish, 0))
		if seal.processing_item == dish: supply[dish] += seal.processing
		supply[dish] += _riding_to_pickup(dish)
	for worker in workers:
		if not worker.ticket.is_empty(): supply[worker.ticket.dish] += worker.ticket.count
		elif not worker.job.is_empty() and worker.job.kind == "carry_to_seal" and worker.job.src == "shelf": supply[worker.job.item] += worker.job.count
		elif not worker.job.is_empty() and worker.job.kind == "carry_to_pickup": supply[worker.job.item] += worker.job.count
	return supply

## Orders in line (oldest first) that no cup on hand or in the making covers yet.
func open_orders() -> Array:
	var supply := _kitchen_supply()
	var result: Array = []
	for order in orders:
		if order.reserved or not _is_kitchen_dish(order.dish): continue
		if supply[order.dish] > 0: supply[order.dish] -= 1
		else: result.append(order)
	return result

## Cups at a station nobody's ticket is waiting for (left over after a recall, say).
func _loose(station: String, dish: String = "") -> int:
	var count := 0
	var waiting := 0
	if station == "mix":
		count = int(stations.mix.input.tea) + int(stations.mix.output.plain_milk_tea) - int(stations.mix.reserved_out.get("plain_milk_tea", 0)) + stations.mix.processing
		for worker in workers:
			if not worker.ticket.is_empty() and worker.ticket.stage == "mix" and (worker.job.is_empty() or worker.job.src != "mix"): waiting += worker.ticket.count
	elif dish.is_empty():
		# Plain milk tea already at the topping machine.
		count = int(stations.topping.input.plain_milk_tea) - int(stations.topping.reserved_out.get("plain_milk_tea", 0))
		for worker in workers:
			if not worker.ticket.is_empty() and worker.ticket.stage == "topping" and worker.job.is_empty(): waiting += worker.ticket.count
	else:
		count = int(stations.topping.output.get(dish, 0)) - int(stations.topping.reserved_out.get(dish, 0))
		for worker in workers:
			if worker.ticket.is_empty() or worker.ticket.dish != dish or not worker.ticket.stage in ["topping", "topped"]: continue
			if worker.job.is_empty() or worker.job.kind == "topping": waiting += worker.ticket.count
	return count - waiting

func _start_stage(dish: String, count: int) -> String:
	if _is_topped(dish) and _loose("topping", dish) >= count: return "topped"
	if _is_topped(dish) and _loose("topping") >= count: return "topping"
	if dish != "black_tea" and _loose("mix") >= count: return "mix"
	return "boil"

## The job of exactly `count` cups, or nothing if fewer are ready.
func _exact(job: Dictionary, count: int) -> Dictionary:
	if job.is_empty() or job.count < count: return {}
	job.count = count
	return job

## The last hop: takeaway cups still missing at the sealer go there, the rest to the shelf.
func _final_job(source: String, item: String, dish: String, count: int, worker: Dictionary) -> Dictionary:
	if station_unlocked("seal") and _pack_need(dish) >= count:
		var job := _exact(_candidate("carry_to_seal", source, "seal", item, worker, 95), count)
		if not job.is_empty(): return job
	return _exact(_candidate("carry_to_shelf", source, "shelf", item, worker, 95), count)

## The next step of a ticket, or nothing while its cups aren't ready.
func _ticket_job(worker: Dictionary, ticket: Dictionary) -> Dictionary:
	var dish: String = ticket.dish
	var count: int = ticket.count
	match ticket.stage:
		"boil":
			if dish == "black_tea": return _final_job("boil", "tea", dish, count, worker)
			return _exact(_candidate("unload_boil", "boil", "mix", "tea", worker, 95), count)
		"mix":
			if dish == "plain_milk_tea": return _final_job("mix", "plain_milk_tea", dish, count, worker)
			return _exact(_candidate("transfer_to_topping", "mix", "topping", "plain_milk_tea", worker, 95), count)
		"topping":
			# A seated hand tops it; the follower waits and carries it out.
			if post_owner("topping") != -1: return _final_job("topping", dish, dish, count, worker)
			if stations.topping.work_reserved or _available("topping", "plain_milk_tea") < count: return {}
			return {"kind": "topping", "src": "topping", "dst": "topping", "item": "plain_milk_tea", "count": count, "priority": 95.0, "belt": "", "order_id": -1}
		"topped": return _final_job("topping", dish, dish, count, worker)
	return {}

func _new_ticket_job(worker: Dictionary, pot: Array) -> Dictionary:
	var open := open_orders()
	if open.is_empty(): return {}
	var dish: String = open[0].dish
	var count := 0
	for order in open:
		if order.dish != dish or count >= _carry(worker): break
		count += 1
	var ticket := {"dish": dish, "count": count, "stage": _start_stage(dish, count), "wait": 0.0}
	var job := _ticket_job(worker, ticket)
	if job.is_empty() and ticket.stage == "boil":
		# No tea ready yet: take the order anyway and start by getting the pot going.
		for option in pot:
			if not option.is_empty() and (job.is_empty() or option.priority > job.priority): job = option.duplicate()
	if job.is_empty(): return {}
	job.priority = 90.0 + minf(20.0, open[0].wait * 0.1)
	job["ticket"] = ticket
	return job

## Tea the pot still owes: followers waiting there and open orders, against tea brewing or ready.
func _tea_short() -> bool:
	var need := 0
	for worker in workers:
		if not worker.ticket.is_empty() and worker.ticket.stage == "boil": need += worker.ticket.count
	for order in open_orders():
		if _start_stage(order.dish, 1) == "boil": need += 1
	return int(stations.boil.output.tea) - int(stations.boil.reserved_out.get("tea", 0)) + stations.boil.processing < need

func _pot_jobs(worker: Dictionary, result: Array) -> Array:
	var short := _tea_short()
	var jobs: Array = []
	for job in result:
		if job.is_empty() or not job.kind in ["brew_start", "stir", "brew_take"]: continue
		if short: job.priority += 30.0
		jobs.append(job)
	if boxes.tea_leaf:
		jobs.append(_candidate("load_boil", "supply", "boil", "raw", worker, 70.0 if short else 26.0))
	return jobs

func _follow_jobs(worker: Dictionary, result: Array) -> Array:
	if not station_unlocked("boil"):
		var packs: Array = []
		_append_pack_jobs(worker, packs)
		return packs
	var pot := _pot_jobs(worker, result) if post_owner("boil") == -1 else []
	if not worker.ticket.is_empty():
		var job := _ticket_job(worker, worker.ticket)
		if not job.is_empty(): return [job]
		# Waiting on empty tea: lend a hand at the pot. Anywhere else the follower just waits.
		return pot if worker.ticket.stage == "boil" else []
	var jobs: Array = pot
	_append_pack_jobs(worker, jobs)
	jobs.append(_new_ticket_job(worker, pot))
	return jobs

## Seated hands: at the brewer they keep the pot going, at the topping machine they top what followers bring.
func _follow_seated(worker: Dictionary, result: Array) -> Array:
	if worker.post == "boil": return _pot_jobs(worker, result)
	# One cup at a time, so each cup gets the flavor its follower is waiting for.
	var jobs := result.filter(func(job: Dictionary) -> bool: return not job.is_empty() and job.kind == "topping" and not _seated_flavor().is_empty())
	for job in jobs: job.count = 1
	return jobs

## The flavor a seated topping hand makes next: what the waiting followers ordered, oldest first.
func _seated_flavor() -> String:
	var made := {}
	for worker in workers:
		if worker.ticket.is_empty() or worker.ticket.stage != "topping": continue
		# Already carrying (or about to carry) their finished cups out.
		if not worker.job.is_empty() and worker.job.src == "topping": continue
		var dish: String = worker.ticket.dish
		if not made.has(dish): made[dish] = int(stations.topping.output.get(dish, 0)) - int(stations.topping.reserved_out.get(dish, 0))
		made[dish] -= worker.ticket.count
		if made[dish] < 0: return dish
	return ""

func _reserve(worker: Dictionary, job: Dictionary) -> void:
	var ticket: Dictionary = job.get("ticket", {})
	job.erase("ticket")
	if follow_orders and job.kind == "topping":
		var flavor: String = ticket.get("dish", worker.ticket.get("dish", ""))
		stations.topping.processing_item = flavor if not flavor.is_empty() else _seated_flavor()
	super._reserve(worker, job)
	if not ticket.is_empty(): worker.ticket = ticket

func _finish(worker: Dictionary) -> void:
	var job: Dictionary = worker.job
	if not worker.ticket.is_empty() and not job.is_empty():
		var ticket: Dictionary = worker.ticket
		var done := false
		match ticket.stage:
			"boil":
				if job.src == "boil" and not _is_operation(job):
					if ticket.dish == "black_tea": done = true
					else: ticket.stage = "mix"
			"mix":
				if job.src == "mix":
					if ticket.dish == "plain_milk_tea": done = true
					else: ticket.stage = "topping"
			"topping":
				if job.kind == "topping": ticket.stage = "topped"
				elif job.src == "topping": done = true
			"topped":
				if job.src == "topping" and not _is_operation(job): done = true
		ticket.wait = 0.0
		if done: worker.ticket = {}
	super._finish(worker)

## A follower stuck past the pot for this long (its cups were used up by someone else) lets the order go;
## the order opens again and whatever cups are left get picked up by the next follower.
const TICKET_GIVE_UP := 30.0

func _drop_stuck_tickets() -> void:
	for worker in workers:
		if worker.ticket.is_empty() or not worker.job.is_empty() or worker.ticket.stage == "boil": continue
		worker.ticket.wait += STEP
		if worker.ticket.wait >= TICKET_GIVE_UP: worker.ticket = {}

func _belt_def(id: String):
	for definition in PROGRESSION.belts:
		if definition.id == id: return definition
	return null

func _belted(source: String, destination: String) -> bool:
	for id in belts:
		var definition = _belt_def(id)
		if definition.from == source and definition.to == destination: return true
	return false

# A bought segment owns its hop: staff stop hand-carrying along it.
func _without_belted(result: Array) -> Array:
	if _belt_courier: return result
	return result.filter(func(job: Dictionary) -> bool:
		return job.is_empty() or job.kind == "serve" or _is_operation(job) or not _belted(job.src, job.dst))

func belt_error(id: String) -> String:
	var definition = _belt_def(id)
	if definition == null: return "未知传送带"
	if belts.has(id): return "这里已经装了传送带"
	if not station_unlocked("lemonade") or stage_index < definition.stage: return "请先解锁" + PROGRESSION.stages[definition.stage].line_name
	if gold < definition.cost: return "金币不足，需要 %d" % definition.cost
	return ""

func buy_belt(id: String) -> String:
	var error := belt_error(id)
	if not error.is_empty(): return error
	var definition = _belt_def(id)
	gold -= definition.cost
	belts[id] = true
	belt_clock[id] = 0.0
	_event("belt_built", definition.display_name + " 传送带已装上")
	return ""

## Taking a segment back refunds it; cups already on it still arrive.
func remove_belt(id: String) -> String:
	if not belts.has(id): return "这里没有传送带"
	var definition = _belt_def(id)
	belts.erase(id)
	belt_clock.erase(id)
	gold += definition.cost
	_event("belt_removed", definition.display_name + " 传送带已收起")
	return ""

## Takes back every bought segment with a full refund (old saves from when belts were for sale).
## Cups already on a segment still arrive, the same as remove_belt.
func retire_belts() -> int:
	var refund := 0
	for id in belts.keys():
		if id in GAME_BELTS: continue
		refund += _belt_def(id).cost
		remove_belt(id)
	return refund

func belt_rows() -> Array:
	var rows: Array = []
	for definition in PROGRESSION.belts:
		rows.append({"id": definition.id, "name": definition.display_name, "from": definition.from, "to": definition.to,
			"cost": definition.cost, "owned": belts.has(definition.id), "error": belt_error(definition.id),
			"available": station_unlocked("lemonade") and stage_index >= definition.stage, "points": definition.view_points})
	return rows

# Each bought segment acts as a courier with room for one cup: it takes the same job a
# worker would on its hop (same caps and flavor rules) and ships it along the belt.
func _run_belts() -> void:
	for id in belts:
		belt_clock[id] = maxf(0.0, belt_clock[id] - STEP)
		if belt_clock[id] > 0.0: continue
		var definition = _belt_def(id)
		var courier := {"id": -1, "post": "", "assignment_pending": false, "capacity": 1}
		_belt_courier = true
		var options := _jobs(courier)
		_belt_courier = false
		var best: Dictionary = {}
		for job in options:
			if job.is_empty() or job.kind == "serve" or _is_operation(job): continue
			if job.src != definition.from or job.dst != definition.to: continue
			if best.is_empty() or job.priority > best.priority: best = job
		if best.is_empty(): continue
		if best.src == "shelf": _shelf_reserved_out += best.count
		elif best.src != "supply": stations[best.src].reserved_out[best.item] = int(stations[best.src].reserved_out.get(best.item, 0)) + best.count
		if best.dst == "shelf": _shelf_reserved_in += best.count
		else: stations[best.dst].reserved_in += best.count
		_take(best)
		belt_items.append({"route": id, "item": best.item, "count": best.count, "progress": 0.0, "duration": definition.seconds, "dst": best.dst})
		belt_clock[id] = definition.interval

## Cups of a drink on the shelf or on their way there (kitchen stock; takeaway cups at the sealer are already spoken for).
func _flavor_inventory(dish: String) -> int:
	var count: int = shelf_stock.get(dish, 0)
	count += stations.topping.output.get(dish, 0)
	for worker in workers:
		if worker.job.is_empty() or worker.job.dst != "shelf": continue
		if _shelf_item(worker.job.item) == dish: count += worker.job.count
	return count

## Customers in line still waiting for this drink.
func _waiting(dish: String) -> int:
	var count := 0
	for order in orders:
		if not order.reserved and order.dish == dish: count += 1
	return count

## Brewed tea set on the shelf is served as black tea.
func _shelf_item(item: String) -> String:
	return "black_tea" if item == "tea" else item

func _topping_room() -> int:
	var room := 0
	for material in _definition("topping").materials:
		if station_levels.topping >= material.unlock_level:
			room += maxi(0, _definition("topping").flavor_cap - _flavor_inventory(material.item_id))
	return room

func _complete_topping(station: Dictionary, job: Dictionary) -> void:
	# Following orders, the flavor was chosen when the job was taken: the one that was ordered.
	if follow_orders and not station.processing_item.is_empty():
		station.output[station.processing_item] += job.count
		station.processing_item = ""
		return
	var flavors: Array = []
	for material in _definition("topping").materials:
		if station_levels.topping >= material.unlock_level: flavors.append(material.item_id)
	for unused in job.count:
		var placed := false
		for attempt in flavors.size():
			var dish: String = flavors[_flavor_cursor % flavors.size()]
			_flavor_cursor += 1
			if _flavor_inventory(dish) >= _definition("topping").flavor_cap: continue
			station.output[dish] += 1
			placed = true
			break
		# Every flavor filled up while this cup was being topped: it goes back to wait as plain milk tea
		# instead of vanishing.
		if not placed: station.input.plain_milk_tea += 1

# The pot stops at each stir point until someone stirs it, so it needs watching.
func _pause_for_stir(station: Dictionary, before: float) -> bool:
	for point in STIR_POINTS:
		if before < point and station.progress >= point:
			station.progress = point
			station.remaining = station.duration * (1.0 - point)
			station.phase = "stir"
			return true
	return false

func _update_machines() -> void:
	for key in ["boil", "mix", "seal"]:
		if not station_unlocked(key): continue
		var station: Dictionary = stations[key]
		if station.processing > 0 and not station.phase in ["awaiting_take", "stir"]:
			var before: float = station.progress
			station.remaining = maxf(0, station.remaining - STEP)
			station.progress = 1.0 - station.remaining / station.duration
			if key == "boil" and _pause_for_stir(station, before): continue
			if station.remaining <= 0.000001:
				if key == "boil": station.phase = "awaiting_take"
				else:
					station.output[station.processing_item] += station.processing
					station.processing = 0
					station.processing_item = ""
					station.phase = "ready"
				station.progress = 1.0
				_event("batch_ready", key + "已完成")
		if station.processing == 0 and key != "boil":
			var input_item := ""
			for item in station.input:
				if station.input[item] > 0:
					input_item = item
					break
			if not input_item.is_empty():
				# The mixer takes everything waiting; the sealer packs one cup at a time.
				station.processing = 1 if key == "seal" else station.input[input_item]
				station.input[input_item] -= station.processing
				station.processing_item = "plain_milk_tea" if key == "mix" else input_item
				station.duration = _machine_duration(key)
				station.remaining = station.duration
				station.progress = 0.0
				station.phase = "mixing" if key == "mix" else "sealing"
			elif _stock(station) == 0:
				station.phase = "idle"
				station.progress = 0.0

func _take(job: Dictionary) -> void:
	if job.src == "shelf": shelf_stock[job.item] -= job.count
	super._take(job)

func _deliver(destination: String, item: String, count: int) -> void:
	if destination == "pickup":
		# The rack only holds: cups go straight to where the front takes them from.
		stations.pickup.output[item] += count
		stations.pickup.reserved_in -= count
		return
	if destination == "shelf": shelf_stock[_shelf_item(item)] += count
	# The sealer packs drinks by name: tea from the pot is black tea.
	super._deliver(destination, _shelf_item(item) if destination == "seal" else item, count)

func _cancel_job(worker: Dictionary) -> void:
	if not worker.job.is_empty() and worker.job.src == "shelf" and worker.carry_count > 0:
		shelf_stock[worker.job.item] += worker.carry_count
	if not worker.job.is_empty() and worker.job.kind == "topping": stations[worker.job.src].processing_item = ""
	super._cancel_job(worker)
	# Whatever this hand was following is left where it stands; the next follower picks it up from there.
	worker.ticket = {}

func _dish_price(dish: String) -> int:
	var price := float(_base_price(dish))
	# Price upgrades multiply: each level ×(1 + step), each star ×star_mult, and the sources on one cup
	# (machine, ingredients, flavor) multiply together, so a level is worth more the dearer the cup already is.
	var mult := 1.0
	for id in ["lemonade", "boil", "mix", "supply", "press"]:
		var definition = _definition(id)
		if _art_mode(definition) and dish in definition.art_price_dishes:
			mult *= pow(1.0 + definition.art_price_step, station_levels[id] - 1) * pow(definition.art_star_mult, stars(id))
		for material in definition.materials:
			if _art_mode(material) and dish in material.art_price_dishes:
				mult *= pow(1.0 + material.art_price_step, material_levels[id][material.id] - 1)
	for id in ["topping", "press"]:
		for material in _definition(id).materials:
			if material.item_id == dish: mult *= material.bonus(material_levels[id][material.id])
	return roundi(price * mult * tuned("price"))

func _record_sale(job: Dictionary) -> void:
	# A cup handed over from the shelf or the stand is drunk here: the customer takes a seat for a while.
	if not _to_go(job):
		# A seated customer comes back to the chair they kept; a standing one takes the first open seat.
		var seat := int(_order_by_id(job.order_id).get("seat", -1))
		if seat < 0: seat = _first_open_seat()
		diners.append({"seat": seat, "dish": job.item, "left": seat_seconds()})
	sold += job.count
	sold_by_dish[job.item] += job.count
	var income: int = _dish_price(job.item) * job.count
	gold += income
	revenue += income
	_event("sale", "%s +%d" % [dish_name(job.item), income])

func audit() -> Dictionary:
	var report := super.audit()
	var count := 0
	for dish in shelf_stock:
		count += shelf_stock[dish]
		if shelf_stock[dish] < 0: report.errors.append("negative flavor stock")
		if _shelf_item_free(dish) < 0: report.errors.append("flavor shelf capacity: " + dish)
	if count != shelf_count: report.errors.append("flavor shelf total")
	for worker in workers:
		if not worker.deployed or not roster.has(worker): report.errors.append("deployment reference")
	report.valid = report.errors.is_empty()
	return report

func to_dict() -> Dictionary:
	var deployed: Array = []
	for worker in workers: deployed.append(worker.id)
	return {"version": SAVE_VERSION, "roster": roster.duplicate(true), "deployed": deployed,
		"stations": stations.duplicate(true), "belt_items": belt_items.duplicate(true),
		"shelf_stock": shelf_stock.duplicate(true), "shelf_count": shelf_count,
		"orders": orders.duplicate(true), "gold": gold, "sold": sold, "revenue": revenue,
		"elapsed": elapsed, "use_belts": use_belts, "paused": paused, "events": events.duplicate(true),
		"accumulator": _accumulator, "generated": _generated, "shelf_reserved_in": _shelf_reserved_in,
		"shelf_reserved_out": _shelf_reserved_out, "next_order": _next_order, "order_clock": _order_clock,
		"stage_index": stage_index, "station_levels": station_levels.duplicate(true),
		"material_levels": material_levels.duplicate(true), "unlocked_stations": unlocked_stations.duplicate(true),
		"sold_by_dish": sold_by_dish.duplicate(true), "flavor_cursor": _flavor_cursor, "rng_state": _rng.state,
		"belts": belts.duplicate(true), "belt_clock": belt_clock.duplicate(true),
		"boxes": boxes.duplicate(true), "seats": seats, "diners": diners.duplicate(true), "flyers": flyers,
		"flyer_wave": flyer_wave, "flyer_wait": flyer_wait, "flyer_clock": flyer_clock, "flyer_pending": flyer_pending,
		"front_upgrades": front_upgrades, "kitchen_upgrades": kitchen_upgrades, "order_ramp": order_ramp.duplicate(true)}

func _apply_state(state: Dictionary) -> void:
	roster = state.roster.duplicate(true)
	workers.clear()
	for id in state.deployed: workers.append(worker_by_id(id))
	stations = state.stations.duplicate(true)
	belt_items = state.belt_items.duplicate(true)
	shelf_stock = state.shelf_stock.duplicate(true)
	shelf_count = state.shelf_count
	orders = state.orders.duplicate(true)
	gold = state.gold
	sold = state.sold
	revenue = state.revenue
	elapsed = state.elapsed
	use_belts = state.use_belts
	paused = state.paused
	events = state.events.duplicate(true)
	_accumulator = state.accumulator
	_generated = state.generated
	_shelf_reserved_in = state.shelf_reserved_in
	_shelf_reserved_out = state.shelf_reserved_out
	_next_order = state.next_order
	_order_clock = state.order_clock
	stage_index = state.stage_index
	station_levels = state.station_levels.duplicate(true)
	material_levels = state.material_levels.duplicate(true)
	unlocked_stations = state.unlocked_stations.duplicate(true)
	sold_by_dish = state.sold_by_dish.duplicate(true)
	_flavor_cursor = state.flavor_cursor
	belts = state.belts.duplicate(true)
	belt_clock = state.belt_clock.duplicate(true)
	boxes = state.boxes.duplicate(true)
	seats = state.seats
	flyers = state.flyers
	flyer_wave = state.flyer_wave
	flyer_wait = state.flyer_wait
	flyer_clock = state.flyer_clock
	flyer_pending = state.flyer_pending
	front_upgrades = state.front_upgrades
	kitchen_upgrades = state.kitchen_upgrades
	diners = state.diners.duplicate(true)
	order_ramp = state.order_ramp.duplicate(true)
	_rng.state = state.rng_state

func load_dict(state: Dictionary) -> String:
	var from_version: Variant = state.get("version")
	if state.get("version") is int and state.version == 3:
		state = _migrate_v3(state)
		state.version = 4
	if state.get("version") is int and state.version == 4: state = _migrate_v4(state)
	if state.get("version") is int and state.version == 5:
		state = state.duplicate(true)
		state.version = 6
		state.flyers = 1
	if state.get("version") is int and state.version == 6: state = _migrate_v6(state)
	if state.get("version") is int and state.version == 7: state = _migrate_v7(state)
	# v8 and every older path (v6 rebuilds from a fresh shop but copies the old level and sales tables)
	# need the press table's keys filled in.
	if from_version is int and from_version <= 8 and state.get("version") in [8, SAVE_VERSION]: state = _migrate_v8(state)
	if state.get("version") is int and state.version == 9: state = _migrate_v9(state)
	if state.get("version") is int and state.version == 10: state = _migrate_v10(state)
	if state.get("version") is int and state.version == 11: state = _migrate_v11(state)
	if from_version is int and from_version < 13 and state.get("version") in [12, SAVE_VERSION]: state = _migrate_v12(state)
	if state.get("version") is int and state.version == 13: state = _migrate_v13(state)
	if state.get("version") is int and state.version == 14: state = _migrate_v14(state)
	_round_seats(state)
	var migrated: bool = from_version is int and from_version < SAVE_VERSION
	var error := _validate_state(state, migrated)
	if not error.is_empty(): return error
	var candidate = get_script().new()
	candidate._apply_state(state)
	var report: Dictionary = candidate.audit()
	if not report.valid: return "存档库存或预留不一致：%s" % report.errors
	# An older save can have more staff out than this version's slots allow: the extras go back to
	# the roster the normal way (cargo and reservations returned), newest deployment first.
	if migrated and candidate._recall_over_limit():
		report = candidate.audit()
		if not report.valid: return "存档库存或预留不一致：%s" % report.errors
		state = candidate.to_dict()
	if candidate._recover_layout_positions():
		report = candidate.audit()
		if not report.valid: return "存档库存或预留不一致：%s" % report.errors
		state = candidate.to_dict()
	_apply_state(state)
	return ""

## Seats are sold a table at a time: an older save's count is rounded up to whole tables (never fewer seats).
func _round_seats(state: Dictionary) -> void:
	if not state.get("seats") is int: return
	var step := maxi(1, PROGRESSION.seat_step)
	var extra := maxi(0, state.seats - PROGRESSION.seat_start)
	state.seats = mini(PROGRESSION.seat_start + ceili(float(extra) / step) * step, seat_max())

## A redrawn shop can put furniture on floor an older save had staff standing or walking on.
## Repair only affected positions/routes after the inventory audit has passed.
func _recover_layout_positions() -> bool:
	var changed := false
	for worker in roster:
		if Layout.path(worker.pos, Layout.POINTS.counter).is_empty():
			_cancel_job(worker)
			worker.pos = Layout.POST_POINTS.get(worker.post, Layout.POINTS.counter)
			worker.assignment_point = worker.pos
			worker.assignment_pending = false
			changed = true
		elif worker.walking and not worker.job.is_empty():
			var destination: Vector2 = _source_point(worker.job) if worker.phase == "walk_pickup" else _destination_point(worker.job)
			var stale: bool = worker.path.is_empty() or worker.path[worker.path.size() - 1] != destination
			for index in range(worker.path_index, worker.path.size()):
				if Layout.path(worker.path[index], Layout.POINTS.counter).is_empty(): stale = true
			if stale:
				_walk(worker, destination, worker.phase)
				changed = true
	return changed

## v6 → v7: training is refunded and undone (the upgrade lists replace it), and someone takes the counter,
## because kitchen staff no longer serve. Jobs from the old rules can't be kept, so like v3 the floor
## starts fresh: progress, money, levels, seats and staff stay; cups in flight and the queue are dropped.
func _migrate_v6(old: Dictionary) -> Dictionary:
	var fresh = get_script().new()
	var state: Dictionary = fresh.to_dict()
	for key in ["gold", "sold", "revenue", "elapsed", "paused", "sold_by_dish", "station_levels", "material_levels", "flavor_cursor", "rng_state", "next_order",
			"stage_index", "unlocked_stations", "boxes", "seats", "flyers"]:
		if old.has(key) and typeof(old[key]) == typeof(state[key]): state[key] = old[key].duplicate(true) if old[key] is Dictionary else old[key]
	state.generated = state.sold
	if not old.get("roster") is Array or not old.get("deployed") is Array or old.roster.is_empty(): return state
	var roster_copy: Array = old.roster.duplicate(true)
	for worker in roster_copy:
		if not worker is Dictionary or not worker.get("art") in ARTS or not worker.get("id") is int or not worker.get("level") is int: return old
		for level in range(1, worker.level):
			if level - 1 < PROGRESSION.train_costs.size(): state.gold += PROGRESSION.train_costs[level - 1]
		var base := _new_staff(worker.art, worker.id)
		for key in ["level", "speed", "skill", "capacity"]: worker[key] = base[key]
		worker.merge({"job": {}, "phase": "idle", "task_label": "idle", "carry_item": "", "carry_count": 0, "walking": false,
			"path": PackedVector2Array(), "path_index": 0, "action_left": 0.0, "assignment_pending": false, "ticket": {}}, true)
	state.roster = roster_copy
	# Old saves had one shared staff cap; now there is one front seat and the stage's kitchen seats.
	# Someone takes the counter (a counter worker, else a mobile one, else a posted one), then kitchen
	# seats fill in the old deployment order, and anyone left over goes back to the roster.
	var deployed_workers := roster_copy.filter(func(worker): return worker.id in old.deployed)
	var front_pick: Dictionary = {}
	for wanted in ["counter", ""]:
		for worker in deployed_workers:
			if front_pick.is_empty() and worker.get("post", "") == wanted: front_pick = worker
	if front_pick.is_empty() and not deployed_workers.is_empty(): front_pick = deployed_workers[0]
	var stage: int = state.stage_index if state.stage_index is int else 0
	var kitchen_room: int = PROGRESSION.stages[clampi(stage, 0, PROGRESSION.stages.size() - 1)].staff_slots
	state.deployed = []
	for worker in deployed_workers:
		if worker == front_pick:
			_seat_at_counter(worker)
		elif kitchen_room > 0:
			kitchen_room -= 1
			if worker.get("post", "") == "counter": worker.post = ""
		else:
			worker.post = ""
			worker.deployed = false
			continue
		worker.deployed = true
		state.deployed.append(worker.id)
	# Belts are no longer sold; refund any the old save still owned, as v3 and startup do.
	if old.get("belts") is Dictionary:
		for id in old.belts:
			var belt = fresh._belt_def(String(id))
			if belt != null: state.gold += belt.cost
	return state

## v7 → v8: staff start with nothing to follow; whatever is in the line is picked up by the next ticket.
func _migrate_v7(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	state.version = 8
	if state.get("roster") is Array:
		for worker in state.roster:
			if worker is Dictionary: worker["ticket"] = {}
	return state

## v8 → v9: the press table, its fruits and the two fruit teas are new; every new key starts empty or at Lv1.
func _migrate_v8(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	state.version = 9
	var fresh: Dictionary = get_script().new().to_dict()
	for key in ["shelf_stock", "sold_by_dish", "station_levels", "unlocked_stations", "material_levels", "stations"]:
		if state.get(key) is Dictionary: _fill_missing(state[key], fresh[key])
	return state

## v9 → v10: dishes already on the menu count as fully eased in; ones not yet open start from zero.
func _migrate_v9(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	state.version = 10
	if state.get("order_ramp") is Dictionary: return state
	var probe = get_script().new()
	if state.get("station_levels") is Dictionary and state.get("unlocked_stations") is Dictionary and state.get("boxes") is Dictionary:
		probe.station_levels = state.station_levels
		probe.unlocked_stations = state.unlocked_stations
		probe.boxes = state.boxes
	var ramp_state := {}
	for dish in DISHES: ramp_state[dish] = RAMP_ORDERS if probe._dish_unlocked(dish, false) else 0
	ramp_state.takeaway = RAMP_ORDERS if probe.station_unlocked("seal") else 0
	state.order_ramp = ramp_state
	return state

## v10 → v11: the takeaway rack starts empty. Sealed cups an old save left at the sealer are carried
## to it by the kitchen; a front worker already fetching one there finishes the trip.
func _migrate_v10(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	state.version = 11
	if state.get("stations") is Dictionary and not state.stations.has("pickup"):
		state.stations.pickup = get_script().new().stations.pickup.duplicate(true)
	return state

## v11 → v12: the kitchen press table and banana tea are gone, lemon tea moved to the front and its unlock
## moved ahead of the topping machine. Cups in flight can't follow the old routes, so like v6 the floor
## starts fresh (queue, jobs, tickets and stock dropped); progress, money, levels, seats and staff stay.
## A shop already past the topping machine gets the front press for free (unlocks follow stage order).
## v12 → v13 (second-shop economy): the flyer is free with its own upgrade levels, so an old flyer level
## (it meant something else) starts over at 1; the topping machine only opens flavors now and tops out at Lv4.
func _migrate_v12(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	if state.version == 12: state.version = 13
	state.flyers = 1
	if state.get("station_levels") is Dictionary and state.station_levels.get("topping") is int:
		state.station_levels.topping = mini(state.station_levels.topping, _max_level("topping"))
	return state

## v13 → v14: orders without a seat stand in line; flyer state saved (a missing one means no flyer running).
## Early v13 saves of this version's test builds lack the seat field too, so it is filled in only where missing.
func _migrate_v13(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	state.version = 14
	if state.get("orders") is Array:
		for order in state.orders:
			if order is Dictionary and not order.has("seat"): order["seat"] = -1
	for key in ["flyer_wave", "flyer_wait", "flyer_clock"]:
		if not state.has(key): state[key] = 0.0
	if not state.has("flyer_pending"): state.flyer_pending = 0
	return state

## v15 has fewer, bigger levels (2026-11-05 economy pass): levels bought past the new caps are kept at
## the cap; the brewer's ten levels fold onto its eight by speed (old Lv3 = new Lv2, old Lv10 = new Lv8).
const BOIL_V14_TO_V15 := [1, 1, 2, 3, 4, 5, 6, 6, 7, 8]

func _migrate_v14(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	state.version = SAVE_VERSION
	if state.get("station_levels") is Dictionary:
		var levels: Dictionary = state.station_levels
		if levels.get("boil") is int: levels.boil = BOIL_V14_TO_V15[clampi(levels.boil, 1, 10) - 1]
		for id in levels.keys():
			if levels[id] is int and id in MACHINE_IDS and _max_level(id) > 0: levels[id] = clampi(levels[id], 1, _max_level(id))
	if state.get("material_levels") is Dictionary:
		for id in state.material_levels.keys():
			var mats = state.material_levels[id]
			if not mats is Dictionary or _definition(id) == null: continue
			for material in mats.keys():
				if mats[material] is int and _definition(id).material(material) != null:
					mats[material] = clampi(mats[material], 1, _material_max(id, material))
	for side in ["front", "kitchen"]:
		var key: String = side + "_upgrades"
		if state.get(key) is int: state[key] = mini(state[key], _upgrade_kinds(side).size())
	if state.get("flyers") is int: state.flyers = clampi(state.flyers, 1, flyer_max_level())
	return state

## Sends staff over this stage's front or kitchen slots back to the roster. True if anyone was recalled.
func _recall_over_limit() -> bool:
	var recalled := false
	for side in ["front", "kitchen"]:
		var room: int = front_slots() if side == "front" else kitchen_slots()
		var out: Array = workers.filter(func(w: Dictionary) -> bool: return (w.post == "counter") == (side == "front"))
		while out.size() > room:
			recall_worker(out.pop_back().id)
			recalled = true
	return recalled

func _migrate_v11(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	state.version = 12
	var fresh: Dictionary = get_script().new().to_dict()
	for key in ["stations", "shelf_stock", "shelf_count", "orders", "belt_items", "generated", "shelf_reserved_in", "shelf_reserved_out", "order_clock", "accumulator"]:
		state[key] = fresh[key].duplicate(true) if fresh[key] is Dictionary or fresh[key] is Array else fresh[key]
	if state.get("sold_by_dish") is Dictionary:
		# Banana teas sold count as fruit (lemon) teas so the sales total stays whole.
		var banana: Variant = state.sold_by_dish.get("banana_tea", 0)
		state.sold_by_dish.erase("banana_tea")
		if banana is int and state.sold_by_dish.get("lemon_tea") is int: state.sold_by_dish.lemon_tea += banana
	if state.get("sold") is int: state.generated = state.sold
	if state.get("material_levels") is Dictionary and state.material_levels.get("press") is Dictionary: state.material_levels.press.erase("banana")
	if state.get("order_ramp") is Dictionary: state.order_ramp.erase("banana_tea")
	if state.get("diners") is Array:
		for diner in state.diners:
			if diner is Dictionary and diner.get("dish") == "banana_tea": diner.dish = "lemon_tea"
	# Old stages: …, 3 milk, 4 topping, 5 press. New: …, 3 milk, 4 press, 5 topping.
	if state.get("stage_index") is int and state.stage_index >= 4 and state.get("unlocked_stations") is Dictionary:
		state.stage_index = 5
		state.unlocked_stations.press = true
		state.unlocked_stations.topping = true
	if state.get("roster") is Array:
		for worker in state.roster:
			if not worker is Dictionary: continue
			worker.merge({"job": {}, "phase": "idle", "task_label": "idle", "carry_item": "", "carry_count": 0, "walking": false,
				"path": PackedVector2Array(), "path_index": 0, "action_left": 0.0, "assignment_pending": false, "ticket": {}}, true)
		# The last stage has one kitchen seat fewer than the old press stage: the newest extra hands go back to the roster.
		if state.get("deployed") is Array and state.get("stage_index") is int:
			var room: int = PROGRESSION.stages[clampi(state.stage_index, 0, PROGRESSION.stages.size() - 1)].staff_slots
			for id in state.deployed.duplicate():
				for worker in state.roster:
					if not worker is Dictionary or worker.get("id") != id or worker.get("post") == "counter": continue
					if room > 0: room -= 1
					else:
						worker.deployed = false
						worker.post = ""
						state.deployed.erase(id)
	return state

## Adds the keys `sample` has and `target` lacks (recursing into nested dictionaries); existing values stay.
func _fill_missing(target: Dictionary, sample: Dictionary) -> void:
	for key in sample:
		if not target.has(key): target[key] = sample[key].duplicate(true) if sample[key] is Dictionary else sample[key]
		elif target[key] is Dictionary and sample[key] is Dictionary: _fill_missing(target[key], sample[key])

## v4 → v5: the brewer pot holds up to six cups, and lemonade levels above the new cap are refunded.
func _migrate_v4(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	state.version = 5
	if state.get("stations") is Dictionary and state.stations.get("boil") is Dictionary: state.stations.boil.capacity = BOIL_CAPACITY
	if state.get("station_levels") is Dictionary and state.station_levels.get("lemonade") is int and state.get("gold") is int:
		var cap := _max_level("lemonade")
		while state.station_levels.lemonade > cap and state.station_levels.lemonade - 2 < LEMONADE_V4_COSTS.size():
			state.gold += LEMONADE_V4_COSTS[state.station_levels.lemonade - 2]
			state.station_levels.lemonade -= 1
	return state

## v3 had the whole black tea line as one stage and sealed every kitchen cup. Keep the player's
## progress (money, sales, levels, staff) and start the floor fresh: cups in flight and the queue are dropped.
func _migrate_v3(old: Dictionary) -> Dictionary:
	var fresh = get_script().new()
	var state: Dictionary = fresh.to_dict()
	for key in ["gold", "sold", "revenue", "elapsed", "paused", "sold_by_dish", "station_levels", "material_levels", "flavor_cursor", "rng_state", "next_order"]:
		if old.has(key) and typeof(old[key]) == typeof(state[key]): state[key] = old[key].duplicate(true) if old[key] is Dictionary else old[key]
	# The floor starts empty, so every cup ever made has been sold.
	state.generated = state.sold
	# Belts are no longer sold; refund any the old save owned, as the shop does on startup.
	if old.get("belts") is Dictionary:
		for id in old.belts:
			var belt = fresh._belt_def(String(id))
			if belt != null: state.gold += belt.cost
	var old_stage: int = old.get("stage_index", 0) if old.get("stage_index", 0) is int else 0
	var lemon: bool = old.get("unlocked_stations", {}).get("lemonade", false) == true
	# The old topping stage is now the last one (the front press opens before it and comes with it).
	state.stage_index = [0, 2, 3, 5][clampi(old_stage, 0, 3)] if lemon else 0
	state.boxes = {"tea_leaf": state.stage_index >= 2, "milk": state.stage_index >= 3}
	for id in state.unlocked_stations:
		state.unlocked_stations[id] = id in ["counter", "supply"] or (id == "lemonade" and lemon) or (fresh._unlock_stage(id) > 0 and state.stage_index >= fresh._unlock_stage(id))
	if old.get("roster") is Array and old.get("deployed") is Array and not old.roster.is_empty():
		var roster_copy: Array = old.roster.duplicate(true)
		for worker in roster_copy:
			if not worker is Dictionary: return old
			worker.merge({"job": {}, "phase": "idle", "task_label": "idle", "carry_item": "", "carry_count": 0, "walking": false,
				"path": PackedVector2Array(), "path_index": 0, "action_left": 0.0, "assignment_pending": false}, true)
		state.roster = roster_copy
		state.deployed = old.deployed.duplicate()
	return state

# Validate every value before following dictionary paths or applying live state.
func _same_shape(value: Variant, sample: Variant) -> bool:
	if typeof(value) != typeof(sample): return false
	if value is float: return is_finite(value)
	if value is Vector2: return value == Vector2.INF or (is_finite(value.x) and is_finite(value.y))
	if value is Dictionary:
		if value.size() != sample.size(): return false
		for key in sample:
			if not value.has(key) or not _same_shape(value[key], sample[key]): return false
	return true

func _counts(value: Variant, allowed: Array) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not key in allowed or not value[key] is int or value[key] < 0: return false
	return true

func _valid_job_route(job: Dictionary) -> bool:
	match job.kind:
		"serve":
			return job.dst == "counter" and job.count == 1 and job.belt == "" and ((job.src == "supply" and job.item in FRONT_DISHES) or (job.src == "shelf" and _is_kitchen_dish(job.item)) or (job.src in ["seal", "pickup"] and job.item in DISHES))
		"carry_to_pickup": return job.src == "seal" and job.dst == "pickup" and job.item in DISHES and job.belt == ""
		"brew_start": return job.src == "boil" and job.dst == "boil" and job.item == "raw" and job.count >= 1 and job.count <= 6 and job.belt == ""
		"brew_take", "stir": return job.src == "boil" and job.dst == "boil" and job.item == "tea" and job.count >= 1 and job.count <= 6 and job.belt == ""
		"topping": return job.src == "topping" and job.dst == "topping" and job.item == "plain_milk_tea" and job.belt == ""
		"load_boil": return job.src == "supply" and job.dst == "boil" and job.item == "raw" and job.belt == ""
		"unload_boil": return job.src == "boil" and job.dst == "mix" and job.item == "tea" and job.belt == ""
		"transfer_to_topping": return job.src == "mix" and job.dst == "topping" and job.item == "plain_milk_tea" and job.belt == ""
		"carry_to_seal":
			return job.dst == "seal" and job.belt == "" and ((job.src == "supply" and job.item == "lemonade") or (job.src == "shelf" and _is_kitchen_dish(job.item))
				or (job.src == "boil" and job.item == "tea") or (job.src == "mix" and job.item == "plain_milk_tea") or (job.src == "topping" and _is_topped(job.item)))
		"carry_to_shelf":
			return job.dst == "shelf" and job.belt == "" and ((job.src == "boil" and job.item == "tea") or (job.src == "mix" and job.item == "plain_milk_tea") or (job.src == "topping" and _is_topped(job.item)))
	return false

func _validate_state(state: Dictionary, allow_extra_staff := false) -> String:
	var template := to_dict()
	if state.size() != template.size(): return "存档字段不完整"
	for key in template:
		if not state.has(key) or typeof(state[key]) != typeof(template[key]): return "存档字段类型错误：" + key
	for key in ["version", "gold", "sold", "revenue", "shelf_count", "generated", "shelf_reserved_in", "shelf_reserved_out", "next_order", "stage_index", "flavor_cursor"]:
		if state[key] < 0: return "存档数值无效：" + key
	if state.version != SAVE_VERSION or state.stage_index >= PROGRESSION.stages.size() or state.next_order < 1: return "不支持的存档版本或阶段"
	for key in ["elapsed", "accumulator", "order_clock"]:
		if not is_finite(state[key]) or state[key] < -0.000001: return "存档时间无效"
	if state.accumulator >= STEP + 0.000001: return "存档时间余量无效"
	if not _same_shape(state.station_levels, template.station_levels) or not _same_shape(state.unlocked_stations, template.unlocked_stations): return "设备字段无效"
	if not _same_shape(state.material_levels, template.material_levels): return "配料字段无效"
	if not _same_shape(state.order_ramp, template.order_ramp): return "出单字段无效"
	for key in state.order_ramp:
		if state.order_ramp[key] < 0 or state.order_ramp[key] > RAMP_ORDERS: return "出单字段无效"
	if state.belts.size() != state.belt_clock.size(): return "传送带字段无效"
	for id in state.belts:
		var belt = _belt_def(id) if id is String else null
		if belt == null or state.belts[id] != true or state.stage_index < belt.stage or not state.unlocked_stations.lemonade: return "传送带字段无效"
		var clock: Variant = state.belt_clock.get(id)
		if not clock is float or not is_finite(clock) or clock < 0 or clock > belt.interval + 0.000001: return "传送带计时无效"
	for id in MACHINE_IDS:
		var definition = _definition(id)
		# Saves from before price upgrades may hold old speed levels (e.g. cabinet Lv3).
		var max_level := maxi(_max_level(id), definition.level_speed.size() if definition != null else 1)
		if state.station_levels[id] < 1 or state.station_levels[id] > max_level: return "设备等级无效"
		var expected_unlock: bool = id in ["counter", "supply"] or (id == "lemonade" and state.unlocked_stations.lemonade) or (_unlock_stage(id) > 0 and state.stage_index >= _unlock_stage(id))
		if state.unlocked_stations[id] != expected_unlock: return "设备解锁状态无效"
	if state.stage_index > 0 and not state.unlocked_stations.lemonade: return "经营阶段无效"
	for id in state.material_levels:
		for material in state.material_levels[id]:
			var level: int = state.material_levels[id][material]
			if level < 1 or level > _material_max(id, material): return "配料等级无效"
	if not _same_shape(state.shelf_stock, template.shelf_stock) or not _counts(state.shelf_stock, DISHES): return "货架口味无效"
	if not _same_shape(state.sold_by_dish, template.sold_by_dish) or not _counts(state.sold_by_dish, DISHES): return "销量无效"
	var sale_total := 0
	for value in state.sold_by_dish.values(): sale_total += value
	if sale_total != state.sold: return "销量总数不一致"
	if state.stations.size() != template.stations.size(): return "机器状态不完整"
	for id in template.stations:
		if not state.stations.has(id) or not state.stations[id] is Dictionary: return "机器字段无效"
		var station: Dictionary = state.stations[id]
		var expected: Dictionary = template.stations[id]
		if station.size() != expected.size(): return "机器字段不完整"
		for key in expected:
			if not station.has(key) or typeof(station[key]) != typeof(expected[key]): return "机器字段类型无效"
		if not _counts(station.input, expected.input.keys()) or not _counts(station.output, expected.output.keys()) or not _counts(station.reserved_out, expected.input.keys() + expected.output.keys()): return "机器库存无效"
		if station.input.size() != expected.input.size() or station.output.size() != expected.output.size(): return "机器库存字段不完整"
		if station.processing < 0 or station.reserved_in < 0 or station.capacity != expected.capacity: return "机器数量无效"
		for key in ["progress", "remaining", "duration"]:
			if not is_finite(station[key]) or station[key] < 0: return "机器进度无效"
		if station.progress > 1 or (station.processing > 0 and station.duration <= 0): return "机器进度无效"
		if not station.phase in ["idle", "ready", "working", "heating", "stir", "awaiting_take", "mixing", "sealing"]: return "机器阶段无效"
		if station.processing > 0 and id in ["mix", "seal"] and not station.processing_item in expected.output: return "加工口味无效"
	var worker_sample := _make_worker(0)
	worker_sample.source = ""
	worker_sample.deployed = false
	if state.roster.is_empty(): return "员工名册无效"
	if not state.front_upgrades is int or not state.kitchen_upgrades is int: return "员工升级无效"
	# Front staff (at the counter) fill the front slots; everyone else fills the kitchen slots of this stage.
	var front_room := 1
	for index in mini(state.front_upgrades, PROGRESSION.front_upgrade_kinds.size()): front_room += 1 if PROGRESSION.front_upgrade_kinds[index] == "slot" else 0
	var front_count := 0
	var kitchen_count := 0
	for worker in state.roster:
		if worker is Dictionary and worker.get("id") in state.deployed:
			if worker.get("post") == "counter": front_count += 1
			else: kitchen_count += 1
	if not allow_extra_staff and (front_count > front_room or kitchen_count > PROGRESSION.stages[state.stage_index].staff_slots): return "派出员工超过岗位数"
	var ids: Array = []
	for worker in state.roster:
		if not worker is Dictionary: return "员工字段无效"
		# Jobs have their own variable schema; every other worker field is fixed.
		var fields: Dictionary = worker.duplicate()
		if not fields.has("job") or not fields.job is Dictionary: return "员工运单无效"
		fields.job = {}
		if not fields.has("ticket") or not fields.ticket is Dictionary: return "员工跟单无效"
		fields.ticket = {}
		if not _same_shape(fields, worker_sample): return "员工字段无效"
		if not worker.ticket.is_empty():
			var ticket: Dictionary = worker.ticket
			if not _same_shape(ticket, {"dish": "", "count": 1, "stage": "", "wait": 0.0}) or ticket.wait < 0 or not _is_kitchen_dish(ticket.dish) or ticket.count < 1 or ticket.count > worker.capacity + 9 or not ticket.stage in TICKET_STAGES: return "员工跟单无效"
			if not worker.deployed or worker.post == "counter": return "员工跟单无效"
		if not worker.art in ARTS or worker.id < 1 or worker.id in ids: return "员工身份无效"
		ids.append(worker.id)
		var carry_bonus := 0
		var side_kinds: Array = PROGRESSION.front_upgrade_kinds if worker.post == "counter" else PROGRESSION.kitchen_upgrade_kinds
		var side_bought: int = state.front_upgrades if worker.post == "counter" else state.kitchen_upgrades
		if side_bought is int and side_bought >= 0:
			for index in mini(side_bought, side_kinds.size()): carry_bonus += 1 if side_kinds[index] == "carry" else 0
		if worker.level < 1 or worker.speed <= 0 or worker.skill <= 0 or worker.capacity < 1 or worker.carry_count < 0 or worker.carry_count > worker.capacity + carry_bonus: return "员工能力或货物无效"
		if not worker.role in ["speed", "carry", "skill"] or worker.source.is_empty(): return "员工来源或能力无效"
		if not worker.post.is_empty() and not Layout.POST_POINTS.has(worker.post): return "员工岗位无效"
		if not worker.phase in ["idle", "walk_pickup", "pickup", "work", "walk_dropoff", "dropoff"]: return "员工阶段无效"
		if not is_finite(worker.pos.x) or not is_finite(worker.pos.y) or worker.action_left < 0 or worker.path_index < 0 or worker.path_index > worker.path.size(): return "员工移动状态无效"
		for point in worker.path:
			if not is_finite(point.x) or not is_finite(point.y): return "员工路径无效"
		if worker.job.is_empty():
			if worker.phase != "idle" or worker.carry_count != 0: return "员工空闲状态无效"
		else:
			var job_sample := {"kind": "", "src": "", "dst": "", "item": "", "count": 1, "priority": 1.0, "belt": "", "order_id": -1}
			if not _same_shape(worker.job, job_sample): return "员工运单字段无效"
			var job: Dictionary = worker.job
			if not job.kind in ["serve", "topping", "brew_start", "brew_take", "stir", "load_boil", "unload_boil", "transfer_to_topping", "load_seal_belt", "carry_to_seal", "load_shelf_belt", "carry_to_shelf", "carry_to_pickup"]: return "员工任务无效"
			if not job.src in ["supply", "shelf", "boil", "mix", "topping", "seal", "pickup"] or not job.dst in ["boil", "mix", "topping", "seal", "shelf", "counter", "pickup"]: return "员工运输端点无效"
			if not job.item in DISHES + ["raw", "tea"] or job.count <= 0: return "员工运单货物无效"
			if not job.belt in ["", "topping_to_seal", "seal_to_shelf"]: return "员工传送带无效"
			if not _valid_job_route(job): return "员工运单路线或口味无效"
			if _is_operation(job):
				if not worker.phase in ["walk_pickup", "work"]: return "人工操作阶段无效"
			elif worker.phase == "work": return "运输任务不能进行机器操作"
			if worker.post == "counter" and job.kind != "serve": return "员工岗位与任务不一致"
			if worker.post != "counter" and job.kind == "serve": return "后厨员工不上菜"
			if not worker.post in ["", "counter"] and not _post_job(worker.post, job): return "员工岗位与任务不一致"
			if not _is_operation(job) and job.count > worker.capacity + carry_bonus: return "员工运单超过搬运能力"
			if worker.phase in ["walk_dropoff", "dropoff"]:
				if worker.carry_count != job.count or worker.carry_item != job.item: return "员工在途货物不一致"
			elif worker.carry_count != 0 or not worker.carry_item.is_empty(): return "员工取货状态无效"
			if worker.walking != (worker.phase in ["walk_pickup", "walk_dropoff"]): return "员工行走阶段无效"
			if not worker.deployed or worker.phase == "idle": return "待派遣员工不能工作"
		if worker.deployed != state.deployed.has(worker.id): return "员工派遣关系无效"
		if not worker.deployed and (not worker.job.is_empty() or not worker.post.is_empty()): return "待派遣员工状态无效"
	var active_ids: Array = []
	for id in state.deployed:
		if not id is int or not id in ids or id in active_ids: return "员工派遣编号无效"
		active_ids.append(id)
	var order_ids: Array = []
	for order in state.orders:
		if not order is Dictionary or not _same_shape(order, {"id": 1, "wait": 0.0, "reserved": false, "dish": "", "takeaway": false, "seat": 0}): return "订单字段无效"
		if order.id < 1 or order.id >= state.next_order or order.id in order_ids or order.wait < 0 or not order.dish in DISHES: return "订单内容无效"
		if order.seat < -1 or order.seat >= state.seats or (order.seat >= 0 and order.takeaway): return "订单座位无效"
		order_ids.append(order.id)
	var served_orders: Array = []
	var operations := {"boil": 0, "topping": 0}
	for worker in state.roster:
		if worker.job.is_empty(): continue
		var job: Dictionary = worker.job
		if _is_operation(job): operations[job.src] += 1
		if job.kind != "serve": continue
		if job.order_id in served_orders: return "订单重复派送"
		served_orders.append(job.order_id)
		var matching_order := false
		for order in state.orders:
			if order.id == job.order_id and order.dish == job.item and order.reserved: matching_order = true
		if not matching_order: return "运单与订单口味不一致"
	for id in operations:
		if operations[id] > 1 or state.stations[id].work_reserved != (operations[id] == 1): return "人工岗位预留不一致"
	for id in state.stations:
		var station: Dictionary = state.stations[id]
		for item in station.reserved_out:
			var stock: Dictionary = station.input if _input_item(id, item) else station.output
			if station.reserved_out[item] > stock.get(item, 0): return "取货预留超过实际库存"
	for shipment in state.belt_items:
		var sample := {"route": "", "item": "", "count": 1, "progress": 0.0, "duration": 1.0, "dst": ""}
		if not shipment is Dictionary or not _same_shape(shipment, sample): return "传送带字段无效"
		var route = _belt_def(shipment.route)
		if route == null or not shipment.item in DISHES + ["raw", "tea"] or shipment.item in FRONT_DISHES or shipment.count <= 0 or shipment.duration <= 0 or shipment.progress < 0 or shipment.progress >= 1: return "传送带内容无效"
		if shipment.dst != route.to: return "传送带终点不一致"
	if not _same_shape(state.boxes, template.boxes): return "原料箱字段无效"
	for material in state.boxes:
		var machine := _canonical(_box_def(material).box_machine)
		if state.boxes[material] and not state.unlocked_stations[machine]: return "原料箱解锁状态无效"
	if state.seats < PROGRESSION.seat_start or state.seats > seat_max() or state.diners.size() > state.seats: return "座位无效"
	if state.flyers < 1 or state.flyers > flyer_max_level(): return "传单字段无效"
	if state.flyer_wave < 0 or state.flyer_wait < 0 or state.flyer_clock < 0 or state.flyer_pending < 0: return "传单状态无效"
	if state.front_upgrades < 0 or state.front_upgrades > PROGRESSION.front_upgrade_kinds.size() or state.kitchen_upgrades < 0 or state.kitchen_upgrades > PROGRESSION.kitchen_upgrade_kinds.size(): return "员工升级无效"
	var seat_ids: Array = []
	for order in state.orders:
		if order.seat < 0: continue
		if order.seat in seat_ids: return "订单座位重复"
		seat_ids.append(order.seat)
	for diner in state.diners:
		if not diner is Dictionary or not _same_shape(diner, {"seat": 0, "dish": "", "left": 0.0}): return "堂食客人字段无效"
		if diner.seat < 0 or diner.seat >= state.seats or diner.seat in seat_ids or not diner.dish in DISHES or diner.left < 0 or diner.left > _longest_seat_seconds() + 0.000001: return "堂食客人无效"
		seat_ids.append(diner.seat)
	for event in state.events:
		if not event is Dictionary or not _same_shape(event, {"kind": "", "text": ""}): return "事件字段无效"
	return ""
