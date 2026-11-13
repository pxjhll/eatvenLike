class_name ShopView
extends RefCounted
## 快照（规格 §3.11）：界面只从这里读数据、只通过 ShopRules 的命令改数据。
## 这里把规则层状态拼成界面用的字典：机器面板、目标、任务、员工、招人、瓶颈、进行中加成。
## 所有文案模板来自店铺数据（goals.texts、机器说明、升级轨标签），这里不出现任何店铺、机器、菜品的名字。

var rules: ShopRules
var shop: SpecShop
var message_formatter: Callable

const CommandResult := preload("res://game/rules/rule_command_result.gd")
const CommandText := preload("res://content/ui/rule_command_text.gd")
const Numbers := preload("res://game/rules/rule_numbers.gd")
const Production := preload("res://game/rules/production_plan.gd")
const SceneFrame := preload("res://game/rules/template/scene_frame.gd")
var _runtime_binding: RefCounted
var _follows_owner := false
var _runtime: RefCounted:
	get: return rules.runtime if _follows_owner else _runtime_binding
	set(value): _runtime_binding = value
var _displays: Array = []
var _presentation: Dictionary = {}
const TemplatePresentation := preload("res://game/rules/template/presentation.gd")

## 升级效果 → 面板上“这一级做什么”的分类
const KIND_TEXT := {"capacity": "产能升级", "price": "售价升级", "menu": "开新口味", "both": "产能售价升级"}
const CAPACITY_KINDS := ["speed", "duration", "batch", "process_slots"]


func _init(rules_: ShopRules, message_formatter_: Callable = Callable()) -> void:
	rules = rules_
	shop = rules.shop
	message_formatter = message_formatter_
	_follows_owner = rules.runtime!=null


func command_message(status: Dictionary) -> String:
	if message_formatter.is_valid(): return str(message_formatter.call(status.duplicate(true), shop))
	return CommandText.format(status, shop)


# ---------- Detached presentation reads ----------

## Explicit presentation dependency. The session/controller owns simulation
## advancement and saving; binding a view never starts or replaces a loop.
func bind_runtime(runtime: RefCounted, displays: Array = [], geometry: Dictionary = {}) -> String:
	if runtime==null or not runtime.get("runner") is RefCounted or runtime.runner.owner!=rules: return "presentation runtime belongs to another owner"
	if not String(runtime.last_error).is_empty(): return String(runtime.last_error)
	var resolved := TemplatePresentation.resolve(runtime._definition.get("presentation",{}),geometry)
	if not resolved.error.is_empty(): return resolved.error
	var combined: Array = resolved.definition.get("stock",[])+displays
	var frame: Dictionary = runtime.frame(combined)
	if not String(frame.error).is_empty(): return String(frame.error)
	_runtime = runtime
	_follows_owner = runtime==rules.runtime
	_displays = combined.duplicate(true)
	_presentation = resolved.definition
	return ""

## One caller-owned frame, in the simulation's existing iteration order.
func render_snapshot() -> Dictionary:
	if _runtime!=null: return SceneFrame.build(_runtime,_displays,_presentation)
	var frame := {"clock": rules.clock, "gold": rules.gold, "revenue": rules.revenue, "sold": rules.sold,
		"lost": rules.lost, "paused": rules.paused, "stage_index": rules.stage_index,
		"completed_at": rules.completed_at, "shelf_count": rules.shelf_count,
		"workers": rules.workers, "roster": rules.roster, "stations": rules.stations,
		"shelf_stock": rules.shelf_stock, "orders": rules.orders, "customers": rules.customers,
		"queue": rules.queue, "diners": rules.diners, "belts": rules.belts,
		"belt_items": rules.belt_items, "seats": rules.seats, "serve": rules.serve,
		"stage_queue_capacity": rules.current_stage().queue_capacity}
	if rules.movement_enabled(): frame.movement = rules.movement
	frame = frame.duplicate(true)
	if shop.fulfillment.flow_version==1:
		frame.flow = {"version":1,"delivery_batch":shop.fulfillment.delivery_batch,"bundles":{}}
		for key in rules.serve.jobs:
			var job: Dictionary = rules.serve.jobs[key]
			if job.kind!="bundle": continue
			frame.flow.bundles[key] = {"order":job.order,"goods":job.goods.duplicate(true),"capacity":job.capacity,"held":rules.worker_by_id(int(key)).carry_count}
	if shop.dispatch.action_version==1:
		frame.actions = {}
		for worker: Dictionary in frame.workers:
			if not worker.has("action"): continue
			var action: Dictionary = worker.action
			var step: Dictionary = action.steps[action.index]
			frame.actions[str(worker.id)] = {"status":action.status,"reason":action.reason,"kind":step.kind,"target":step.target,
				"index":action.index,"count":action.steps.size(),"remaining":worker.action_left}
	if rules.movement_enabled():
		for worker: Dictionary in frame.workers:
			worker.speed = rules.walk_speed(worker)/shop.layout.motion_units
			worker.walking = worker.walking and not worker.path.is_empty()
	return frame


func roster_snapshot() -> Array:
	if _runtime!=null:
		var active := {}
		for worker in render_snapshot().workers: active[worker.id] = worker
		var roster: Array = rules.roster.duplicate(true)
		for index in roster.size():
			if active.has(roster[index].id): roster[index] = active[roster[index].id]
		return roster
	return rules.roster.duplicate(true)

func production_snapshot(dish_id: String) -> Dictionary:
	if shop.fulfillment.flow_version!=1: return {}
	return Production.compile(shop,dish_id)


func deployed_snapshot() -> Array:
	if _runtime!=null: return render_snapshot().workers
	return rules.workers.duplicate(true)


func worker_snapshot(id: int) -> Dictionary:
	if _runtime!=null:
		for worker in roster_snapshot():
			if worker.id==id: return worker
		return {}
	return rules.worker_by_id(id).duplicate(true)


