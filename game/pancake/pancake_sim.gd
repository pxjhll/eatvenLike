class_name PancakeSim
extends RefCounted
## 首店煎饼果子摊玩法（设计稿 v0.5）。流动岗：空闲员工到前台接队首客人，一人把这一单从收钱做到递餐。
## 坐标是 v04 原画的源坐标（937×1678），员工真实走路，所以走路时间按摆位算。
## 纯逻辑，不依赖场景：画面和 bot 都只读 state。

const STATION_ORDER := ["soy_milk", "rear_equipment", "fryer", "topping"]
const STATION_NAMES := {"soy_milk": "豆浆机", "rear_equipment": "鏊子", "fryer": "油锅", "topping": "加料台"}
## 开局就在的台子（前台、打包台、货架装饰）。
const OPENING_STATIONS := ["front_counter", "packing", "rack"]
## 和鏊子一起开放的台子。
const COMPANIONS := {"rear_equipment": ["raw_ingredients"]}

## 员工站位（脚底，源坐标）。
const POINTS := {
	"register": Vector2(697, 768), "soy": Vector2(300, 742), "raw": Vector2(790, 430),
	"griddle": Vector2(420, 432), "fryer": Vector2(272, 500), "crisps": Vector2(252, 626),
	"topping": Vector2(560, 562), "packing": Vector2(716, 640), "home": Vector2(520, 742),
}
## 顾客位置：队伍从收银机前往左排；付了钱的人优先坐坐垫等饼，没坐垫就站在左边；排不下的队尾也坐坐垫。
const QUEUE_SPOTS := [Vector2(684, 1074), Vector2(584, 1088), Vector2(484, 1094), Vector2(384, 1094), Vector2(284, 1088), Vector2(184, 1082)]
const WAIT_SPOTS := [Vector2(96, 1086), Vector2(60, 1130), Vector2(150, 1140), Vector2(40, 1060)]
## 坐垫中心，按解锁批次排列（2 / 3 / 4 个，累计 2 / 5 / 9）。
const SEAT_SPOTS := [Vector2(114, 1236), Vector2(353, 1236), Vector2(598, 1221), Vector2(726, 1172), Vector2(836, 1221),
	Vector2(602, 1436), Vector2(830, 1441), Vector2(127, 1451), Vector2(347, 1451)]
const SPAWN := Vector2(468, 1720)

const DISHES := {
	"soy": {"name": "豆浆", "price": 6.0},
	"plain": {"name": "原味煎饼", "price": 15.0},
	"guozi": {"name": "煎饼果子", "price": 22.0},
	"ham": {"name": "火腿煎饼果子", "price": 28.0, "tops": 1, "lv": 1},
	"floss": {"name": "肉松煎饼果子", "price": 29.0, "tops": 1, "lv": 2},
	"bacon": {"name": "培根煎饼果子", "price": 30.0, "tops": 1, "lv": 3},
	"family": {"name": "全家福", "price": 40.0, "tops": 3, "lv": 5},
}

