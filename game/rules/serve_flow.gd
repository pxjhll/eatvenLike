extends RefCounted
## 交接方式 serve（规格 §10，v1.1 草案）：顾客排队 → 前厅接单并分配座位 → 后厨按配方依赖做（多路半成品在组合台等齐才合）
## → 放出餐口 → 前厅送到座位 → 已就座且整单送齐才开吃 → 吃完离座。
##
## 规则层只认积木类型和配方数据，不认任何店、机器、菜的名字。全部运行状态在 rules.serve 里（跟存档走）：
##   guests  顾客：排队 / 去座位 / 坐着等 / 吃 —— 顾客、订单、座位是三样东西，用 id 互相引用
##   orders  订单：餐品明细 lines[{dish, qty, delivered}]、付没付
##   units   每份要做的餐（订单明细的一份）：做完了哪几步
##   goods   每一件实物：在哪（机器 id / hand:员工 / seat:座位号）、归谁（某份餐，或 -1 = 共享库存）、被谁预留
##   jobs    员工手上的活，按员工 id 存
## 物品守恒：实物只在“从原料箱拿起 / 批量锅出锅”时出生，只在“配方工序消耗 / 客人吃完”时消失；取消只放回、不凭空增减。

const WorkerState := preload("res://game/rules/worker_state.gd")
const SHARED := -1
const SOURCE_BLOCKS := ["supply", "batch_pot"]
const WORK_BLOCKS := ["hand", "combine"]
const HAND := "hand:"
const SEAT := "seat:"


static func empty_state() -> Dictionary:
	return {"guests": [], "orders": [], "units": [], "goods": [], "jobs": {}, "next_id": 1,
		"served": 0, "orders_done": 0, "items_sold": 0}


# =====================================================================
# 配方（只读店铺数据）
# =====================================================================

static func work_steps(shop: SpecShop, dish_id: String) -> Array[int]:
	var out: Array[int] = []
	var dish := shop.dish(dish_id)
	for i in dish.steps.size():
		var st := shop.station(dish.steps[i].station)
		if st != null and st.block in WORK_BLOCKS: out.append(i)
	return out


## 这道菜里谁做出 item（同一道菜里只认第一步）
static func producer(shop: SpecShop, dish_id: String, item: String) -> int:
	var dish := shop.dish(dish_id)
	for i in dish.steps.size():
		if dish.steps[i].produces.has(item): return i
	return -1


static func pickup_of(shop: SpecShop) -> String:
	for st in shop.stations:
		if st.block == "pickup": return st.id
	return ""


static func seat_point(shop: SpecShop, seat: int) -> String:
	for g in shop.seat_groups:
		if g.purpose == "dine": return "%s/%d" % [g.id, seat]
	return ""


static func pot_item(shop: SpecShop, id: String) -> String:
	var st := shop.station(id)
	if not st.stock.is_empty(): return st.stock[0].item
	for dish in shop.dishes:
		for s in dish.steps:
			if s.station == id and not s.produces.is_empty(): return s.produces.keys()[0]
	return ""


static func pot_cap(shop: SpecShop, id: String) -> int:
	var st := shop.station(id)
	if not st.stock.is_empty() and st.stock[0].cap > 0: return st.stock[0].cap
	return int(st.params.get("capacity", 6))


# =====================================================================
# 查询
# =====================================================================

static func _find(rows: Array, id: int) -> Dictionary:
	for row in rows:
		if int(row.id) == id: return row
	return {}


static func guest(rules: ShopRules, id: int) -> Dictionary:
	return _find(rules.serve.guests, id)


static func order(rules: ShopRules, id: int) -> Dictionary:
	return _find(rules.serve.orders, id)


static func unit(rules: ShopRules, id: int) -> Dictionary:
	return _find(rules.serve.units, id)


static func job_of(rules: ShopRules, worker: Dictionary) -> Dictionary:
	return rules.serve.jobs.get(str(worker.id), {})


static func goods_at(rules: ShopRules, at: String, item := "", owner := SHARED, free_only := false) -> Array:
	var out: Array = []
	for g in rules.serve.goods:
		if g.at != at or (not item.is_empty() and g.item != item) or int(g.owner) != owner: continue
		if free_only and int(g.res) != -1: continue
		out.append(g)
	return out


