extends "res://game/tea_playtest/tea_playtest_sim.gd"
## Business rules preserve physical goods from collection to service.
const CONFIG = preload("res://content/tea/tea.tres")
## The art shop opens its line one machine group at a time; the legacy GameSim keeps tea.tres stages.
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
const SAVE_VERSION := 5
## What the lemonade stand's old levels 6–10 cost; v4 saves above Lv5 get it back.
const LEMONADE_V4_COSTS := [20, 30, 40, 55, 75, 110, 150, 210, 295]
## A waiting customer gets impatient, then angry; they never leave (the face just pushes the player to upgrade).
const BOIL_CAPACITY := 12
const MOOD_IMPATIENT := 15.0
const MOOD_ANGRY := 30.0
const ARTS := ["cat", "raccoon", "fox", "rabbit"]
const ALIASES := {"cabinet": "supply", "brewer": "boil", "milk_station": "mix", "lemonade_stand": "lemonade"}
const RESOURCE_IDS := {"supply": "cabinet", "boil": "brewer", "mix": "milk_station", "topping": "topping", "lemonade": "lemonade_stand", "counter": "counter"}
const DISHES := ["lemonade", "black_tea", "plain_milk_tea", "pearl_milk_tea", "coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea"]
const MACHINE_IDS := ["supply", "boil", "mix", "topping", "seal", "lemonade", "counter"]

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
var diners: Array = []
var _flavor_cursor := 0
## Bought conveyor segments (BeltSlotDef ids) and each one's countdown to its next cup.
var belts: Dictionary = {}
var belt_clock: Dictionary = {}
## The game no longer offers belts (2026-10-30); the segment rules stay so they can come back.
const BELTS_IN_GAME := false
var _belt_courier := false
var _rng: RandomNumberGenerator

func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = CONFIG.random_seed
	if workers.is_empty(): _add_worker()
	roster = workers.duplicate()
	for worker in roster:
		worker.deployed = true
		worker.source = "初始"
	_initialize_shop()

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
	material_levels = {"supply": {"tea_leaf": 1, "milk": 1}, "topping": {"pearl": 1, "coconut": 1, "redbean": 1, "taro": 1}}
	boxes = {"tea_leaf": false, "milk": false}
	seats = PROGRESSION.seat_start
	diners.clear()
	for id in ["boil", "mix", "topping", "seal"]:
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
	# The sealer packs takeaway cups of any drink, one at a time.
	for dish in DISHES:
		stations.seal.input[dish] = 0
		stations.seal.output[dish] = 0
		if not dish in ["lemonade", "black_tea", "plain_milk_tea"]: stations.topping.output[dish] = 0

func _make_worker(index: int) -> Dictionary:
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

func reset_shop() -> void:
	workers.clear()
	var starter: int = roster[0].id
	for worker in roster:
		var fresh := _new_staff(worker.art, worker.id)
		for key in ["name", "level", "speed", "capacity", "skill", "source"]: fresh[key] = worker[key]
		fresh.deployed = worker.id == starter
		worker.clear()
		worker.merge(fresh)
		if worker.deployed: workers.append(worker)
	_initialize_shop()

func all_workers() -> Array:
	return roster

func worker_by_id(id: int) -> Dictionary:
	for worker in roster:
		if worker.id == id: return worker
	return {}

func acquire_staff(art: String, source: String) -> String:
	if not art in ARTS: return "未知员工类型"
	if source.strip_edges().is_empty(): return "员工来源不能为空"
	# The first of each animal keeps its old id (cat 1 to rabbit 4); repeats number on from there.
	var id := ARTS.find(art) + 1
	var next_id := ARTS.size() + 1
	for owned in roster:
		next_id = maxi(next_id, owned.id + 1)
		if owned.id == id: id = -1
	var worker := _new_staff(art, id if id > 0 else next_id)
	worker.source = source
	worker.deployed = false
	roster.append(worker)
	_event("acquired", "获得员工：" + worker.name)
	return ""