var cfg := {
	"start_gold": 10.0,
	"unlock_cost": {"soy_milk": 10, "rear_equipment": 50, "fryer": 160, "topping": 320},
	# 段 0 = 只有豆浆机；之后每开一台加一段
	"interval": [10.0, 7.5, 6.0, 4.5],
	"standing": [3, 4, 4, 6],
	"cushions": [0, 2, 5, 9],
	"weights": [
		{"soy": 1.0},
		{"soy": 0.4, "plain": 0.6},
		{"soy": 0.3, "plain": 0.2, "guozi": 0.5},
		{"soy": 0.25, "plain": 0.1, "guozi": 0.2, "meat": 0.45},
	],
	"soy_addon": 0.3,
	"staff_slots": [1, 2, 3, 4],
	"hire_cost": [30, 100, 200],
	"walk_speed": 200.0,
	"take": 1.5, "pour": 1.5, "raw": 1.0, "grill": 10.0, "crisp": 0.5, "top": 1.5, "pack": 2.5, "hand": 0.5,
	"fry_load": 2.0, "fry_cook": 18.0, "fry_unload": 2.0, "fry_batch": 4, "crisp_cap": 8, "crisp_low": 3, "crisp_start": 4,
	"patience": 60.0,
	"late_grow": 1.15,
	"rating_minutes": [22.0, 28.0],
	"flyer_cooldown": 120.0, "flyer_wave": 4, "flyer_gap": 3.0,
	# 每项升级只做一件事
	"upgrades": {
		"rear_equipment": {"name": "鏊子", "effect": "speed", "mult": 0.86, "max": 9, "cost": 15.0, "grow": 1.5},
		"fryer": {"name": "油锅", "effect": "speed", "mult": 0.86, "max": 8, "cost": 45.0, "grow": 1.4},
		"soy_milk": {"name": "豆浆机", "effect": "price", "mult": 1.08, "max": 8, "cost": 12.0, "grow": 1.45},
		"topping": {"name": "加料台", "effect": "price", "mult": 1.08, "max": 8, "cost": 60.0, "grow": 1.35},
	},
	"tasks": [
		{"id": "soy30", "text": "卖出 30 杯豆浆", "dish": "soy", "count": 30},
		{"id": "plain20", "text": "卖出 20 张原味煎饼", "dish": "plain", "count": 20},
		{"id": "guozi30", "text": "卖出 30 份煎饼果子", "dish": "guozi", "count": 30},
		{"id": "floss", "text": "开出肉松口味", "flavor": "floss"},
		{"id": "family5", "text": "卖出 5 份全家福", "dish": "family", "count": 5},
	],
}

var rng := RandomNumberGenerator.new()
var clock := 0.0
var gold := 0.0
var earned := 0.0
var unlocked := {}
var levels := {}
var staff: Array = []
var customers: Array = []
var queue: Array = []          # customer ids standing/sitting in line, head first
var sold := {}
var lost := 0
var crisps := 0
var fryer := {"state": "idle", "timer": 0.0, "user": -1}
var griddle_user := -1
var next_customer := 0.0
var flyer_ready_at := 0.0
var flyer_left := 0
var flyer_timer := 0.0
var events: Array = []         # [clock, text] for the HUD / bot
## 第一次满足完店条件的时刻（-1 = 还没完店），结店评分用。
var completed_at := -1.0
var _next_customer_id := 1
var _next_staff_id := 1


func _init(seed := 0) -> void:
	rng.seed = seed
	reset()


func reset() -> void:
	clock = 0.0
	gold = cfg.start_gold
	completed_at = -1.0
	earned = 0.0
	unlocked = {}
	for key in OPENING_STATIONS: unlocked[key] = true
	levels = {}
	for key in cfg.upgrades: levels[key] = 1
	staff = []
	customers = []
	queue = []
	sold = {}
	for dish in DISHES: sold[dish] = 0
	lost = 0
	crisps = 0
	fryer = {"state": "idle", "timer": 0.0, "user": -1}
	griddle_user = -1
	next_customer = 2.0
	flyer_ready_at = 0.0
	flyer_left = 0
	events = []
	_next_customer_id = 1
	_next_staff_id = 1
	_add_staff()


# ---------- queries ----------

## 段：开了几台功能台（豆浆机开之前也是 0 段，但没有客人来）。
func stage() -> int:
	var n := 0
	for key in STATION_ORDER.slice(1):
		if unlocked.get(key, false): n += 1
	return n


func is_open() -> bool:
	return unlocked.get("soy_milk", false)


func next_unlock() -> String:
	for key in STATION_ORDER:
		if not unlocked.get(key, false): return key
	return ""


func unlock_cost(key: String) -> int:
	return int(cfg.unlock_cost.get(key, 0))


func can_unlock(key: String) -> bool:
	return key == next_unlock() and gold >= unlock_cost(key)


func upgrade_cost(key: String) -> int:
	var u: Dictionary = cfg.upgrades[key]
	# 后期每级再贵 ×1.15（同奶茶店第 4 轮），满级成为“多留一会儿拿奖杯”的取舍
	return int(round(u.cost * pow(u.grow * float(cfg.late_grow), levels[key] - 1)))


func upgrade_available(key: String) -> bool:
	return cfg.upgrades.has(key) and unlocked.get(key, false) and levels[key] < int(cfg.upgrades[key].max)