## 共享库存（§10.3）：可用 / 已预留 / 在制
static func stock(rules: ShopRules, station_id: String) -> Dictionary:
	var available := 0
	var reserved := 0
	for g in rules.serve.goods:
		if g.at != station_id or int(g.owner) != SHARED: continue
		if int(g.res) == -1: available += 1
		else: reserved += 1
	var pot: Dictionary = rules.stations.get(station_id, {})
	return {"available": available, "reserved": reserved, "cooking": int(pot.get("processing", 0))}


static func seats_taken(rules: ShopRules) -> Array[int]:
	var taken: Array[int] = []
	for g in rules.serve.guests:
		if int(g.seat) >= 0: taken.append(int(g.seat))
	return taken


static func free_seat(rules: ShopRules) -> int:
	var taken := seats_taken(rules)
	for seat in rules.seat_total():
		if not seat in taken: return seat
	return -1


static func queue_size(rules: ShopRules) -> int:
	var n := 0
	for g in rules.serve.guests:
		if g.state == "queue": n += 1
	return n


static func order_complete(o: Dictionary) -> bool:
	for line in o.lines:
		if int(line.delivered) < int(line.qty): return false
	return true


static func role(rules: ShopRules, worker: Dictionary) -> String:
	if rules.shop.staff.zones.is_empty(): return "any" if String(worker.post).is_empty() else "seated"
	if worker.post == rules.counter_id: return "front"
	return "kitchen" if String(worker.post).is_empty() else "seated"


# =====================================================================
# 时间推进
# =====================================================================

static func tick(rules: ShopRules, dt: float) -> void:
	if rules.is_open(): _arrivals(rules, dt)
	_pots(rules, dt)
	_guests(rules, dt)
	for worker in rules.workers: _work(rules, worker, dt)
	_allocate(rules)


static func _arrivals(rules: ShopRules, dt: float) -> void:
	rules._next_customer -= dt
	if rules.flyer_left > 0:
		rules.flyer_timer -= dt
		if rules.flyer_timer <= 0.0:
			rules.flyer_left -= 1
			rules.flyer_timer = rules.shop.flyer.gap
			_spawn(rules)
	if rules._next_customer <= 0.0:
		var interval := rules.customer_interval()
		rules._next_customer = interval if rules.shop.fulfillment.arrival == "fixed" else -log(1.0 - rules.rng.randf() * 0.999) * interval
		_spawn(rules)


static func _spawn(rules: ShopRules) -> void:
	if queue_size(rules) >= rules.queue_capacity():
		rules.lost += 1
		rules.events.emit("lost", {})
		return
	var s: Dictionary = rules.serve
	s.guests.append({"id": _next(rules), "state": "queue", "wait": 0.0, "seat": -1, "order": -1, "claimed": -1,
		"walk_left": 0.0, "walk_total": 0.0, "eat_left": 0.0})
	rules._next_customer_id += 1
	rules.events.emit("arrived", {})


static func _next(rules: ShopRules) -> int:
	var id := int(rules.serve.next_id)
	rules.serve.next_id = id + 1
	return id


## 自动批量锅（电饭柜）：库存放得下一整锅就自己开一锅；出锅的东西进共享库存，谁用谁来拿（自动加工 ≠ 自动搬运）
static func _pots(rules: ShopRules, dt: float) -> void:
	for st in rules.shop.stations:
		if st.block != "batch_pot" or not rules.station_unlocked(st.id): continue
		var pot: Dictionary = rules.stations[st.id]
		var item := pot_item(rules.shop, st.id)
		if pot.phase == "cook":
			pot.remaining = maxf(0.0, float(pot.remaining) - dt)
			pot.progress = clampf(1.0 - float(pot.remaining) / maxf(0.001, float(pot.duration)), 0.0, 1.0)
			if pot.remaining <= 0.000001:
				for unused in int(pot.processing): _birth(rules, item, st.id, SHARED)
				pot.processing = 0
				pot.phase = "idle"
				pot.progress = 0.0
				rules.events.emit("pot_done", {"station": st.id})
		if pot.phase == "idle":
			var batch := rules.pot_batch(st.id)
			# 放得下一整锅才开；饭盆空了总能开（升级后每锅份数可能超过库存上限，不能因此停产）
			var have := goods_at(rules, st.id, item).size()
			if have == 0 or have + batch <= pot_cap(rules.shop, st.id):
				pot.phase = "cook"
				pot.processing = batch
				pot.processing_item = item
				pot.duration = rules.pot_seconds(st.id)
				pot.remaining = pot.duration
				pot.progress = 0.0
		pot.stock = goods_at(rules, st.id, item, SHARED, true).size()