func deployment_error(id: int) -> String:
	var worker := worker_by_id(id)
	if worker.is_empty(): return "未拥有这位员工"
	if worker.deployed: return ""
	if workers.size() >= staff_slots():
		var more := ""
		for next in range(stage_index + 1, PROGRESSION.stages.size()):
			if PROGRESSION.stages[next].staff_slots > staff_slots():
				more = "，解锁%s后可再派 %d 位" % [PROGRESSION.stages[next].line_name, PROGRESSION.stages[next].staff_slots - staff_slots()]
				break
		return "店内最多派出 %d 位员工%s" % [staff_slots(), more]
	return ""

## How many staff may work in the shop at once; each production line opens more room.
func staff_slots() -> int:
	return PROGRESSION.stages[stage_index].staff_slots

func deploy_worker(id: int) -> String:
	var error := deployment_error(id)
	if not error.is_empty(): return error
	var worker := worker_by_id(id)
	if worker.deployed: return ""
	worker.deployed = true
	workers.append(worker)
	_event("deployed", worker.name + "已派出")
	return ""

func _placement_error(id: int, post: String, point: Vector2) -> String:
	var error := deployment_error(id)
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
	deploy_worker(id)
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

func train_cost(id: int) -> int:
	var worker := worker_by_id(id)
	return -1 if worker.is_empty() else 25 * worker.level

func train(id: int) -> bool:
	var price := train_cost(id)
	if price < 0 or gold < price: return false
	var worker := worker_by_id(id)
	gold -= price
	worker.level += 1
	match worker.role:
		"speed": worker.speed += 18.0
		"carry": worker.capacity += 1
		"skill": worker.skill += 0.35
	_event("trained", worker.name + "已培养")
	return true

func _canonical(id: String) -> String:
	return ALIASES.get(id, id)

func _definition(id: String):
	var resource_id: String = RESOURCE_IDS.get(_canonical(id), "")
	for slot in CONFIG.slots:
		if slot.station.id == resource_id: return slot.station
	for spot in CONFIG.front_spots:
		if spot.station.id == resource_id: return spot.station
	return null

func station_unlocked(id: String) -> bool:
	return unlocked_stations.get(_canonical(id), false)

## Each stage opens one machine; the cabinet is furniture and its boxes are bought separately.
const STAGE_MACHINES := [[], ["boil"], ["seal"], ["mix"], ["topping"]]

func _unlock_stage(id: String) -> int:
	for stage in STAGE_MACHINES.size():
		if id in STAGE_MACHINES[stage]: return stage
	return 0

func _unlock_error(id: String) -> String:
	if not id in MACHINE_IDS: return "未知设备"
	if station_unlocked(id): return "设备已经解锁"
	var stage := _unlock_stage(id)
	if stage > 0:
		if not station_unlocked("lemonade"): return "请先解锁柠檬茶台"
		if stage > stage_index + 1: return "请先解锁" + PROGRESSION.stages[stage - 1].line_name
		var definition = PROGRESSION.stages[stage]
		if revenue < definition.revenue_threshold: return "营业额需达到 %d" % definition.revenue_threshold
	if gold < _unlock_cost(id): return "金币不足，需要 %d" % _unlock_cost(id)
	return ""

func _unlock_cost(id: String) -> int:
	if id == "lemonade":
		for spot in CONFIG.front_spots:
			if spot.station.id == "lemonade_stand": return spot.unlock_cost
	if id in ["boil", "mix", "seal", "topping"]: return PROGRESSION.stages[_unlock_stage(id)].line_cost
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
	var index := seats - PROGRESSION.seat_start
	return PROGRESSION.seat_costs[index] if index >= 0 and index < PROGRESSION.seat_costs.size() else -1

func seat_max() -> int:
	return PROGRESSION.seat_start + PROGRESSION.seat_costs.size()