func can_upgrade(key: String) -> bool:
	return upgrade_available(key) and gold >= upgrade_cost(key)


func staff_slots() -> int:
	return int(cfg.staff_slots[stage()]) if is_open() else 1


func hire_cost() -> int:
	var n := staff.size() - 1
	if n >= cfg.hire_cost.size(): return -1
	return int(cfg.hire_cost[n])


func can_hire() -> bool:
	return staff.size() < staff_slots() and hire_cost() >= 0 and gold >= hire_cost()


func queue_capacity() -> int:
	return standing_slots() + cushion_count()


func standing_slots() -> int:
	return int(cfg.standing[stage()])


func cushion_count() -> int:
	return int(cfg.cushions[stage()])


func cushion_stage() -> int:
	return stage()


func flyer_cooldown_left() -> float:
	return maxf(0.0, flyer_ready_at - clock)


func flavors() -> Array:
	var out := []
	if not unlocked.get("topping", false): return out
	for dish in DISHES:
		if DISHES[dish].has("lv") and levels.topping >= int(DISHES[dish].lv): out.append(dish)
	return out


func menu() -> Array:
	var out := []
	if unlocked.get("soy_milk", false): out.append("soy")
	if unlocked.get("rear_equipment", false): out.append("plain")
	if unlocked.get("fryer", false): out.append("guozi")
	out.append_array(flavors())
	return out


func price(dish: String) -> float:
	if dish == "soy":
		return DISHES.soy.price * _mult("soy_milk")
	var d: Dictionary = DISHES[dish]
	if d.has("tops"):
		return DISHES.guozi.price + (d.price - DISHES.guozi.price) * _mult("topping")
	return d.price


func order_price(c: Dictionary) -> int:
	var total := 0.0
	if c.kind != "soy": total += price(c.kind)
	if c.soy: total += price("soy")
	return int(round(total))


func task_done(task: Dictionary) -> bool:
	if task.has("flavor"): return task.flavor in flavors()
	return int(sold.get(task.dish, 0)) >= int(task.count)


func tasks_done() -> int:
	var n := 0
	for t in cfg.tasks:
		if task_done(t): n += 1
	return n


## 完店：菜单全开、任务全部完成（不要求满级）。
func shop_complete() -> bool:
	return next_unlock().is_empty() and "family" in flavors() and tasks_done() == cfg.tasks.size()


func customer(id: int) -> Dictionary:
	for c in customers:
		if c.id == id: return c
	return {}


func total_sold() -> int:
	var n := 0
	for d in sold: n += int(sold[d])
	return n


# ---------- player actions ----------

func unlock(key: String) -> bool:
	if not can_unlock(key): return false
	gold -= unlock_cost(key)
	unlocked[key] = true
	for extra in COMPANIONS.get(key, []): unlocked[extra] = true
	if key == "fryer": crisps = int(cfg.crisp_start)
	if key == "soy_milk": next_customer = 1.5
	_event("开放了%s" % STATION_NAMES[key])
	return true


func upgrade(key: String) -> bool:
	if not can_upgrade(key): return false
	gold -= upgrade_cost(key)
	levels[key] += 1
	return true


func hire() -> bool:
	if not can_hire(): return false
	gold -= hire_cost()
	_add_staff()
	_event("招到第 %d 名员工" % staff.size())
	return true


func send_flyers() -> bool:
	if not is_open() or flyer_cooldown_left() > 0.0: return false
	flyer_left += int(cfg.flyer_wave)
	flyer_timer = 0.0
	flyer_ready_at = clock + float(cfg.flyer_cooldown)
	return true


# ---------- simulation ----------

func step(dt: float) -> void:
	clock += dt
	if is_open(): _arrivals(dt)
	_customers_tick(dt)
	if fryer.state == "cook":
		fryer.timer -= dt
		if fryer.timer <= 0.0: fryer.state = "done"
	for s in staff: _staff_tick(s, dt)
	if completed_at < 0.0 and shop_complete(): completed_at = clock


func run(seconds: float, dt := 0.1) -> void:
	var t := 0.0
	while t < seconds:
		step(dt)
		t += dt