static func _birth(rules: ShopRules, item: String, at: String, owner: int) -> Dictionary:
	var good := {"id": _next(rules), "item": item, "at": at, "owner": owner, "res": -1}
	rules.serve.goods.append(good)
	return good


static func seed_stock(rules: ShopRules, station_id: String) -> void:
	var st := rules.shop.station(station_id)
	if st == null or st.block != "batch_pot" or st.stock.is_empty(): return
	var item := pot_item(rules.shop, station_id)
	for unused in maxi(0, st.stock[0].start - goods_at(rules, station_id, item).size()): _birth(rules, item, station_id, SHARED)
	rules.stations[station_id].stock = goods_at(rules, station_id, item, SHARED, true).size()


static func _guests(rules: ShopRules, dt: float) -> void:
	var f := rules.shop.fulfillment
	var patience := f.leave_after * rules.mods.value("patience", 1.0)
	for g in rules.serve.guests.duplicate():
		match String(g.state):
			"queue":
				g.wait += dt
				if f.leave_who == "queued_unclaimed" and f.leave_after > 0.0 and int(g.claimed) == -1 and g.wait >= patience:
					rules.serve.guests.erase(g)
					rules.lost += 1
					rules.events.emit("lost", {})
			"to_seat":
				g.wait += dt
				g.walk_left = maxf(0.0, float(g.walk_left) - dt)
				if g.walk_left <= 0.000001:
					g.state = "seated"
					rules.events.emit("seated", {"guest": g.id, "seat": g.seat})
					_maybe_eat(rules, g)
			"seated":
				g.wait += dt
			"eating":
				g.eat_left = maxf(0.0, float(g.eat_left) - dt)
				if g.eat_left <= 0.000001: _leave(rules, g)


## 用餐开始条件（§10.4，本模式固定）：已就座 + 订单全部明细送达
static func _maybe_eat(rules: ShopRules, g: Dictionary) -> void:
	if g.state != "seated": return
	var o := order(rules, int(g.order))
	if o.is_empty() or not order_complete(o): return
	g.state = "eating"
	g.eat_left = rules.seat_seconds()
	rules.events.emit("eat_start", {"guest": g.id, "seat": g.seat})


static func _leave(rules: ShopRules, g: Dictionary) -> void:
	var s: Dictionary = rules.serve
	var o := order(rules, int(g.order))
	var owned := {}
	for u in s.units.duplicate():
		if int(u.order) == int(g.order):
			owned[int(u.id)] = true
			s.units.erase(u)
	for good in s.goods.duplicate():
		if owned.has(int(good.owner)) and good.at == SEAT + str(g.seat): s.goods.erase(good)
	if not o.is_empty(): s.orders.erase(o)
	s.guests.erase(g)
	rules.events.emit("left", {"guest": g.id, "seat": g.seat})


# =====================================================================
# 员工：每个员工手上一件活，一步步走完
# =====================================================================

static func _point(rules: ShopRules, at: String) -> Vector2:
	if at.begins_with(SEAT): return rules.nav.point(seat_point(rules.shop, int(at.substr(SEAT.length()))))
	return rules.nav.point(at)


static func _go(rules: ShopRules, worker: Dictionary, at: String, stage: String) -> void:
	var job := job_of(rules, worker)
	job.stage = stage
	worker.target = "" if at.begins_with(SEAT) else at
	var goal := _point(rules, at)
	if worker.pos.distance_to(goal) < 1.0:
		worker.walking = false
		worker.pos = goal
		_arrived(rules, worker)
	else:
		WorkerState.begin_walk(worker, rules.nav.path(worker.pos, goal), "walk")


static func _act(worker: Dictionary, job: Dictionary, stage: String, seconds: float, label: String) -> void:
	job.stage = stage
	worker.walking = false
	worker.phase = "work"
	worker.action_left = maxf(0.0, seconds)
	worker.task_label = label