func seat_error() -> String:
	if not station_unlocked("lemonade"): return "请先解锁柠檬茶台"
	if seat_cost() < 0: return "座位已满"
	if gold < seat_cost(): return "金币不足，需要 %d" % seat_cost()
	return ""

func buy_seat() -> String:
	var error := seat_error()
	if not error.is_empty(): return error
	gold -= seat_cost()
	seats += 1
	_event("seat_added", "加了一张座位")
	return ""

## Seats neither occupied nor promised to a dine-in cup on its way.
func free_seats() -> int:
	var promised := 0
	for worker in workers:
		if not worker.job.is_empty() and worker.job.kind == "serve" and worker.job.src != "seal": promised += 1
	return seats - diners.size() - promised

## 0 calm, 1 impatient, 2 angry.
func order_mood(order: Dictionary) -> int:
	return 2 if order.wait >= MOOD_ANGRY else (1 if order.wait >= MOOD_IMPATIENT else 0)

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
			materials.append(row)
	var descriptions := {"supply": "店里的原料柜。茶叶箱、牛奶箱跟着机器解锁，升级提高售价", "boil": "人工装料、煮茶、取茶；开局一锅 2 杯，升级轮流加杯和提速", "mix": "自动将茶汤调成原味奶茶；开了以后茶汤分给红茶和奶茶", "topping": "人工加料，口味随设备等级开放", "seal": "外带的杯子都要来这里封口；升级封得更快，5 级、10 级各加一个封口位", "lemonade": "服务员到展示柜现取柠檬茶", "counter": "客人在这里点单取杯。堂食要有空座位，加座位能多坐几位"}
	var effects := {"boil": "煮茶速度", "mix": "售价", "topping": "加料速度", "lemonade": "售价", "seal": "封口速度"}
	var speeds: Array = [1.0]
	if definition != null: speeds = definition.art_speeds if _art_mode(definition) and not definition.art_speeds.is_empty() else definition.level_speed
	var next_flavor := ""
	if definition != null:
		for material in definition.materials:
			if material.unlock_level == level + 1: next_flavor = material.display_name
	var stage := _unlock_stage(id)
	var seating := {}
	# Dine-in seats are bought at the counter.
	if id == "counter": seating = {"seats": seats, "seat_max": seat_max(), "diners": diners.size(), "seat_cost": seat_cost(), "seat_error": seat_error()}
	# Capacity machines (brewer, sealer, topping) speed up the line; price machines raise what each cup earns.
	seating.kind = "capacity" if id in ["boil", "seal", "topping"] else ("price" if id in ["lemonade", "mix", "supply"] else "")
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
		"unlock_revenue": PROGRESSION.stages[stage].revenue_threshold if stage > 0 else 0,
		"line_name": PROGRESSION.stages[stage].line_name if stage > 0 else name, "line_members": line,
		"unlock_note": PROGRESSION.stages[stage].unlock_note if stage > 0 else "",
		"dish_name": dish_name(PROGRESSION.stages[stage].dish_id), "dish_price": _base_price(PROGRESSION.stages[stage].dish_id),
		"price": _price_preview(id, "", upgrade_cost >= 0) if _art_mode(definition) and definition.art_price_step > 0 else {},
		"seconds": definition.art_seconds / speeds[level - 1] if _art_mode(definition) and definition.art_seconds > 0 else -1.0,
		"next_seconds": definition.art_seconds / speeds[level] if _art_mode(definition) and definition.art_seconds > 0 and upgrade_cost >= 0 else -1.0}.merged(seating, true)