func customer_snapshot(id: int) -> Dictionary:
	if _runtime!=null:
		return render_snapshot().movement.customers.get("guest:"+str(id),{}).duplicate(true)
	return rules.customer(id).duplicate(true)


func deployed_count() -> int:
	return rules.workers.size()


func is_deployed(id: int) -> bool:
	var worker := rules.worker_by_id(id)
	return not worker.is_empty() and bool(worker.deployed)


func progress_snapshot() -> Dictionary:
	return {"levels": rules.levels.duplicate(true), "tune": rules.tune.duplicate(true)}


func activity_snapshot() -> Dictionary:
	if _runtime!=null: return SceneFrame.activity(_runtime)
	var idle := 0
	for worker in rules.workers:
		if rules.worker_idle(worker): idle += 1
	var working := {}
	for id in rules.pots + rules.autos: working[id] = rules.machine_working(id)
	return {"clock": rules.clock, "stage_index": rules.stage_index, "gold": rules.gold,
		"revenue": rules.revenue, "sold": rules.sold, "lost": rules.lost,
		"queue": rules.queue_size(), "queue_capacity": rules.queue_capacity(), "angry_count": rules.angry_count(),
		"staff_count": rules.workers.size(), "idle_count": idle, "machine_working": working,
		"seat_count": rules.seat_count(), "seats_used": rules.seats_used(), "customer_interval": rules.customer_interval()}


## Lost-customer bookkeeping belongs to the guide; only current rule facts live here.
func guide_snapshot() -> Dictionary:
	var group := rules.buy_group()
	return {"lost": rules.lost, "staff_count": rules.workers.size(),
		"seats_owned": int(rules.seats.get(group.id, 0)) if group != null else 0,
		"any_angry": rules.angry_count() > 0, "angry_cause": _guide_angry_cause(), "slow_machine": _guide_slow_machine()}


func _guide_angry_cause() -> String:
	if _runtime!=null:
		if rules.angry_count()==0: return ""
		var group := rules.buy_group()
		if group!=null and rules.seat_cost()>=0 and rules.seats_used()>=rules.seat_count(): return "seats"
		return "staff" if rules.workers.size()<rules.staff_slots() else "machine"
	if shop.fulfillment.handoff == "single":
		var group := rules.buy_group()
		if group != null and group.purpose == "wait" and rules.seat_cost() >= 0 and int(rules.seats.get(group.id, 0)) < rules.seat_cap(group): return "seats"
		if rules.workers.size() < rules.staff_slots(): return "staff"
		return "machine"
	var angry: Array = rules.orders.filter(func(order: Dictionary) -> bool: return rules.order_mood(order) >= 2)
	if angry.is_empty(): return ""
	var dine_in: bool = angry.any(func(order: Dictionary) -> bool: return not order.get("takeaway", false))
	if dine_in and rules.dine_group() != null and rules.free_seats() <= 0 and rules.seat_cost() >= 0: return "seats"
	if rules.workers.size() < rules.staff_slots(): return "staff"
	return "machine"


func _guide_slow_machine() -> String:
	if _runtime!=null:
		var oldest := {}
		for guest in _runtime.service.orders.active_snapshot().guests:
			if guest.state not in ["queue","waiting"] or guest.request.is_empty(): continue
			if oldest.is_empty() or guest.wait>oldest.wait: oldest = guest
		if not oldest.is_empty():
			var recipe: Dictionary = _runtime._definition.recipes[oldest.request[0].recipe]
			for unit in _runtime._units:
				if unit.recipe!=oldest.request[0].recipe: continue
				for node in recipe.nodes.values():
					if node.capability=="process" and node.id not in unit.done: return node.machine
			for node in recipe.nodes.values():
				if node.capability=="process": return node.machine
		return rules.counter_id
	if shop.fulfillment.handoff == "single":
		var dish := ""
		for id in rules.queue:
			dish = String(rules.customer(id).get("kind", ""))
			break
		if dish.is_empty() and not rules.dish_ids.is_empty(): dish = rules.dish_ids[0]
		var definition := shop.dish(dish)
		if definition != null:
			for step in definition.steps:
				var station := shop.station(step.station)
				if station != null and not station.tracks.is_empty() and rules.station_unlocked(station.id): return station.id
		return rules.counter_id
	var oldest: Dictionary = {}
	for order in rules.orders:
		if oldest.is_empty() or order.wait > oldest.wait: oldest = order
	var dish: String = oldest.get("dish", rules.dish_ids[0] if not rules.dish_ids.is_empty() else "")
	var chain: Array = rules.chains.get(dish, [])
	if not chain.is_empty() and not shop.dish(dish).front: return chain[0]
	var definition := shop.dish(dish)
	if definition != null:
		for step in definition.steps:
			var station := shop.station(step.station)
			if station != null and station.block != "counter": return station.id
	return rules.counter_id


func staff_kind(id: String) -> Dictionary:
	var kind := rules._kind(id)
	return {"id": kind.id, "display_name": kind.display_name, "role": kind.role,
		"description": kind.description, "stats": kind.stats.duplicate(true)}


func art_visible(rule: String) -> bool:
	if rule == "always": return true
	if rule.begins_with("belt:"): return rules.belts.has(rule.trim_prefix("belt:"))
	if rule == "ingredient_box": return rules.boxes.values().has(true)
	if rule.begins_with("box:"): return bool(rules.boxes.get(rule.trim_prefix("box:"), false))
	if rule.begins_with("flavor:"):
		var dish := shop.dish(rule.trim_prefix("flavor:"))
		return dish != null and rules.flavor_open(dish)
	if rule.begins_with("wait_seats:"): return rules.wait_seats() >= int(rule.get_slice(":", 1))
	if rule.begins_with("dine_seats:"): return rules.seat_total() >= int(rule.get_slice(":", 1))
	return rules.station_unlocked(rule)