static func _work(rules: ShopRules, worker: Dictionary, dt: float) -> void:
	var job := job_of(rules, worker)
	if job.is_empty():
		worker.phase = "idle"
		return
	if worker.walking:
		if WorkerState.advance_walk(worker, rules.walk_speed(worker) * dt): _arrived(rules, worker)
		return
	if worker.phase != "work": return
	worker.action_left = maxf(0.0, float(worker.action_left) - dt)
	if worker.action_left > 0.000001: return
	match String(job.stage):
		"pick": _picked(rules, worker, job)
		"drop": _dropped(rules, worker, job)
		"work": _worked(rules, worker, job)


static func _arrived(rules: ShopRules, worker: Dictionary) -> void:
	var job := job_of(rules, worker)
	var shop := rules.shop
	match String(job.stage):
		"go_from":
			if job.kind == "take":
				_act(worker, job, "work", float(shop.station(rules.counter_id).params.get("take_seconds", 0.0)) / rules.skill(worker), "接单")
			elif job.kind == "work":
				var s: SpecStep = shop.dish(String(unit(rules, int(job.unit)).dish)).steps[int(job.step)]
				_act(worker, job, "work", rules.manual_operation_seconds(s.station, s.seconds * s.repeat, worker, s.fixed), s.label)
			else:
				_act(worker, job, "pick", _pick_seconds(rules, worker, job), _pick_label(rules, job))
		"go_to":
			var seconds := float(shop.station(rules.counter_id).params.get("hand_seconds", 0.0)) if job.kind == "serve" else shop.dispatch.hop_seconds
			_act(worker, job, "drop", seconds / rules.skill(worker), "上菜" if job.kind == "serve" else "放下")
		"home":
			_end(rules, worker)


static func _pick_seconds(rules: ShopRules, worker: Dictionary, job: Dictionary) -> float:
	var st := rules.shop.station(String(job.from))
	if st != null and st.block in SOURCE_BLOCKS:
		var u := unit(rules, int(job.unit))
		var p := producer(rules.shop, String(u.dish), String(job.item))
		if p >= 0:
			var s: SpecStep = rules.shop.dish(String(u.dish)).steps[p]
			return rules.manual_operation_seconds(s.station, s.seconds * s.repeat, worker, s.fixed)
	return rules.shop.dispatch.hop_seconds / rules.skill(worker)


static func _pick_label(rules: ShopRules, job: Dictionary) -> String:
	var u := unit(rules, int(job.unit))
	var p := producer(rules.shop, String(u.dish), String(job.item)) if not u.is_empty() else -1
	var st := rules.shop.station(String(job.from))
	if p >= 0 and st != null and st.block in SOURCE_BLOCKS: return rules.shop.dish(String(u.dish)).steps[p].label
	return "端起" if job.kind == "serve" else "拿起"


static func _picked(rules: ShopRules, worker: Dictionary, job: Dictionary) -> void:
	var good: Dictionary
	if int(job.good) == -1:
		good = _birth(rules, String(job.item), HAND + str(worker.id), int(job.unit))
		job.good = good.id
	else:
		good = _good(rules, int(job.good))
		good.at = HAND + str(worker.id)
		# 共享库存一拿起来就归这份餐（预留 → 领用）
		good.owner = int(job.unit)
	good.res = worker.id
	worker.carry_item = String(job.item)
	worker.carry_count = 1
	worker.task_label = "送餐" if job.kind == "serve" else ("出餐" if job.kind == "pass" else "搬")
	_go(rules, worker, String(job.to), "go_to")


static func _dropped(rules: ShopRules, worker: Dictionary, job: Dictionary) -> void:
	var good := _good(rules, int(job.good))
	good.at = String(job.to)
	good.res = -1
	worker.carry_item = ""
	worker.carry_count = 0
	if job.kind == "serve": _delivered(rules, int(job.unit))
	_end(rules, worker)


static func _worked(rules: ShopRules, worker: Dictionary, job: Dictionary) -> void:
	var s := rules.serve
	if job.kind == "take":
		_taken(rules, worker, job)
		_end(rules, worker)
		return
	var u := unit(rules, int(job.unit))
	var step: SpecStep = rules.shop.dish(String(u.dish)).steps[int(job.step)]
	for item in step.consumes:
		var need: int = step.consumes[item]
		for good in goods_at(rules, step.station, item, int(u.id)):
			if need <= 0: break
			s.goods.erase(good)
			need -= 1
	for item in step.produces:
		for unused in int(step.produces[item]): _birth(rules, item, step.station, int(u.id))
	u.done.append(int(job.step))
	rules.stations[step.station].user = -1
	rules.events.emit("made", {"station": step.station, "dish": u.dish, "unit": u.id})
	_end(rules, worker)