func _arrivals(dt: float) -> void:
	next_customer -= dt
	if flyer_left > 0:
		flyer_timer -= dt
		if flyer_timer <= 0.0:
			flyer_left -= 1
			flyer_timer = float(cfg.flyer_gap)
			_spawn()
	if next_customer <= 0.0:
		var interval: float = cfg.interval[stage()]
		next_customer = -log(1.0 - rng.randf() * 0.999) * interval
		_spawn()


func _spawn() -> void:
	if queue.size() >= queue_capacity():
		lost += 1
		return
	var kind := _pick_dish()
	var soy := kind == "soy" or rng.randf() < float(cfg.soy_addon)
	var c := {"id": _next_customer_id, "kind": kind, "soy": soy, "state": "queue", "wait": 0.0,
		"pos": SPAWN, "art_index": _next_customer_id, "spot": SPAWN, "seated": false}
	_next_customer_id += 1
	customers.append(c)
	queue.append(c.id)
	_assign_spots()


func _pick_dish() -> String:
	var w: Dictionary = cfg.weights[stage()].duplicate()
	if w.has("meat"):
		var share: float = w.meat
		w.erase("meat")
		var fl := flavors()
		if fl.is_empty(): w.guozi = float(w.get("guozi", 0.0)) + share
		for f in fl: w[f] = share / fl.size()
	var total := 0.0
	for k in w: total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0: return k
	return w.keys()[-1]


func _customers_tick(dt: float) -> void:
	var leaving := []
	for c in customers:
		if c.state == "queue":
			c.wait += dt
			if c.wait > float(cfg.patience) and not c.get("claimed", false):
				c.state = "leaving"
				c.spot = SPAWN
				queue.erase(c.id)
				lost += 1
		if c.state == "leaving" and c.pos.distance_to(SPAWN) < 4.0:
			leaving.append(c)
		var to: Vector2 = c.spot - c.pos
		var move := 140.0 * dt
		c.pos = c.spot if to.length() <= move else c.pos + to.normalized() * move
	for c in leaving: customers.erase(c)
	_assign_spots()


func _assign_spots() -> void:
	var seats := cushion_count()
	var seat := 0
	var w := 0
	for c in customers:
		if c.state != "paid": continue
		if seat < seats:
			c.spot = SEAT_SPOTS[seat]
			c.seated = true
			seat += 1
		else:
			c.spot = WAIT_SPOTS[mini(w, WAIT_SPOTS.size() - 1)]
			c.seated = false
			w += 1
	var standing := standing_slots()
	for i in queue.size():
		var c := customer(queue[i])
		if i < standing or seat >= seats:
			c.spot = QUEUE_SPOTS[mini(i, QUEUE_SPOTS.size() - 1)]
			c.seated = false
		else:
			c.spot = SEAT_SPOTS[seat]
			c.seated = true
			seat += 1


func _add_staff() -> void:
	var arts := ["rabbit", "gray_cat", "bear", "rabbit"]
	var s := {"id": _next_staff_id, "art": arts[(_next_staff_id - 1) % arts.size()], "pos": POINTS.home,
		"target": "", "walking": false, "phase": "idle", "task_label": "待命", "timer": 0.0,
		"order": -1, "steps": [], "step": 0, "chore": "", "speed": float(cfg.walk_speed)}
	_next_staff_id += 1
	staff.append(s)


func _speed(key: String) -> float:
	var u: Dictionary = cfg.upgrades[key]
	return pow(u.mult, levels[key] - 1) if u.effect == "speed" else 1.0


func _mult(key: String) -> float:
	var u: Dictionary = cfg.upgrades[key]
	return pow(u.mult, levels[key] - 1) if u.effect == "price" else 1.0