## What one more level is worth, shown on a sample cup the player already sells.
func _price_preview(id: String, material: String, has_next: bool) -> Dictionary:
	var source = _definition(id) if material.is_empty() else _definition(id).material(material)
	var dishes: Array = source.art_price_dishes
	var step: float = source.art_price_step
	var sample := ""
	for dish in ["lemonade", "black_tea", "plain_milk_tea"]:
		if dish in dishes: sample = dish
	for dish in ["plain_milk_tea", "black_tea", "lemonade"]:
		if dish in dishes and _dish_unlocked(dish):
			sample = dish
			break
	var names: Array = []
	if "lemonade" in dishes: names.append("柠檬茶")
	if "black_tea" in dishes: names.append("红茶")
	if "plain_milk_tea" in dishes: names.append("奶茶")
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
	if not station_unlocked("lemonade"): return {"text": "解锁柠檬茶台，开始营业", "current": 0, "target": 1}
	var box := pending_box()
	if not box.is_empty(): return {"text": "解锁%s箱" % _box_def(box).display_name, "current": mini(gold, _box_def(box).box_cost), "target": _box_def(box).box_cost}
	if stage_index < PROGRESSION.stages.size() - 1:
		var stage = PROGRESSION.stages[stage_index + 1]
		if revenue < stage.revenue_threshold: return {"text": "营业额 · 解锁" + stage.line_name, "current": revenue, "target": stage.revenue_threshold}
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

func current_goal() -> String:
	if not station_unlocked("lemonade"): return "支付 10 金币解锁柠檬茶台，开始营业"
	var box := pending_box()
	if not box.is_empty(): return "支付 %d 金币在原料柜解锁%s箱" % [_box_def(box).box_cost, _box_def(box).display_name]
	if stage_index < PROGRESSION.stages.size() - 1:
		var stage = PROGRESSION.stages[stage_index + 1]
		if revenue < stage.revenue_threshold: return "营业额 %d / %d，随后解锁%s" % [revenue, stage.revenue_threshold, stage.line_name]
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
			return (seconds if seconds > 0 else 7.0) / _speed("boil") / _speed("supply") / _material_bonus("supply", "tea_leaf")
		"mix": return 4.0 / _speed("mix") / _material_bonus("supply", "milk")
	return seal_seconds()

## Time per takeaway cup at the sealer: faster per level, and each extra slot (stars at Lv5 / Lv10) adds another cup at once.
func seal_seconds(level: int = -1) -> float:
	var lv: int = station_levels.seal if level < 0 else level
	var speed: float = PROGRESSION.seal_speeds[mini(lv, PROGRESSION.seal_speeds.size()) - 1]
	return PROGRESSION.seal_seconds / speed / seal_slots(lv)

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
	if job.item == "lemonade" and job.src == "supply": return _definition("lemonade").cycle_seconds / _speed("lemonade") / _skill(worker)
	if job.kind == "topping": return _topping_seconds() * job.count / _skill(worker) / _speed("topping")
	if job.kind == "stir": return STIR_SECONDS / _skill(worker)
	if job.kind == "load_boil": return 0.6 / _skill(worker) / _speed("supply") / _material_bonus("supply", "tea_leaf")
	return super._action_duration(job, worker)

## Seconds of hand work per cup at the topping machine (its art_seconds; 2 when unset).
func _topping_seconds() -> float:
	var seconds: float = _definition("topping").art_seconds
	return seconds if seconds > 0 else 2.0

func _order_interval() -> float:
	return PROGRESSION.stages[stage_index].customer_interval

func _queue_capacity() -> int:
	return PROGRESSION.stages[stage_index].queue_capacity

func _tick() -> void:
	super._tick()
	_run_belts()
	for index in range(diners.size() - 1, -1, -1):
		diners[index].left -= STEP
		if diners[index].left <= 0.000001: diners.remove_at(index)
	# Customers never leave. Once the sealer is open, someone who wants to sit but finds no seat takes it away.
	if station_unlocked("seal"):
		var free := free_seats()
		for order in orders:
			if order.reserved or order.get("takeaway", false): continue
			if free > 0: free -= 1
			else: order["takeaway"] = true