## 接单（§10.1）：顾客 → 订单（明细列表）→ 每份餐一个 unit；顾客拿着座位号走过去
static func _taken(rules: ShopRules, worker: Dictionary, job: Dictionary) -> void:
	var s := rules.serve
	var g := guest(rules, int(job.guest))
	var lines: Array = [{"dish": rules._pick_dish(rules.order_weights()), "qty": 1, "delivered": 0}]
	var f := rules.shop.fulfillment
	if not f.addon_dish.is_empty() and lines[0].dish != f.addon_dish and rules.dish_open(f.addon_dish, false) and rules.rng.randf() < f.addon_chance:
		lines.append({"dish": f.addon_dish, "qty": 1, "delivered": 0})
	var o := {"id": _next(rules), "guest": g.id, "seat": g.seat, "lines": lines, "paid": false}
	s.orders.append(o)
	for i in lines.size():
		for unused in int(lines[i].qty):
			s.units.append({"id": _next(rules), "order": o.id, "line": i, "dish": lines[i].dish, "done": [], "wait": 0.0})
	g.order = o.id
	g.claimed = -1
	g.state = "to_seat"
	var speed := maxf(1.0, f.customer_walk)
	g.walk_total = RuleNav.length(rules.nav.path(rules.nav.point(rules.counter_id), _point(rules, SEAT + str(g.seat)))) / speed
	g.walk_left = g.walk_total
	rules.events.emit("order_taken", {"guest": g.id, "order": o.id, "seat": g.seat})


## 一份餐送到座位：只更新它那条明细；整单齐了才结一次账（§10.4）
static func _delivered(rules: ShopRules, unit_id: int) -> void:
	var s := rules.serve
	var u := unit(rules, unit_id)
	var o := order(rules, int(u.order))
	var line: Dictionary = o.lines[int(u.line)]
	line.delivered = int(line.delivered) + 1
	rules._sales.count_handoff(String(u.dish), 1)
	s.items_sold = int(s.items_sold) + 1
	rules.events.emit("delivered", {"dish": u.dish, "order": o.id})
	if bool(o.paid) or not order_complete(o): return
	o.paid = true
	var total := 0.0
	var count := 0
	for l in o.lines:
		total += rules.dish_price(String(l.dish)) * int(l.qty)
		count += int(l.qty)
	var sale: Dictionary = rules._sales.credit_order(total)
	s.served = int(s.served) + 1
	s.orders_done = int(s.orders_done) + 1
	rules.events.emit("sale", {"dish": o.lines[0].dish, "count": count, "income": sale.income})
	_maybe_eat(rules, guest(rules, int(o.guest)))


static func _end(rules: ShopRules, worker: Dictionary) -> void:
	rules.serve.jobs.erase(str(worker.id))
	worker.phase = "idle"
	worker.task_label = "idle"
	worker.walking = false
	worker.action_left = 0.0
	worker.completed += 1


static func _good(rules: ShopRules, id: int) -> Dictionary:
	return _find(rules.serve.goods, id)


## 放下手上的活（调岗、收回名册）：预留全部释放；手上的东西放回拿的地方，仍归原来那份餐（§10.3 取消释放）
static func cancel(rules: ShopRules, worker: Dictionary) -> void:
	var job := job_of(rules, worker)
	if job.is_empty(): return
	if int(job.good) != -1:
		var good := _good(rules, int(job.good))
		if not good.is_empty():
			if String(good.at).begins_with(HAND): good.at = String(job.from)
			good.res = -1
	if job.kind == "take":
		var g := guest(rules, int(job.guest))
		if not g.is_empty() and g.state == "queue":
			g.claimed = -1
			g.seat = -1
	if job.kind == "work":
		var u := unit(rules, int(job.unit))
		if not u.is_empty():
			var st: String = rules.shop.dish(String(u.dish)).steps[int(job.step)].station
			if int(rules.stations[st].user) == int(worker.id): rules.stations[st].user = -1
	rules.serve.jobs.erase(str(worker.id))
	worker.carry_item = ""
	worker.carry_count = 0
	worker.walking = false
	worker.phase = "idle"
	worker.task_label = "idle"
	worker.action_left = 0.0