func seat_count(group_id: String) -> int:
	for group in shop.seat_groups:
		if group.id==group_id: return mini(int(rules.seats.get(group_id,0)),rules.seat_cap(group))
	return 0


func post_point(id: String) -> Vector2:
	return rules.nav.post(id)


func navigation_point(id: String) -> Vector2:
	return rules.nav.point(id)


func walkable(point: Vector2, from: Vector2) -> bool:
	return rules.nav.walkable(point, from)


func tuning_limits() -> Dictionary:
	return Numbers.tuning_limits()


# ---------- 名字与文案 ----------

func dish_name(id: String) -> String:
	var dish := shop.dish(id)
	if dish != null: return dish.display_name
	return item_name(id)


func item_name(id: String) -> String:
	for item in shop.items:
		if item.id == id: return item.display_name
	return id


func station_name(id: String) -> String:
	var st := shop.station(id)
	return st.display_name if st != null else id


## 文案模板：goals.texts[key]，{键} 换成 values 里的值
func text(key: String, values: Dictionary = {}, fallback := "") -> String:
	var template: String = shop.goals.texts.get(key, fallback)
	for k in values: template = template.replace("{%s}" % k, str(values[k]))
	return template


## “13” 整数价、“13.2” 带一位小数
static func price_text(value: float) -> String:
	return "%d" % roundi(value) if is_equal_approx(value, roundf(value)) else "%.1f" % value