func _shelf_capacity() -> int:
	# ShopConfig defines capacity per item, while the base audit needs a total.
	var flavors := 0
	for dish in DISHES:
		if dish != "lemonade" and _dish_unlocked(dish): flavors += 1
	return CONFIG.shelf_capacity * maxi(1, flavors)

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
	return CONFIG.shelf_capacity - committed

func _candidate(kind: String, source: String, destination: String, item: String, worker: Dictionary, priority: float, belt: String = "") -> Dictionary:
	var job := super._candidate(kind, source, destination, item, worker, priority, belt)
	if not job.is_empty() and destination == "shelf":
		job.count = mini(job.count, _shelf_item_free(_shelf_item(item)))
		if job.count <= 0: return {}
	return job

func _dish_unlocked(dish: String) -> bool:
	if dish == "lemonade": return station_unlocked("lemonade")
	if dish == "black_tea": return _brew_ready()
	if dish == "plain_milk_tea": return _mix_ready()
	for material in _definition("topping").materials:
		if material.item_id == dish: return station_unlocked("topping") and station_levels.topping >= material.unlock_level
	return false

func _add_order() -> void:
	if _rng == null or not station_unlocked("lemonade"): return
	var weights: Dictionary = PROGRESSION.stages[stage_index].order_weights
	var total := 0.0
	for dish in weights:
		if _dish_unlocked(dish): total += weights[dish]
	if total <= 0: return
	var sample := _rng.randf() * total
	var selected := "lemonade"
	for dish in weights:
		if not _dish_unlocked(dish): continue
		sample -= weights[dish]
		if sample <= 0:
			selected = dish
			break
	var takeaway := station_unlocked("seal") and _rng.randf() < PROGRESSION.stages[stage_index].takeaway_share
	orders.append({"id": _next_order, "wait": 0.0, "reserved": false, "dish": selected, "takeaway": takeaway})
	_next_order += 1

func _source_point(job: Dictionary) -> Vector2:
	if job.item == "lemonade" and job.src == "supply": return Vector2(330, 910)
	return super._source_point(job)

func _available(source: String, item: String) -> int:
	if source == "supply": return 999
	if source == "shelf":
		var reserved := 0
		for worker in workers:
			if not worker.job.is_empty() and worker.job.src == "shelf" and worker.job.item == item and worker.carry_count == 0: reserved += worker.job.count
		return int(shelf_stock.get(item, 0)) - reserved
	var station: Dictionary = stations[source]
	var stock: Dictionary = station.input if (source == "boil" and item == "raw") or (source == "topping" and item == "plain_milk_tea") else station.output
	return int(stock.get(item, 0)) - int(station.reserved_out.get(item, 0))

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
			count = mini(worker.capacity, mini(_available(post, item), _topping_room()))
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
	if worker.post == "topping": return _topping_segment(worker, result)
	if worker.post == "boil": return _boil_segment(worker, result)
	if not worker.post.is_empty() and worker.post != "counter": return result
	# Once someone staffs the counter, mobile staff leave customers to them and stay in the kitchen.
	var front_staffed: bool = worker.post.is_empty() and post_owner("counter") != -1
	var seats_left := free_seats()
	for order in orders:
		if order.reserved or front_staffed: continue
		# Takeaway cups are handed over from the sealer; dine-in cups need a free seat.
		var source: String = "seal" if order.get("takeaway", false) else ("supply" if order.dish == "lemonade" else "shelf")
		if not order.get("takeaway", false):
			if seats_left <= 0: continue
		var serve := _candidate("serve", source, "counter", order.dish, worker, 110)
		if serve.is_empty(): continue
		if not order.get("takeaway", false): seats_left -= 1
		serve.count = 1
		serve.order_id = order.id
		serve.priority += minf(20, order.wait * 0.1)
		result.append(serve)
	_append_pack_jobs(worker, result)
	if worker.post == "counter" or not station_unlocked("boil"): return result
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
			if not dish in ["lemonade", "plain_milk_tea", "black_tea"]: result.append(_candidate("carry_to_shelf", "topping", "shelf", dish, worker, 84))
	return _boost_kitchen(result)