# =====================================================================
# 派活：空闲员工从候选表里挑分最高的（§3.6 打分，分区和坐班决定能接哪些）
# =====================================================================

static func _allocate(rules: ShopRules) -> void:
	for u in rules.serve.units: u.wait = float(u.wait) + ShopRules.STEP
	for worker in rules.workers:
		if not job_of(rules, worker).is_empty(): continue
		var best := {}
		for c in candidates(rules, worker):
			if best.is_empty() or float(c.score) > float(best.score): best = c
		if best.is_empty():
			_idle(rules, worker)
			continue
		_claim(rules, worker, best)


static func _idle(rules: ShopRules, worker: Dictionary) -> void:
	worker.phase = "idle"
	if String(worker.post).is_empty(): return
	var home := rules.nav.post(worker.post)
	if worker.pos.distance_to(home) < 1.0: return
	rules.serve.jobs[str(worker.id)] = _job("home", -1, -1, "", -1, "", worker.post)
	worker.task_label = "回岗"
	WorkerState.begin_walk(worker, rules.nav.path(worker.pos, home), "walk")
	job_of(rules, worker).stage = "home"


static func _job(kind: String, unit_id: int, step: int, item: String, good: int, from: String, to: String, guest_id := -1) -> Dictionary:
	return {"kind": kind, "unit": unit_id, "step": step, "item": item, "good": good, "from": from, "to": to,
		"guest": guest_id, "stage": "", "score": 0.0}


static func _claim(rules: ShopRules, worker: Dictionary, c: Dictionary) -> void:
	var job := c.duplicate()
	rules.serve.jobs[str(worker.id)] = job
	if int(job.good) != -1: _good(rules, int(job.good)).res = worker.id
	if job.kind == "take":
		var g := guest(rules, int(job.guest))
		g.claimed = worker.id
		g.seat = free_seat(rules)
	if job.kind == "work":
		var u := unit(rules, int(job.unit))
		rules.stations[rules.shop.dish(String(u.dish)).steps[int(job.step)].station].user = worker.id
	worker.task_label = String(c.get("label", ""))
	_go(rules, worker, String(job.from), "go_from")


## 这个员工现在能接的所有活（只读）
static func candidates(rules: ShopRules, worker: Dictionary) -> Array:
	var out: Array = []
	var r := role(rules, worker)
	var shop := rules.shop
	var d := shop.dispatch
	if r in ["front", "any"]:
		for g in rules.serve.guests:
			if g.state != "queue" or int(g.claimed) != -1: continue
			if free_seat(rules) < 0: break
			out.append(_scored(rules, worker, _job("take", -1, -1, "", -1, rules.counter_id, rules.counter_id, int(g.id)), "take", float(g.wait), "接单"))
			break
		var pickup := pickup_of(shop)
		for good in rules.serve.goods:
			if good.at != pickup or int(good.res) != -1 or int(good.owner) == SHARED: continue
			var u := unit(rules, int(good.owner))
			if u.is_empty() or String(rules.shop.dish(String(u.dish)).item) != String(good.item): continue
			var o := order(rules, int(u.order))
			out.append(_scored(rules, worker, _job("serve", int(u.id), -1, String(good.item), int(good.id), pickup, SEAT + str(o.seat)), "serve", float(u.wait), "送餐"))
	if r == "front": return out
	var claimed := _claimed(rules)
	for u in rules.serve.units:
		_unit_jobs(rules, worker, r, u, claimed, out)
	return out


static func _scored(rules: ShopRules, worker: Dictionary, job: Dictionary, key: String, wait: float, label: String) -> Dictionary:
	var d := rules.shop.dispatch
	var travel: float = (worker.pos as Vector2).distance_to(_point(rules, String(job.from)))
	job.score = float(d.base_scores.get(key, 0.0)) + minf(d.wait_bonus_cap, wait * d.wait_bonus_per_second) - travel * d.travel_penalty
	job.label = label
	return job


## 已经有人在做的：{"carry|unit|item|to": 件数, "work|unit|step": true}
static func _claimed(rules: ShopRules) -> Dictionary:
	var out := {}
	for key in rules.serve.jobs:
		var job: Dictionary = rules.serve.jobs[key]
		if job.kind in ["carry", "pass"]:
			var k := "carry|%d|%s|%s" % [job.unit, job.item, job.to]
			out[k] = int(out.get(k, 0)) + 1
		elif job.kind == "work":
			out["work|%d|%d" % [job.unit, job.step]] = true
	return out