static func stat_text(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")


# ---------- 目标与任务（§3.9） ----------

## 当前目标：{text 顶栏短句, long 完整句, current, target, kind, id}
func goal() -> Dictionary:
	for step in shop.goals.order:
		match step:
			"open":
				if not rules.is_open():
					var id := shop.goals.opening_station
					var cost := shop.stages[0].cost
					return {"kind": "open", "id": id, "current": 0, "target": 1,
						"text": text("open_short", {"name": station_name(id), "cost": cost}, "解锁%s，开始营业" % station_name(id)),
						"long": text("open", {"name": station_name(id), "cost": cost})}
			"box":
				var box := rules.pending_box()
				if not box.is_empty():
					var m := shop.station(rules.supply_id).material(box)
					return {"kind": "box", "id": box, "current": mini(int(rules.gold), m.box_cost), "target": m.box_cost,
						"text": text("box_short", {"name": m.display_name, "cost": m.box_cost}, "解锁%s箱" % m.display_name),
						"long": text("box", {"name": m.display_name, "cost": m.box_cost})}
			"stage":
				if rules.stage_index < shop.stages.size() - 1:
					var stage := shop.stages[rules.stage_index + 1]
					return {"kind": "stage", "id": shop.sold_at(rules.stage_index + 1), "current": mini(int(rules.gold), stage.cost), "target": stage.cost,
						"text": text("stage_short", {"name": stage.display_name, "cost": stage.cost}, "攒金币 · 解锁" + stage.display_name),
						"long": text("stage", {"name": stage.display_name, "cost": stage.cost})}
			"tasks":
				for row in rules.task_rows():
					if not row.complete:
						return {"kind": "task", "id": row.id, "current": row.current, "target": row.target, "text": row.name,
							"long": text("task", {"name": row.name, "current": int(row.current), "target": int(row.target)})}
	return {"kind": "done", "id": "", "current": 1, "target": 1, "text": text("done_short", {}, "经营任务已全部完成"), "long": text("done")}


## 完店评分（1–3 星；没完店 0）：完店用时在 rating_minutes 以内各加一星，走掉的客人超过 rating_lost_share 扣一星
func rating() -> int:
	if rules.completed_at < 0.0: return 0
	var stars := 1
	var minutes := rules.completed_at / 60.0
	for limit in shop.goals.rating_minutes:
		if minutes <= limit: stars += 1
	var served := rules.sold + rules.lost
	if shop.goals.rating_lost_share > 0.0 and served > 0 and float(rules.lost) / served > shop.goals.rating_lost_share: stars -= 1
	return clampi(stars, 1, 3)


## 结店总结（§3.9）：{shop, seconds 完店用时, played, earned, sold, lost, top [[份数, 菜]…前 3], levels, staff, rating}
func summary() -> Dictionary:
	var top := []
	for dish in rules.sold_by_dish:
		if int(rules.sold_by_dish[dish]) > 0: top.append([int(rules.sold_by_dish[dish]), dish])
	top.sort()
	top.reverse()
	var levels := {}
	for st in shop.stations:
		var t := rules.track_of(st.id)
		if t != null and not t.levels.is_empty(): levels[st.id] = rules.level(st.id)
	return {"shop": shop.id, "seconds": rules.completed_at if rules.completed_at >= 0.0 else rules.clock, "played": rules.clock,
		"earned": int(rules.revenue), "sold": rules.sold, "lost": rules.lost, "top": top.slice(0, 3), "levels": levels,
		"staff": rules.roster.size(), "rating": rating()}


func tasks() -> Array:
	return rules.task_rows()


func stats() -> Dictionary:
	return {"sold": rules.sold, "revenue": int(rules.revenue), "lost": rules.lost, "clock": rules.clock,
		"shelf": rules.shelf_count, "shelf_limit": rules.shelf_capacity()}


# ---------- 机器面板（§6.2.1：面板按段拼，有什么段由这里决定） ----------

## 下一个要解锁的阶段（未开张 = 0）
func next_stage() -> int:
	return rules.stage_index + 1 if rules.is_open() else 0


## 一台机器的面板数据。段：header、unlock（未解锁）、track（主升级轨）、materials、seats、flyer。
func station(id: String) -> Dictionary:
	var st := shop.station(id)
	if st == null: return {}
	var stage := shop.stage_of(id)
	var unlocked := rules.station_unlocked(id)
	var card := {"id": id, "name": st.display_name, "block": st.block, "icon": st.icon if not st.icon.is_empty() else id,
		"description": st.description, "unlocked": unlocked, "stage": stage, "level": rules.level(id),
		"stars": rules.stars(id), "sections": []}
	var t := rules.track_of(id)
	card.max_stars = 0
	if t != null:
		for lv in t.levels: card.max_stars += 1 if lv.star else 0
	if not unlocked:
		card.sections.append("unlock")
		card.unlock = _unlock_section(id, stage)
		return card
	if t != null and not t.levels.is_empty():
		card.sections.append("track")
		card.track = track_row(id)
	if not shop.recipe_stages(id).is_empty():
		card.sections.append("recipes")
		card.recipes = shop.recipe_stages(id).map(func(index: int) -> Dictionary: return recipe_row(id, index))
	if not st.materials.is_empty():
		card.sections.append("materials")
		card.materials = st.materials.map(func(m: SpecMaterial) -> Dictionary: return material_row(st, m))
	if id == rules.counter_id:
		if rules.buy_group() != null:
			card.sections.append("seats")
			card.seats = seats()
		if shop.flyer != null:
			card.sections.append("flyer")
			card.flyer = flyer()
	return card


func _unlock_section(id: String, stage: int) -> Dictionary:
	var members: Array = []
	var note := ""
	var title := station_name(id)
	var dish := ""
	var cost := 0
	if stage >= 0:
		var def := shop.stages[stage]
		cost = def.cost
		note = def.unlock_note
		dish = def.dish
		if stage > 0: title = def.display_name
		for key in def.stations: members.append(station_name(key))
	var d := shop.dish(dish)
	var status := rules.command_status("unlock", {"id": id})
	return {"cost": cost, "status": status, "error": command_message(status), "title": title, "members": members, "note": note,
		"dish": dish_name(dish) if not dish.is_empty() else "", "dish_price": rules.dish_price(dish) if d != null else 0.0,
		"quote": rules.dish_quote(dish) if d != null else {},
		"description": "基础说明：" + shop.station(id).description, "frame": stage >= 0 and stage == next_stage()}


## 配方栏的一行：{stage, dish, name, cost, price, state(owned 已买 / next 下一个可买 / later 还没轮到), status, error}
func recipe_row(id: String, index: int) -> Dictionary:
	var def := shop.stages[index]
	var row := {"stage": index, "dish": def.dish, "name": dish_name(def.dish), "title": def.display_name, "cost": def.cost,
		"price": rules.dish_price(def.dish), "icon": def.dish, "note": def.unlock_note, "state": "later", "status": {}, "error": ""}
	if index <= rules.stage_index:
		row.state = "owned"
		return row
	row.status = rules.command_status("unlock", {"id": id})
	row.error = command_message(row.status)
	if index == rules.stage_index + 1 and rules.is_open(): row.state = "next"
	return row


## 一条升级轨的面板行：{key, title, kind, level, max, cost, error, now, next, effect, star_next}
## now / next = 面板上“当前 → 升级后”两格；effect = 底下一整句（手机没有悬停，整句直接写出来）
func track_row(key: String) -> Dictionary:
	var t := rules.track_of(key)
	var id := key.get_slice("/", 0)
	var level := rules.level(key) if not key.begins_with("staff/") else int(rules.levels[key]) + 1
	var cost := rules.upgrade_cost(key)
	var status := rules.command_status("upgrade", {"key": key})
	var row := {"key": key, "title": t.display_name, "label": t.effect_label, "level": level, "max": t.max_level(),
		"cost": cost, "status": status, "error": command_message(status), "star_next": false, "kind": "", "now": "Lv.%d" % level,
		"next": "满级" if cost < 0 else "Lv.%d" % (level + 1), "effect": ""}
	if cost >= 0: row.star_next = t.levels[level - 1].star
	var next_effects: Array = t.levels[level - 1].effects if cost >= 0 else []
	var kinds := {}
	for e in next_effects: kinds[e.kind] = true
	var capacity := kinds.keys().any(func(k: String) -> bool: return k in CAPACITY_KINDS)
	var price := kinds.has("price")
	row.kind = "both" if capacity and price else "capacity" if capacity else "price" if price else "menu" if kinds.has("open_flavor") else ""
	# 面板标题下那一行说的升级种类：数据里写了就用数据的
	row.heading_kind = t.kind if not t.kind.is_empty() else row.kind
	if key.begins_with("staff/") or key == "flyer": return row
	var st := shop.station(id)
	var unit: String = st.params.get("unit", "份")
	var timing := station_timing(id)
	var per := "基准每" + String(timing.unit)
	var preview := price_preview(key)
	var batch_now := rules.pot_batch(id) if st.block == "batch_pot" else 0
	var batch_next: int = rules.preview(key, func(query: RefCounted) -> int: return query.pot_batch(id)) if cost >= 0 and st.block == "batch_pot" else batch_now
	var slots_now := rules.process_slots(id) if st.block == "pickup" else 0
	var slots_next: int = rules.preview(key, func(query: RefCounted) -> int: return query.process_slots(id)) if cost >= 0 and st.block == "pickup" else slots_now
	var timed := st.block in ["batch_pot", "pickup"] or kinds.has("speed") or kinds.has("duration")
	var s_now := seconds(id)
	var s_next: float = rules.preview(key, func(query: RefCounted) -> float: return query.station_timing(id).seconds) if cost >= 0 else s_now
	# 两格对比：加杯 > 加位 > 涨价 > 提速
	if cost >= 0:
		if batch_next > batch_now:
			row.now = "%d %s / 锅" % [batch_now, unit]
			row.next = "%d %s / 锅" % [batch_next, unit]
		elif slots_next > slots_now:
			var label: String = st.params.get("slot_label", "加工位")
			row.now = "%d %s" % [slots_now, label]
			row.next = "%d %s" % [slots_next, label]
		elif not preview.is_empty():
			row.now = quote_primary(preview.quote_now)
			row.next = quote_primary(preview.quote_next)
		elif timed:
			var pot: String = timing.unit
			row.now = "%.1f 秒 / %s" % [s_now, pot]
			row.next = "%.1f 秒 / %s" % [s_next, pot]
	# Compose each numeric description once, then retain menu-opening information.
	var line := ""
	if not preview.is_empty():
		line = "%s · %s" % [preview.sample, quote_change(preview.quote_now, preview.quote_next, cost >= 0)]
		if preview.partial: line = "部分价格加成 · " + line
		if row.kind == "both": line += " · %s %.1f → %.1f 秒" % [per, s_now, s_next]
	elif batch_next > batch_now:
		line = "一锅 %d → %d %s" % [batch_now, batch_next, unit]
	elif slots_next > slots_now:
		line = "%s %d → %d" % [st.params.get("slot_label", "加工位"), slots_now, slots_next]
	elif timed:
		line = "%s %.1f 秒" % [per, s_now] if cost < 0 else "%s %.1f → %.1f 秒" % [per, s_now, s_next]
	elif cost < 0 and _opens_flavors(t): line = "口味全开"
	if timed: line += " · 基准操作，不含员工加成和行走"
	for e in next_effects:
		if e.kind == "open_flavor":
			var material := st.material(e.target)
			line += (" · " if not line.is_empty() else "") + "开放" + (material.display_name if material != null else e.target) + "，客人更多"
	row.effect = line
	return row


func _opens_flavors(t: SpecUpgradeTrack) -> bool:
	for lv in t.levels:
		for e in lv.effects:
			if e.kind == "open_flavor": return true
	return false


## 满级时显示的现状一句
func current_effect(id: String) -> String:
	var st := shop.station(id)
	match st.block:
		"batch_pot": return "一锅 %d %s · 每锅 %.1f 秒" % [rules.pot_batch(id), st.params.get("unit", "份"), seconds(id)]
		"pickup": return "%s %d · 每%s %.1f 秒" % [st.params.get("slot_label", "加工位"), rules.process_slots(id), st.params.get("unit", "份"), seconds(id)]
	var preview := price_preview(id)
	if not preview.is_empty(): return "%s · %s" % [preview.sample, quote_text(preview.quote_now)]
	return "已满级"


## 基准操作秒数（不含员工加成或行走），单位见 station_timing。
func seconds(id: String) -> float:
	return float(rules.station_timing(id).get("seconds", 0.0))


func station_timing(id: String) -> Dictionary:
	var timing := rules.station_timing(id)
	if timing.is_empty(): return {}
	var units := {"cooking_batch": "锅", "batch": "批", "operation": "次", "item": shop.station(id).params.get("unit", "份")}
	timing.unit = units[timing.unit]
	return timing


func timing_text(id: String) -> String:
	var timing := station_timing(id)
	return "基准 %.1f 秒 / %s" % [timing.seconds, timing.unit]


func quote_text(quote: Dictionary) -> String:
	var calculated := price_text(quote.calculated)
	if quote.has("solo_payment"):
		return "计算 %s 金 · 单点实收 %d 金" % [calculated, quote.solo_payment]
	return "单价 %s 金 · 小数累计" % calculated


func quote_primary(quote: Dictionary) -> String:
	return "单点实收 %d 金" % quote.solo_payment if quote.has("solo_payment") else "单价 %s 金" % price_text(quote.calculated)


func quote_change(now: Dictionary, next: Dictionary, changing := true) -> String:
	var calculated := price_text(now.calculated)
	if changing: calculated += " → " + price_text(next.calculated)
	if now.has("solo_payment"):
		var payment := str(now.solo_payment)
		if changing: payment += " → " + str(next.solo_payment)
		return "计算 %s 金 · 单点实收 %s 金（无加项）" % [calculated, payment]
	return "单价 %s 金 · 小数累计" % calculated


## 涨价预览：拿一道已经在卖的菜当例子，算真实售价（全部加成、同一取整）
func price_preview(key: String) -> Dictionary:
	var t := rules.track_of(key)
	if t == null: return {}
	var id := key.get_slice("/", 0)
	var st := shop.station(id)
	var scope: Array = st.price_dishes
	var level := rules.level(key)
	# 满级以后说的是最后一级的涨幅
	var shown: SpecUpgradeLevel = t.levels[mini(level, t.levels.size()) - 1] if level > 0 and not t.levels.is_empty() else null
	if shown != null:
		for e in shown.effects:
			if e.kind == "price" and not e.dishes.is_empty(): scope = e.dishes
	if scope.is_empty(): return {}
	var sample: String = scope[0]
	if not t.preview_dishes.is_empty():
		sample = t.preview_dishes[0]
		for dish in t.preview_dishes:
			if rules.dish_open(dish):
				sample = dish
				break
	else:
		for d in shop.dishes:
			if d.id in scope and rules.dish_open(d.id, false): sample = d.id
	var mult := 1.0
	var partial := false
	if shown != null:
		for e in shown.effects:
			if e.kind == "price" and e.op == "mul": mult *= e.value
			if e.kind == "price" and not e.price_part.is_empty(): partial = true
	var now := rules.dish_price(sample)
	var next: float = rules.preview(key, func(query: RefCounted) -> float: return query.dish_price(sample)) if level <= t.levels.size() else -1.0
	var quote_now := rules.dish_quote(sample)
	var quote_next: Dictionary = rules.preview(key, func(query: RefCounted) -> Dictionary: return query.dish_quote(sample)) if level <= t.levels.size() else quote_now
	var names: Array = []
	for d in shop.dishes:
		if d.id in scope: names.append(d.display_name)
	var out := {"scope": t.preview_label if not t.preview_label.is_empty() else "、".join(names), "sample": dish_name(sample), "now": now, "next": next, "mult": mult,
		"partial": partial, "quote_now": quote_now, "quote_next": quote_next}
	if quote_now.has("solo_payment"):
		out.payment_now = quote_now.solo_payment
		out.payment_next = quote_next.solo_payment
	return out


## 机器上的一个物料行：原料箱（先解锁箱）或口味（机器几级开放）
func material_row(st: SpecStation, m: SpecMaterial) -> Dictionary:
	var key := st.id + "/" + m.id
	var level := rules.level(key)
	var status := rules.command_status("upgrade", {"key": key})
	var row := {"id": m.id, "key": key, "name": m.display_name, "icon": m.icon if not m.icon.is_empty() else m.id,
		"level": level, "cost": rules.upgrade_cost(key), "status": status, "error": command_message(status), "state": "open",
		"requires": m.track.requires_level, "effect": ""}
	if rules.boxes.has(m.id) and not rules.boxes[m.id]:
		row.state = "box"
		row.cost = m.box_cost
		row.status = rules.command_status("unlock_box", {"material": m.id})
		row.error = command_message(row.status)
		row.box_station = station_name(m.box_station)
		row.effect = ("解锁%s后开放" if row.status.code == CommandResult.STATION_REQUIRED else "解锁后%s才有原料") % row.box_station
		if row.status.code == CommandResult.STATION_REQUIRED: row.state = "box_closed"
		return row
	if rules.level(st.id) < m.track.requires_level:
		row.state = "closed"
		row.effect = "%s Lv%d 开放" % [st.display_name, m.track.requires_level]
		return row
	var dish := shop.dish(m.item)
	var preview := price_preview(key)
	if not preview.is_empty():
		row.effect = ("部分价格加成 · " if preview.partial else "") + preview.sample + " " + quote_change(preview.quote_now, preview.quote_next, row.cost >= 0)
	elif dish != null:
		row.effect = quote_text(rules.dish_quote(dish.id))
		if row.cost >= 0:
			row.effect += " → " + quote_text(rules.preview(key, func(query: RefCounted) -> Dictionary: return query.dish_quote(dish.id)))
	return row


func seats() -> Dictionary:
	var g := rules.buy_group()
	var dine := g.purpose == "dine"
	var total: int = int(rules.seats.get(g.id, 0))
	var full := g.start + (ShopRules._sum(g.steps) if not g.steps.is_empty() else g.step * g.costs.size())
	var used := SceneFrame.seats_used(_runtime,g) if _runtime!=null else rules.seats_used()
	var next := rules._seat_step(g) if rules.seat_cost() >= 0 else 0
	var status := rules.command_status("buy_seat", {})
	return {"total": total, "max": full, "cap": rules.seat_cap(g), "used": used, "step": next, "purpose": g.purpose,
		"title": text("seats_title_" + g.purpose, {}, "堂食座位" if dine else "等位坐垫"),
		"cost": rules.seat_cost(), "status": status, "error": command_message(status)}


func flyer() -> Dictionary:
	var single := shop.fulfillment.handoff == "single"
	var wait := maxf(0.0, rules.flyer_ready_at - rules.clock) if single else rules.flyer_wait
	var pending := rules.flyer_left if single else rules.flyer_pending
	var wave := rules.flyer_wave
	if _runtime!=null and _runtime.service.flyers!=null:
		var state: Dictionary = _runtime.service.flyers.snapshot()
		wait = state.cooldown; pending = state.pending; wave = state.wave_left
	var cost := rules.upgrade_cost("flyer")
	var next_customers := rules.flyer_customers()
	var next_cooldown := rules.flyer_cooldown()
	if cost >= 0:
		next_customers = rules.preview("flyer", func(query: RefCounted) -> int: return query.flyer_customers())
		next_cooldown = rules.preview("flyer", func(query: RefCounted) -> float: return query.flyer_cooldown())
	var status := rules.command_status("send_flyers")
	var upgrade_status := rules.command_status("upgrade", {"key": "flyer"})
	return {"level": rules.level("flyer"), "customers": rules.flyer_customers(), "cooldown": rules.flyer_cooldown(),
		"seconds": shop.flyer.wave_seconds, "wait": wait, "wave": wave, "pending": pending,
		"status": status, "error": command_message(status), "queue_full": rules.queue_size() >= rules.queue_capacity(),
		"upgradable": shop.flyer.track != null and not shop.flyer.track.levels.is_empty(), "gap": shop.flyer.gap,
		"upgrade_cost": cost, "upgrade_status": upgrade_status, "upgrade_error": command_message(upgrade_status), "next_customers": next_customers, "next_cooldown": next_cooldown}


## 现在能在这台机器的面板里花钱（红 ↑）
func can_buy(id: String) -> bool:
	if not rules.station_unlocked(id): return false
	if rules.track_of(id) != null and CommandResult.is_ok(rules.command_status("upgrade", {"key": id})): return true
	if id == rules.counter_id:
		if rules.buy_group() != null and CommandResult.is_ok(rules.command_status("buy_seat", {})): return true
		if shop.flyer != null and CommandResult.is_ok(rules.command_status("upgrade", {"key": "flyer"})): return true
		# 传单只在队伍还有空的时候提示
		if shop.flyer != null and CommandResult.is_ok(rules.command_status("send_flyers", {})) and rules.queue_size() * 2 < rules.queue_capacity(): return true
	var st := shop.station(id)
	for m in st.materials:
		if CommandResult.is_ok(rules.command_status("upgrade", {"key": id + "/" + m.id})): return true
	if not shop.recipe_stages(id).is_empty() and CommandResult.is_ok(rules.command_status("unlock", {"id": id})): return true
	return false


## 机器此刻在干什么：{working, progress, need（待取 n / 待操作）, input, processing, output}
func machine_status(id: String) -> Dictionary:
	if _runtime!=null:
		var current: Dictionary = _runtime.runner.machines.status(id)
		if current.is_empty(): return {}
		if not current.need.is_empty(): current.need = text("need_operate",{},"待操作")
		elif not current.working and current.output>0: current.need = "待取 %d"%current.output
		return current
	var s: Dictionary = rules.stations.get(id, {})
	if s.is_empty(): return {}
	var total := func(d: Dictionary) -> int:
		var n := 0
		for v in d.values(): n += int(v)
		return n
	var output: int = total.call(s.output)
	var working: bool = s.phase in ["heating", "mixing", "working", "sealing", "cook"]
	var progress := float(s.progress)
	# 一人跟单的店的锅只记剩几秒
	var duration := float(s.get("duration", 0.0))
	if duration <= 0.0 and s.phase == "cook": duration = rules.pot_seconds(id)
	if s.phase == "cook" and duration > 0.0: progress = clampf(1.0 - float(s.remaining) / duration, 0.0, 1.0)
	var need := ""
	if not working:
		if s.phase in ["awaiting_take", "done"]: need = text("need_take", {}, "待取")
		elif s.phase == "stir": need = text("need_operate", {}, "待操作")
		elif output > 0: need = "待取 %d" % output
		elif total.call(s.input) > 0 and shop.station(id).block in ["batch_pot", "topping"]: need = text("need_operate", {}, "待操作")
	return {"working": working, "progress": progress, "need": need, "input": total.call(s.input),
		"processing": int(s.get("processing", 0)), "output": output}


# ---------- 员工（§3.5） ----------

func hire() -> Dictionary:
	var kind := rules.next_hire_kind()
	var k := rules._kind(kind)
	var status := rules.command_status("hire", {})
	return {"cost": rules.hire_cost(), "status": status, "error": command_message(status), "kind": kind, "name": k.display_name,
		"room": rules.workers.size() < rules.staff_slots()}


## 前台 / 后厨升级：{side, title, bought, total, rows, cost, error, name}
func staff_track(side: String) -> Dictionary:
	var key := "staff/" + side
	var t := rules.track_of(key)
	if t == null: return {}
	var bought := int(rules.levels[key])
	var rows: Array = []
	for index in t.levels.size():
		rows.append({"name": effect_name(t.levels[index].effects), "cost": t.levels[index].cost, "bought": index < bought})
	var cost := rules.upgrade_cost(key)
	var status := rules.command_status("upgrade", {"key": key})
	return {"side": side, "title": t.display_name, "bought": bought, "total": t.levels.size(), "rows": rows, "cost": cost,
		"status": status, "error": command_message(status) if cost >= 0 else "已全部升级", "name": rows[bought].name if bought < rows.size() else ""}


## 一级效果的一句话（员工升级列表用）
func effect_name(effects: Array) -> String:
	var parts: Array = []
	for e in effects:
		match e.kind:
			"walk": parts.append("走路快 +%d%%" % roundi((e.value - 1.0) * 100))
			"work": parts.append("手脚快 +%d%%" % roundi((e.value - 1.0) * 100))
			"carry": parts.append("一次多搬 %d %s" % [int(e.value), text("unit", {}, "份")])
			"staff_slot": parts.append("多一个%s位" % ("前台" if e.target == "front" else "后厨"))
			"luck": parts.append("运气 +%s" % price_text(e.value))
			_: parts.append(e.kind)
	return "、".join(parts)


func slots() -> Dictionary:
	if shop.staff.zones.is_empty(): return {"all": rules.staff_slots(), "used": rules.workers.size()}
	return {"front": rules.front_slots(), "kitchen": rules.kitchen_slots(), "front_used": rules.workers.size() - rules.kitchen_staff(),
		"kitchen_used": rules.kitchen_staff(), "all": rules.staff_slots(), "used": rules.workers.size()}


## 员工头顶的字：texts["task_<动作>@<机器>"] → texts["task_<动作>"] → 原样（单人模式的规则层直接给中文）
func task_text(worker: Dictionary) -> String:
	if worker.get("presentation_version")==1:
		var action := String(worker.get("display_task","idle"))
		return text("task_"+action,{}, {"operate":"加工","transfer":"搬运","bundle":"搬运","interact":"接单","idle":"空闲"}.get(action,action))
	var label: String = worker.get("task_label", "")
	if label.is_empty(): label = "idle"
	var job: Dictionary = worker.get("job", {})
	var at: String = job.get("dst", "")
	var values := {"to": station_name(at), "item": item_name(String(job.get("item", "")))}
	var specific := text("task_%s@%s" % [label, at], values)
	if not specific.is_empty(): return specific
	return text("task_" + label, values, label)


## 员工卡片：cultivation 为所属区域培养进度，stats 为当前有效属性。
func worker_card(worker: Dictionary) -> Dictionary:
	var kind := rules._kind(String(worker.kind))
	var track := staff_track(rules.side_of(worker))
	var cultivation := "培养 %d/%d" % [track.bought, track.total] if not track.is_empty() else "店内培养"
	return {"id": worker.id, "kind": worker.kind, "name": kind.display_name, "role": kind.role, "description": kind.description,
		"cultivation": cultivation, "cultivation_scope": track.get("title", "店内"), "stats": rules.effective_worker_stats(worker), "stat_limits": rules.worker_stat_limits(worker), "deployed": worker.deployed, "post": worker.post,
		"task": task_text(worker)}


## 员工手上这步活的进度（0–1）；没在干活、或者活在机器上（机器自己有进度条）返回 -1
func work_progress(worker: Dictionary) -> float:
	if worker.get("presentation_version")==1: return float(worker.display_progress)
	if worker.get("phase", "") != "work": return -1.0
	var duration: float = float(worker.get("duration", 0.0))
	if duration <= 0.0 or not worker.get("job", {}).is_empty(): return -1.0
	return clampf(1.0 - float(worker.get("timer", 0.0)) / duration, 0.0, 1.0)


const ItemArt := preload("res://game/rules/shop_item_art.gd")

## Explicit scene artwork and UI icons share the same shop item data.
func item_art(id: String) -> Dictionary:
	return ItemArt.appearance(shop, id)


func item_icon(id: String) -> Texture2D:
	return ItemArt.icon(shop, id)


## 在这台机器前干活朝哪个方向（8 方向；-1 = 不转）
## 机器或原料的图标：店铺数据里写了就用（图标名或 res:// 图），没写就用 id
func icon_of(id: String) -> String:
	var st := shop.station(id)
	if st != null: return st.icon if not st.icon.is_empty() else id
	for s in shop.stations:
		var m := s.material(id)
		if m != null and not m.icon.is_empty(): return m.icon
	if ItemArt.find_item(shop, id) != null: return item_icon(id).resource_path
	return id


func work_direction(station_id: String) -> int:
	var st := shop.station(station_id)
	return int(st.params.get("facing", -1)) if st != null else -1


## 正从展示柜接现成饮品的员工：返回那台机器（动画按“干活”放）
func pouring_station(worker: Dictionary) -> String:
	if worker.get("presentation_version")==1: return String(worker.get("work_station","")) if worker.get("phase")=="pickup" else ""
	if worker.get("phase", "") != "pickup": return ""
	var job: Dictionary = worker.get("job", {})
	for d in shop.dishes:
		if d.front and d.id == String(job.get("item", "")):
			for step in d.steps:
				var st := shop.station(step.station)
				if st != null and st.block == "dispenser": return st.id
	return ""


# ---------- 瓶颈提示（§3.10） ----------

const HINT_AFTER := 20.0

## 队伍满了一阵子：哪道菜排长队、卡在哪、去哪修（target = 机器 id，或 staff_front / staff_kitchen / staff）。
func bottleneck() -> Dictionary:
	if rules.full_seconds < HINT_AFTER: return {}
	var waiting := {}
	var source: Array = rules.orders if shop.fulfillment.handoff != "single" else rules.customers
	for order in source:
		if order.get("reserved", false) or order.get("claimed", false): continue
		var dish: String = order.get("dish", order.get("kind", ""))
		waiting[dish] = int(waiting.get(dish, 0)) + 1
	var top := ""
	for dish in waiting:
		if top.is_empty() or waiting[dish] > waiting[top]: top = dish
	if top.is_empty(): return {}
	var drink := dish_name(top)
	var zoned := not shop.staff.zones.is_empty()
	var hint := {}
	var chain: Array = rules.chains.get(top, [])
	var pot := ""
	for id in chain:
		if id in rules.pots and pot.is_empty(): pot = id
	if zoned and shop.dish(top).front:
		hint = {"key": "hint_front", "target": "staff_front"}
	elif zoned and rules.kitchen_staff() <= 0:
		hint = {"key": "hint_no_kitchen", "target": "staff_kitchen"}
	elif not pot.is_empty() and float(rules.pot_busy.get(pot, 0.0)) > 0.85:
		hint = {"key": "hint_pot", "target": pot}
	elif float(rules.side_idle.get("kitchen" if zoned else "", 1.0)) < 0.15:
		hint = {"key": "hint_staff", "target": "staff_kitchen" if zoned else "staff"}
	elif not pot.is_empty():
		hint = {"key": "hint_machine", "target": pot}
	else:
		hint = {"key": "hint_staff", "target": "staff_kitchen" if zoned else "staff"}
	var values := {"drink": drink, "name": station_name(hint.target) if shop.station(hint.target) != null else ""}
	hint.drink = drink
	hint.text = text(hint.key, values, drink + "排长队")
	hint.fix = text(hint.key + "_fix", values, "")
	hint.short = "%s排长队 · %s" % [drink, hint.fix] if not hint.fix.is_empty() else hint.text
	return hint


# ---------- 进行中加成（§6.2.1） ----------

## 加成栈里带到期时间的加成：顶栏小图标。{source, id, kind, value, left, total}
func buffs() -> Array:
	return rules.mods.timed().map(func(e: Dictionary) -> Dictionary:
		return {"source": e.source, "id": e.source_id, "kind": e.kind, "value": e.value, "left": e.left, "total": e.total})


## 加成图标：来自哪个奇遇就用它的图标，否则按种类 texts["buff_icon_<种类>"]，再没有就用“目标”
func buff_icon(buff: Dictionary) -> String:
	var ev := _event_def(String(buff.get("id", "")))
	if ev != null and not ev.icon.is_empty(): return ev.icon
	return text("buff_icon_" + String(buff.get("kind", "")), {}, "goals")


func buff_name(buff: Dictionary) -> String:
	var ev := _event_def(String(buff.get("id", "")))
	return ev.display_name if ev != null else String(buff.get("kind", ""))


## 等玩家选的奇遇卡：{id, title, text, icon, speaker, choices: [label…]}
func event_card() -> Dictionary:
	if rules.pending_events.is_empty(): return {}
	var ev: SpecEvent = rules.pending_events[0]
	return {"id": ev.id, "title": ev.display_name, "text": ev.card_text, "icon": ev.icon, "speaker": ev.speaker,
		"choices": ev.choices.map(func(c: Dictionary) -> String: return String(c.get("label", "")))}


func _event_def(id: String) -> SpecEvent:
	for ev in rules.event_defs:
		if ev.id == id: return ev
	return null