## Takeaway cups still to be packed for each drink: waiting takeaway orders minus cups already at or headed to the sealer.
func _pack_need(dish: String) -> int:
	var need := 0
	for order in orders:
		if order.get("takeaway", false) and not order.reserved and order.dish == dish: need += 1
	var seal: Dictionary = stations.seal
	need -= int(seal.input[dish]) + int(seal.output[dish]) - int(seal.reserved_out.get(dish, 0))
	if seal.processing_item == dish: need -= seal.processing
	for other in workers:
		if not other.job.is_empty() and other.job.kind == "carry_to_seal" and other.job.item == dish: need -= other.job.count
	return need

## A takeaway cup is fetched from the shelf (or poured at the lemonade stand) and carried to the sealer.
func _append_pack_jobs(worker: Dictionary, result: Array) -> void:
	if not station_unlocked("seal"): return
	for dish in DISHES:
		var need := _pack_need(dish)
		if need <= 0: continue
		var job := _candidate("carry_to_seal", "supply" if dish == "lemonade" else "shelf", "seal", dish, worker, 100)
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
		if not dish in ["lemonade", "plain_milk_tea", "black_tea"]: result.append(_candidate("carry_to_shelf", "topping", "shelf", dish, worker, 84))
	return _boost_kitchen(_without_belted(result))

const SEATED_BONUS := 1.3

func _walk_speed(worker: Dictionary) -> float:
	return worker.speed * (SEATED_BONUS if worker.post in ["topping", "boil"] else 1.0)

func _skill(worker: Dictionary) -> float:
	return worker.skill * (SEATED_BONUS if worker.post in ["topping", "boil"] else 1.0)

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
		if not order.reserved and order.dish != "lemonade" and shelf_stock.get(order.dish, 0) == 0: starving += 1
	if starving == 0: return result
	for job in result:
		if not job.is_empty() and job.kind != "serve": job.priority += minf(90.0, 45.0 * starving)
	return result

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
	var flavors: Array = []
	for material in _definition("topping").materials:
		if station_levels.topping >= material.unlock_level: flavors.append(material.item_id)
	for unused in job.count:
		for attempt in flavors.size():
			var dish: String = flavors[_flavor_cursor % flavors.size()]
			_flavor_cursor += 1
			if _flavor_inventory(dish) >= _definition("topping").flavor_cap: continue
			station.output[dish] += 1
			break

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
	if destination == "shelf": shelf_stock[_shelf_item(item)] += count
	super._deliver(destination, item, count)

func _cancel_job(worker: Dictionary) -> void:
	if not worker.job.is_empty() and worker.job.src == "shelf" and worker.carry_count > 0:
		shelf_stock[worker.job.item] += worker.carry_count
	super._cancel_job(worker)

func _dish_price(dish: String) -> int:
	var price := _base_price(dish)
	# Price upgrades multiply: each level ×(1 + step), each star ×star_mult, across machines and ingredients.
	var bonus := 1.0
	for id in ["lemonade", "boil", "mix", "supply"]:
		var definition = _definition(id)
		if _art_mode(definition) and dish in definition.art_price_dishes:
			bonus *= pow(1.0 + definition.art_price_step, station_levels[id] - 1) * pow(definition.art_star_mult, stars(id))
		for material in definition.materials:
			if _art_mode(material) and dish in material.art_price_dishes: bonus *= pow(1.0 + material.art_price_step, material_levels[id][material.id] - 1)
	var flavor := 1.0
	for material in _definition("topping").materials:
		if material.item_id == dish: flavor = _material_bonus("topping", material.id)
	return roundi(price * bonus * flavor)