static func _unit_jobs(rules: ShopRules, worker: Dictionary, r: String, u: Dictionary, claimed: Dictionary, out: Array) -> void:
	var shop := rules.shop
	var dish := shop.dish(String(u.dish))
	var flowing := r in ["kitchen", "any"]
	var pickup := pickup_of(shop)
	var all_done := true
	for i in work_steps(shop, dish.id):
		if i in u.done: continue
		all_done = false
		var s := dish.steps[i]
		var station: Dictionary = rules.stations[s.station]
		# 前面的工序还没做完（浇头没炒好）就不往这台送别的料：按单合流，不提前囤货（§10.3）
		var blocked := false
		for item in s.consumes:
			var p := producer(shop, dish.id, item)
			if p >= 0 and p in work_steps(shop, dish.id) and not p in u.done: blocked = true
		if blocked: continue
		var ready := true
		for item in s.consumes:
			var need: int = s.consumes[item]
			var here := goods_at(rules, s.station, item, int(u.id), true).size()
			var coming := int(claimed.get("carry|%d|%s|%s" % [u.id, item, s.station], 0))
			if here < need: ready = false
			if here + coming >= need or not flowing: continue
			var c := _carry_in(rules, worker, u, item, s.station)
			if not c.is_empty(): out.append(c)
		if not ready or claimed.has("work|%d|%d" % [u.id, i]): continue
		if int(station.user) != -1 or not rules.station_unlocked(s.station): continue
		# 坐班的人只做自己这台；有人坐班的台子流动员工不碰（§3.6 坐班）
		if r == "seated" and worker.post != s.station: continue
		if flowing and rules.post_owner(s.station) != -1: continue
		out.append(_scored(rules, worker, _job("work", int(u.id), i, "", -1, s.station, s.station), "work", float(u.wait), s.label))
	if not flowing or not all_done: return
	if int(claimed.get("carry|%d|%s|%s" % [u.id, dish.item, pickup], 0)) > 0: return
	for good in rules.serve.goods:
		if int(good.owner) == int(u.id) and good.item == dish.item:
			if good.at == pickup or String(good.at).begins_with(SEAT) or int(good.res) != -1: return
			out.append(_scored(rules, worker, _job("pass", int(u.id), -1, dish.item, int(good.id), String(good.at), pickup), "pass", float(u.wait), "出餐"))
			return
	# 成品直接来自原料箱 / 批量锅（例汤）：从那儿盛了送出餐口
	var c := _carry_in(rules, worker, u, dish.item, pickup)
	if not c.is_empty():
		c.kind = "pass"
		c.score = c.score - float(shop.dispatch.base_scores.get("carry", 0.0)) + float(shop.dispatch.base_scores.get("pass", 0.0))
		out.append(c)


## 把 item 送到 to 给这份餐用：这份餐自己做出来的放在别处的 → 搬；配方说来自原料箱 → 拿；来自批量锅 → 从共享库存领一份（预留）
static func _carry_in(rules: ShopRules, worker: Dictionary, u: Dictionary, item: String, to: String) -> Dictionary:
	var shop := rules.shop
	for good in rules.serve.goods:
		if int(good.owner) != int(u.id) or good.item != item or int(good.res) != -1: continue
		if good.at == to or String(good.at).begins_with(HAND) or String(good.at).begins_with(SEAT): continue
		return _scored(rules, worker, _job("carry", int(u.id), -1, item, int(good.id), String(good.at), to), "carry", float(u.wait), "搬")
	var p := producer(shop, String(u.dish), item)
	if p < 0: return {}
	var s := shop.dish(String(u.dish)).steps[p]
	var st := shop.station(s.station)
	if st == null or not rules.station_unlocked(s.station) and st.companion_of.is_empty(): return {}
	if st.block == "supply":
		return _scored(rules, worker, _job("carry", int(u.id), -1, item, -1, s.station, to), "carry", float(u.wait), s.label)
	if st.block == "batch_pot":
		var free := goods_at(rules, s.station, item, SHARED, true)
		if free.is_empty(): return {}
		return _scored(rules, worker, _job("carry", int(u.id), -1, item, int(free[0].id), s.station, to), "carry", float(u.wait), s.label)
	return {}
