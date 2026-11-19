extends RefCounted
## All clocks use shop time. Independent RNG keeps a reveal stable across saves.
const STORABLE := ["walk", "machine", "tips", "guest"]
const FUN := ["stamp", "flower", "postcard"]
const WEIGHTS := {"cash":20, "walk":18, "machine":18, "tips":16, "guest":13, "stamp":5, "flower":5, "postcard":5}
const TITLES := {"cash":"金币红包", "walk":"全员加速", "machine":"机器加速", "tips":"幸运小费", "guest":"熟客来访", "stamp":"被猫盖章了", "flower":"今日最佳员工", "postcard":"店长的旅行明信片"}
const DETAILS := {"walk":"移速 +40% · 20秒", "machine":"自动加工 +50% · 20秒", "tips":"小费 +20% · 3单", "guest":"一位熟客自带餐盒来点单", "stamp":"店长留下了一枚爪印。", "flower":"一朵小红花，送给今天的你。", "postcard":"路过桥头的鱼铺，本想问个路。鱼干买了三包，路忘了问。——三花店长"}
const REFILL := 180.0
var progress := 0
var charges := 0
var opened := false
var next_at := 0.0
var held: Array = []
var pending := ""
var amount := 0
var lucky_next := false
var walk_until := 0.0
var machine_until := 0.0
var tips := 0
var guests := 0
var history: Array = []
var random := RandomNumberGenerator.new()

func slots() -> int:
	return 2 if progress >= 5 else 1

func sync(now: float, sold: int) -> void:
	if not opened and sold > 0:
		opened = true
		charges = 1
		next_at = now + REFILL
	while opened and charges < 2 and now + 0.00001 >= next_at:
		charges += 1
		next_at = next_at + REFILL if charges < 2 else 0.0

func receipt(base: int) -> int:
	if base <= 0: return 0
	history.append(base)
	if history.size() > 5: history.pop_front()
	if tips == 0: return 0
	tips -= 1
	return maxi(1, roundi(base * 0.2))

func _machine_ready(owner: RefCounted) -> bool:
	for id in owner.runtime._definition.machines:
		if owner.station_unlocked(id) and not owner.runtime._definition.machines[id].profile.get("manual", false): return true
	return false

func draw(owner: RefCounted) -> bool:
	sync(owner.clock, owner.sold)
	if owner.runtime == null or charges < 1 or not pending.is_empty(): return false
	if charges == 2: next_at = owner.clock + REFILL
	charges -= 1
	progress = mini(5, progress + 1)
	var pool := WEIGHTS.duplicate()
	if not _machine_ready(owner): pool.erase("machine")
	if owner.workers.is_empty(): pool.erase("flower")
	# Keep cosmetic probability at 15% even when machine tickets are unavailable.
	var cosmetic := not lucky_next and random.randf() < 0.15
	var choices := []
	var weight := 0
	for id in pool:
		if (id in FUN) != cosmetic: continue
		choices.append(id)
		weight += int(pool[id])
	var roll := random.randi_range(1, weight)
	for id in choices:
		roll -= int(pool[id])
		if roll <= 0:
			pending = id
			break
	lucky_next = pending in FUN
	amount = 0
	if pending == "cash":
		var total := 0
		for income in history: total += int(income)
		var average := float(total) / history.size() if not history.is_empty() else float(owner.revenue) / maxi(1, owner.sold)
		amount = maxi(1, roundi(2.0 * average))
		owner.gold += amount
	elif pending == "flower":
		amount = int(owner.workers[random.randi_range(0, owner.workers.size()-1)].id)
	return true

func act(owner: RefCounted, action: String, index := 0) -> bool:
	match action:
		"draw": return draw(owner)
		"swap":
			if held.size() != 2 or pending != "": return false
			held.reverse()
		"save":
			if pending not in STORABLE or held.size() >= slots(): return false
			held.push_front(pending)
			pending = ""
		"use":
			if pending not in STORABLE: return false
			_apply(owner.clock, pending)
			pending = ""
		"replace":
			if pending not in STORABLE or held.size() != slots() or index < 0 or index >= held.size(): return false
			_apply(owner.clock, held[index])
			held[index] = pending
			pending = ""
		"held":
			if held.is_empty() or pending != "": return false
			_apply(owner.clock, held.pop_front())
		"done":
			if pending != "cash" and pending not in FUN: return false
			pending = ""
		_: return false
	return true

func _apply(now: float, id: String) -> void:
	match id:
		"walk": walk_until = maxf(now, walk_until) + 20.0
		"machine": machine_until = maxf(now, machine_until) + 20.0
		"tips": tips += 3
		"guest": guests += 1

func snapshot() -> Dictionary:
	return {"progress":progress, "charges":charges, "opened":opened, "next_at":next_at,
		"held":held.duplicate(), "pending":pending, "amount":amount, "lucky_next":lucky_next,
		"walk_until":walk_until, "machine_until":machine_until, "tips":tips, "guests":guests,
		"history":history.duplicate(), "rng":random.state}

func restore(data: Dictionary) -> bool:
	var model := snapshot()
	if data.size() != model.size(): return false
	for key in model:
		if typeof(data.get(key)) != typeof(model[key]): return false
	for key in ["next_at","walk_until","machine_until"]:
		if not is_finite(data[key]) or data[key] < 0: return false
	if data.progress not in range(6) or data.charges not in range(3) or data.tips < 0 or data.guests < 0 or data.amount < 0: return false
	if data.pending != "" and not WEIGHTS.has(data.pending): return false
	if data.held.size() > (2 if data.progress == 5 else 1) or data.history.size() > 5: return false
	for id in data.held:
		if id not in STORABLE: return false
	for income in data.history:
		if not income is int or income < 1: return false
	for key in data:
		if key == "rng": random.state = data.rng
		else: set(key, data[key].duplicate() if data[key] is Array else data[key])
	return true