func _record_sale(job: Dictionary) -> void:
	# A cup handed over from the shelf or the stand is drunk here: the customer takes a seat for a while.
	if job.src != "seal":
		var taken: Array = diners.map(func(diner: Dictionary) -> int: return diner.seat)
		var seat := 0
		while seat in taken: seat += 1
		diners.append({"seat": seat, "dish": job.item, "left": PROGRESSION.seat_seconds})
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
		"boxes": boxes.duplicate(true), "seats": seats, "diners": diners.duplicate(true)}

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
	diners = state.diners.duplicate(true)
	_rng.state = state.rng_state

func load_dict(state: Dictionary) -> String:
	if state.get("version") is int and state.version == 3:
		state = _migrate_v3(state)
		state.version = 4
	if state.get("version") is int and state.version == 4: state = _migrate_v4(state)
	var error := _validate_state(state)
	if not error.is_empty(): return error
	var candidate = get_script().new()
	candidate._apply_state(state)
	var report: Dictionary = candidate.audit()
	if not report.valid: return "存档库存或预留不一致：%s" % report.errors
	_apply_state(state)
	return ""

## v4 → v5: the brewer pot holds up to six cups, and lemonade levels above the new cap are refunded.
func _migrate_v4(old: Dictionary) -> Dictionary:
	var state: Dictionary = old.duplicate(true)
	state.version = SAVE_VERSION
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
	state.stage_index = [0, 2, 3, 4][clampi(old_stage, 0, 3)] if lemon else 0
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
			return job.dst == "counter" and job.count == 1 and job.belt == "" and ((job.src == "supply" and job.item == "lemonade") or (job.src == "shelf" and job.item in DISHES and job.item != "lemonade") or (job.src == "seal" and job.item in DISHES))
		"brew_start": return job.src == "boil" and job.dst == "boil" and job.item == "raw" and job.count >= 1 and job.count <= 6 and job.belt == ""
		"brew_take", "stir": return job.src == "boil" and job.dst == "boil" and job.item == "tea" and job.count >= 1 and job.count <= 6 and job.belt == ""
		"topping": return job.src == "topping" and job.dst == "topping" and job.item == "plain_milk_tea" and job.belt == ""
		"load_boil": return job.src == "supply" and job.dst == "boil" and job.item == "raw" and job.belt == ""
		"unload_boil": return job.src == "boil" and job.dst == "mix" and job.item == "tea" and job.belt == ""
		"transfer_to_topping": return job.src == "mix" and job.dst == "topping" and job.item == "plain_milk_tea" and job.belt == ""
		"carry_to_seal":
			return job.dst == "seal" and job.belt == "" and ((job.src == "supply" and job.item == "lemonade") or (job.src == "shelf" and job.item in DISHES and job.item != "lemonade"))
		"carry_to_shelf":
			return job.dst == "shelf" and job.belt == "" and ((job.src == "boil" and job.item == "tea") or (job.src == "mix" and job.item == "plain_milk_tea") or (job.src == "topping" and job.item in DISHES and not job.item in ["lemonade", "black_tea", "plain_milk_tea"]))
	return false