func _order_steps(c: Dictionary) -> Array:
	var steps := [["register", "take", float(cfg.take), "收钱"]]
	if c.soy: steps.append(["soy", "pour", float(cfg.pour), "打豆浆"])
	if c.kind != "soy":
		steps.append(["raw", "raw", float(cfg.raw), "拿面糊鸡蛋"])
		steps.append(["griddle", "grill", float(cfg.grill), "摊饼"])
		if c.kind != "plain": steps.append(["crisps", "crisp", float(cfg.crisp), "拿薄脆"])
		if DISHES[c.kind].has("tops"): steps.append(["topping", "top", float(cfg.top) * int(DISHES[c.kind].tops), "加料"])
		steps.append(["packing", "pack", float(cfg.pack), "卷饼装袋"])
	steps.append(["register", "hand", float(cfg.hand), "递餐"])
	return steps


func _staff_tick(s: Dictionary, dt: float) -> void:
	if s.walking:
		# 回待命点的路上也能接新活
		if s.target == "home" and s.order < 0 and s.chore.is_empty() and _find_job(s): return
		_walk(s, dt)
		return
	if s.phase == "work":
		s.timer -= dt
		if s.timer > 0.0: return
		_finish_work(s)
	_decide(s)


func _walk(s: Dictionary, dt: float) -> void:
	var goal: Vector2 = POINTS[s.target]
	var to: Vector2 = goal - s.pos
	var move: float = float(s.speed) * dt
	if to.length() <= move:
		s.pos = goal
		s.walking = false
		_arrived(s)
	else:
		s.pos += to.normalized() * move


func _go(s: Dictionary, point: String, label: String) -> void:
	s.target = point
	s.task_label = label
	if s.pos.distance_to(POINTS[point]) < 1.0:
		s.walking = false
		_arrived(s)
	else:
		s.walking = true
		s.phase = "walk"


func _work(s: Dictionary, seconds: float) -> void:
	s.phase = "work"
	s.timer = seconds


## Free staff: fryer chores first, then the next customer in line.
func _decide(s: Dictionary) -> void:
	if s.phase == "work" or s.walking: return
	if not s.chore.is_empty(): return
	if s.order >= 0:
		_next_step(s)
		return
	if _find_job(s): return
	# 没活就原地等，不来回跑；只有和别人挤在同一处时才让到待命点
	if s.target != "home" and _crowded(s):
		_go(s, "home", "待命")
	s.phase = "walk" if s.walking else "idle"
	s.task_label = "待命"


func _crowded(s: Dictionary) -> bool:
	for o in staff:
		if o.id != s.id and Vector2(o.pos).distance_to(s.pos) < 60.0: return true
	return false


func _find_job(s: Dictionary) -> bool:
	if _try_fryer_chore(s, false): return true
	if queue.is_empty(): return false
	var c := customer(queue[0])
	if c.get("claimed", false): return false
	c.claimed = true
	s.order = c.id
	s.steps = _order_steps(c)
	s.step = 0
	s.walking = false
	_next_step(s)
	return true


func _try_fryer_chore(s: Dictionary, blocked: bool) -> bool:
	if not unlocked.get("fryer", false) or fryer.user != -1: return false
	if fryer.state == "done":
		fryer.user = s.id
		s.chore = "unload"
		_go(s, "fryer", "捞薄脆")
		return true
	if fryer.state == "idle" and (crisps < int(cfg.crisp_low) or blocked) and crisps < int(cfg.crisp_cap):
		fryer.user = s.id
		s.chore = "load"
		_go(s, "fryer", "下锅炸薄脆")
		return true
	return false


func _next_step(s: Dictionary) -> void:
	var st: Array = s.steps[s.step]
	_go(s, st[0], st[3])


func _arrived(s: Dictionary) -> void:
	if s.chore == "load":
		s.task_label = "下锅炸薄脆"
		_work(s, float(cfg.fry_load))
		return
	if s.chore == "unload":
		s.task_label = "捞薄脆"
		_work(s, float(cfg.fry_unload))
		return
	if s.order < 0:
		s.phase = "idle"
		s.task_label = "待命"
		return
	var st: Array = s.steps[s.step]
	match st[1]:
		"grill":
			if griddle_user != -1 and griddle_user != s.id:
				s.phase = "wait"
				s.task_label = "等鏊子"
				return
			griddle_user = s.id
			_work(s, float(st[2]) * _speed("rear_equipment"))
		"crisp":
			if crisps < 1:
				s.phase = "wait"
				s.task_label = "等薄脆"
				_try_fryer_chore(s, true)
				return
			crisps -= 1
			_work(s, float(st[2]))
		_:
			_work(s, float(st[2]))
	s.task_label = st[3]