func _validate_state(state: Dictionary) -> String:
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
	if state.stations.size() != 4: return "机器状态不完整"
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
	# Saves from before per-stage slots could deploy three at any stage.
	var slots := 3
	if state.stage_index is int and state.stage_index >= 0 and state.stage_index < PROGRESSION.stages.size():
		slots = maxi(slots, PROGRESSION.stages[state.stage_index].staff_slots)
	if state.roster.is_empty() or state.deployed.size() > slots: return "员工名册无效"
	var ids: Array = []
	for worker in state.roster:
		if not worker is Dictionary: return "员工字段无效"
		# Jobs have their own variable schema; every other worker field is fixed.
		var fields: Dictionary = worker.duplicate()
		if not fields.has("job") or not fields.job is Dictionary: return "员工运单无效"
		fields.job = {}
		if not _same_shape(fields, worker_sample): return "员工字段无效"
		if not worker.art in ARTS or worker.id < 1 or worker.id in ids: return "员工身份无效"
		ids.append(worker.id)
		if worker.level < 1 or worker.speed <= 0 or worker.skill <= 0 or worker.capacity < 1 or worker.carry_count < 0 or worker.carry_count > worker.capacity: return "员工能力或货物无效"
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
			if not job.kind in ["serve", "topping", "brew_start", "brew_take", "stir", "load_boil", "unload_boil", "transfer_to_topping", "load_seal_belt", "carry_to_seal", "load_shelf_belt", "carry_to_shelf"]: return "员工任务无效"
			if not job.src in ["supply", "shelf", "boil", "mix", "topping", "seal"] or not job.dst in ["boil", "mix", "topping", "seal", "shelf", "counter"]: return "员工运输端点无效"
			if not job.item in DISHES + ["raw", "tea"] or job.count <= 0: return "员工运单货物无效"
			if not job.belt in ["", "topping_to_seal", "seal_to_shelf"]: return "员工传送带无效"
			if not _valid_job_route(job): return "员工运单路线或口味无效"
			if _is_operation(job):
				if not worker.phase in ["walk_pickup", "work"]: return "人工操作阶段无效"
			elif worker.phase == "work": return "运输任务不能进行机器操作"
			if worker.post == "counter" and not job.kind in ["serve", "carry_to_seal"]: return "员工岗位与任务不一致"
			if not worker.post in ["", "counter"] and not _post_job(worker.post, job): return "员工岗位与任务不一致"
			if not _is_operation(job) and job.count > worker.capacity: return "员工运单超过搬运能力"
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
		if not order is Dictionary or not _same_shape(order, {"id": 1, "wait": 0.0, "reserved": false, "dish": "", "takeaway": false}): return "订单字段无效"
		if order.id < 1 or order.id >= state.next_order or order.id in order_ids or order.wait < 0 or not order.dish in DISHES: return "订单内容无效"
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
			var stock: Dictionary = station.input if (id == "boil" and item == "raw") or (id == "topping" and item == "plain_milk_tea") else station.output
			if station.reserved_out[item] > stock.get(item, 0): return "取货预留超过实际库存"
	for shipment in state.belt_items:
		var sample := {"route": "", "item": "", "count": 1, "progress": 0.0, "duration": 1.0, "dst": ""}
		if not shipment is Dictionary or not _same_shape(shipment, sample): return "传送带字段无效"
		var route = _belt_def(shipment.route)
		if route == null or not shipment.item in DISHES + ["raw", "tea"] or shipment.item == "lemonade" or shipment.count <= 0 or shipment.duration <= 0 or shipment.progress < 0 or shipment.progress >= 1: return "传送带内容无效"
		if shipment.dst != route.to: return "传送带终点不一致"
	if not _same_shape(state.boxes, template.boxes): return "原料箱字段无效"
	for material in state.boxes:
		var machine := _canonical(_box_def(material).box_machine)
		if state.boxes[material] and not state.unlocked_stations[machine]: return "原料箱解锁状态无效"
	if state.seats < PROGRESSION.seat_start or state.seats > seat_max() or state.diners.size() > state.seats: return "座位无效"
	var seat_ids: Array = []
	for diner in state.diners:
		if not diner is Dictionary or not _same_shape(diner, {"seat": 0, "dish": "", "left": 0.0}): return "堂食客人字段无效"
		if diner.seat < 0 or diner.seat >= state.seats or diner.seat in seat_ids or not diner.dish in DISHES or diner.left < 0 or diner.left > PROGRESSION.seat_seconds + 0.000001: return "堂食客人无效"
		seat_ids.append(diner.seat)
	for event in state.events:
		if not event is Dictionary or not _same_shape(event, {"kind": "", "text": ""}): return "事件字段无效"
	return ""