func _finish_work(s: Dictionary) -> void:
	s.phase = "idle"
	if s.chore == "load":
		fryer.state = "cook"
		fryer.timer = float(cfg.fry_cook) * _speed("fryer")
		fryer.user = -1
		s.chore = ""
		return
	if s.chore == "unload":
		crisps = mini(int(cfg.crisp_cap), crisps + int(cfg.fry_batch))
		fryer.state = "idle"
		fryer.user = -1
		s.chore = ""
		return
	var c := customer(s.order)
	var st: Array = s.steps[s.step]
	match st[1]:
		"take":
			queue.erase(c.id)
			var paid := order_price(c)
			gold += paid
			earned += paid
			c.paid = paid
			c.state = "paid"
			_assign_spots()
		"grill":
			griddle_user = -1
		"hand":
			c.state = "leaving"
			c.spot = SPAWN
			sold[c.kind] = int(sold[c.kind]) + 1
			if c.soy and c.kind != "soy": sold.soy = int(sold.soy) + 1
			s.order = -1
			s.steps = []
			_assign_spots()
			return
	s.step += 1


func _event(text: String) -> void:
	events.append([clock, text])


# ---------- 结店 ----------

## 结店评分 1–3 星：完店用时 + 流失率。以后用来换员工升级（还没做）。
func rating() -> int:
	if completed_at < 0.0: return 0
	var stars := 1
	var minutes := completed_at / 60.0
	if minutes <= float(cfg.rating_minutes[1]): stars += 1
	if minutes <= float(cfg.rating_minutes[0]): stars += 1
	var served := total_sold() + lost
	if served > 0 and float(lost) / served > 0.2: stars -= 1
	return clampi(stars, 1, 3)


## 结店总结：用时、营业额、卖出份数、卖得最好的 3 样、各台等级、员工数、评分。
func summary() -> Dictionary:
	var top := []
	for dish in sold:
		if int(sold[dish]) > 0: top.append([int(sold[dish]), dish])
	top.sort()
	top.reverse()
	return {"shop": "pancake", "seconds": completed_at if completed_at >= 0.0 else clock, "played": clock,
		"earned": int(earned), "sold": total_sold(), "lost": lost, "top": top.slice(0, 3),
		"levels": levels.duplicate(), "staff": staff.size(), "rating": rating()}


# ---------- save ----------

## 店内存档：只存进度，不存走到一半的员工和排队的客人（读档后从待命开始）。
func to_dict() -> Dictionary:
	return {"clock": clock, "gold": gold, "earned": earned, "unlocked": unlocked.duplicate(),
		"levels": levels.duplicate(), "sold": sold.duplicate(), "lost": lost, "crisps": crisps,
		"staff": staff.size(), "flyer_left": maxf(0.0, flyer_ready_at - clock), "completed_at": completed_at}


func load_dict(d: Dictionary) -> String:
	for key in ["clock", "gold", "unlocked", "levels", "sold", "staff"]:
		if not d.has(key): return "缺少 " + key
	if not d.unlocked is Dictionary or not d.levels is Dictionary or not d.sold is Dictionary:
		return "格式不对"
	var n := int(d.staff)
	if n < 1 or n > int(cfg.staff_slots[-1]): return "员工人数不对"
	reset()
	clock = float(d.clock)
	gold = float(d.gold)
	earned = float(d.get("earned", 0.0))
	for key in d.unlocked: unlocked[String(key)] = bool(d.unlocked[key])
	for key in levels:
		if d.levels.has(key): levels[key] = clampi(int(d.levels[key]), 1, int(cfg.upgrades[key].max))
	for key in sold:
		if d.sold.has(key): sold[key] = maxi(0, int(d.sold[key]))
	lost = int(d.get("lost", 0))
	crisps = int(d.get("crisps", 0))
	flyer_ready_at = clock + float(d.get("flyer_left", 0.0))
	completed_at = float(d.get("completed_at", -1.0))
	while staff.size() < n: _add_staff()
	return ""
