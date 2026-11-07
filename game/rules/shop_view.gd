class_name ShopView
extends RefCounted
## 快照（规格 §3.11）：界面只从这里读数据、只通过 ShopRules 的命令改数据。
## 这里把规则层状态拼成界面用的字典：机器面板、目标、任务、员工、招人、瓶颈、进行中加成。
## 所有文案模板来自店铺数据（goals.texts、机器说明、升级轨标签），这里不出现任何店铺、机器、菜品的名字。

var rules: ShopRules
var shop: SpecShop

## 升级效果 → 面板上“这一级做什么”的分类
const KIND_TEXT := {"capacity": "产能升级", "price": "售价升级", "menu": "开新口味", "both": "产能售价升级"}
const CAPACITY_KINDS := ["speed", "duration", "batch", "process_slots"]


func _init(rules_: ShopRules) -> void:
	rules = rules_
	shop = rules.shop


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
					return {"kind": "stage", "id": stage.stations[0], "current": mini(int(rules.gold), stage.cost), "target": stage.cost,
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
	if not st.materials.is_empty():
		card.sections.append("materials")
		card.materials = st.materials.map(func(m: SpecMaterial) -> Dictionary: return material_row(st, m))
	if id == rules.counter_id:
		if rules.dine_group() != null:
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
	return {"cost": cost, "error": rules.unlock_error(id), "title": title, "members": members, "note": note,
		"dish": dish_name(dish) if not dish.is_empty() else "", "dish_price": d.base_price() if d != null else 0.0,
		"description": shop.station(id).description, "frame": stage >= 0 and stage == next_stage()}


## 一条升级轨的面板行：{key, title, kind, level, max, cost, error, now, next, effect, star_next}
## now / next = 面板上“当前 → 升级后”两格；effect = 底下一整句（手机没有悬停，整句直接写出来）
func track_row(key: String) -> Dictionary:
	var t := rules.track_of(key)
	var id := key.get_slice("/", 0)
	var level := rules.level(key) if not key.begins_with("staff/") else int(rules.levels[key]) + 1
	var cost := rules.upgrade_cost(key)
	var row := {"key": key, "title": t.display_name, "label": t.effect_label, "level": level, "max": t.max_level(),
		"cost": cost, "error": rules.upgrade_error(key), "star_next": false, "kind": "", "now": "Lv.%d" % level,
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
	var per := "每批" if st.block == "batch_pot" else "每" + unit
	var preview := price_preview(key)
	var batch_now := rules.pot_batch(id) if st.block == "batch_pot" else 0
	var batch_next: int = rules.preview(key, func() -> int: return rules.pot_batch(id)) if cost >= 0 and st.block == "batch_pot" else batch_now
	var slots_now := rules.process_slots(id) if st.block == "pickup" else 0
	var slots_next: int = rules.preview(key, func() -> int: return rules.process_slots(id)) if cost >= 0 and st.block == "pickup" else slots_now
	var timed := st.block in ["batch_pot", "pickup"] or kinds.has("speed") or kinds.has("duration")
	var s_now := seconds(id)
	var s_next: float = rules.preview(key, func() -> float: return seconds(id)) if cost >= 0 else s_now
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
			row.now = "%s 金币 / %s" % [price_text(preview.now), unit]
			row.next = "%s 金币 / %s" % [price_text(preview.next), unit]
		elif timed:
			var pot := "锅" if st.block == "batch_pot" else unit
			row.now = "%.1f 秒 / %s" % [s_now, pot]
			row.next = "%.1f 秒 / %s" % [s_next, pot]
	# 整句
	var line := ""
	if cost < 0:
		if not preview.is_empty(): line = "%s %s 金" % [preview.sample, price_text(preview.now)]
		elif st.block == "pickup": line = "%s %d · 每%s %.1f 秒" % [st.params.get("slot_label", "加工位"), slots_now, unit, s_now]
		elif st.block == "batch_pot": line = "一锅 %d %s · 每锅 %.1f 秒" % [batch_now, unit, s_now]
		elif timed: line = "%s %.1f 秒" % [per, s_now]
		elif _opens_flavors(t): line = "口味全开"
	else:
		if not preview.is_empty():
			line = "%s每%s ×%.2f · %s %s → %s 金" % [preview.scope, unit, preview.mult, preview.sample, price_text(preview.now), price_text(preview.next)]
			if row.kind == "both":
				line = line + " · 更快" if row.star_next else "%s %s → %s 金 · %s %.1f → %.1f 秒" % [preview.sample,
					price_text(preview.now), price_text(preview.next), per, s_now, s_next]
		elif st.block == "pickup":
			line = "%s %d → %d" % [st.params.get("slot_label", "加工位"), slots_now, slots_next] if slots_next > slots_now else "每%s %.1f → %.1f 秒" % [unit, s_now, s_next]
		elif batch_next > batch_now:
			line = "一锅 %d → %d %s" % [batch_now, batch_next, unit]
		elif timed:
			line = "%s · %s %.1f → %.1f 秒" % [t.effect_label, per, s_now, s_next]
		for e in next_effects:
			if e.kind == "open_flavor":
				var m := st.material(e.target)
				line += (" · " if not line.is_empty() else "") + "开放" + (m.display_name if m != null else e.target) + "，客人更多"
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
	if not preview.is_empty(): return "%s %s 金" % [preview.sample, price_text(preview.now)]
	return "已满级"


## 这台机器干一次活要几秒（批量锅 = 一锅，其他 = 一份）
func seconds(id: String) -> float:
	var st := shop.station(id)
	if st.block == "batch_pot": return rules.pot_seconds(id)
	var result := rules.machine_seconds(id)
	# 员工在台前做的（手工台、出品台）：台子的秒数经提速
	if result <= 0.0 and st.params.has("seconds"): result = float(st.params.seconds) * rules.duration_mult(id) / rules.speed(id)
	return result


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
	if shown != null:
		for e in shown.effects:
			if e.kind == "price" and e.op == "mul": mult *= e.value
	var now := rules.dish_price(sample)
	var next: float = rules.preview(key, func() -> float: return rules.dish_price(sample)) if level <= t.levels.size() else -1.0
	var names: Array = []
	for d in shop.dishes:
		if d.id in scope: names.append(d.display_name)
	return {"scope": t.preview_label if not t.preview_label.is_empty() else "、".join(names), "sample": dish_name(sample), "now": now, "next": next, "mult": mult}


## 机器上的一个物料行：原料箱（先解锁箱）或口味（机器几级开放）
func material_row(st: SpecStation, m: SpecMaterial) -> Dictionary:
	var key := st.id + "/" + m.id
	var level := rules.level(key)
	var row := {"id": m.id, "key": key, "name": m.display_name, "icon": m.icon if not m.icon.is_empty() else m.id,
		"level": level, "cost": rules.upgrade_cost(key), "error": rules.upgrade_error(key), "state": "open",
		"requires": m.track.requires_level, "effect": ""}
	if rules.boxes.has(m.id) and not rules.boxes[m.id]:
		row.state = "box"
		row.cost = m.box_cost
		row.error = rules.box_error(m.id)
		row.box_station = station_name(m.box_station)
		row.effect = ("解锁%s后开放" if row.error.begins_with("请先解锁") else "解锁后%s才有原料") % row.box_station
		if row.error.begins_with("请先解锁"): row.state = "box_closed"
		return row
	if rules.level(st.id) < m.track.requires_level:
		row.state = "closed"
		row.effect = "%s Lv%d 开放" % [st.display_name, m.track.requires_level]
		return row
	var dish := shop.dish(m.item)
	var preview := price_preview(key)
	# 按倍率涨价的物料（原料）写“每杯 ×1.05”；按菜加价的口味直接写售价
	if not preview.is_empty() and not is_equal_approx(float(preview.mult), 1.0):
		# 物料行的售价按整数显示（和旧面板一致）
		row.effect = ("%s每%s ×%.2f · %s %d 金" % [preview.scope, st.params.get("unit", "份"), preview.mult, preview.sample, int(preview.now)]
			if row.cost < 0 else "%s每%s ×%.2f · %s %d → %d 金" % [preview.scope, st.params.get("unit", "份"), preview.mult,
				preview.sample, int(preview.now), int(preview.next)])
	elif dish != null:
		var now := rules.dish_price(dish.id)
		row.effect = "售价 %s 金" % price_text(now)
		if row.cost >= 0:
			row.effect = "售价 %s → %s 金" % [price_text(now), price_text(rules.preview(key, func() -> float: return rules.dish_price(dish.id)))]
	return row


func seats() -> Dictionary:
	var g := rules.dine_group()
	var total := rules.seat_total()
	var full := g.start + g.step * g.costs.size()
	return {"total": total, "max": full, "used": rules.diners.size() + rules.seated_orders(), "step": g.step,
		"cost": rules.seat_cost(), "error": rules.seat_error()}


func flyer() -> Dictionary:
	var single := shop.fulfillment.handoff == "single"
	var wait := maxf(0.0, rules.flyer_ready_at - rules.clock) if single else rules.flyer_wait
	var cost := rules.upgrade_cost("flyer")
	var next_customers := rules.flyer_customers()
	var next_cooldown := rules.flyer_cooldown()
	if cost >= 0:
		next_customers = rules.preview("flyer", func() -> int: return rules.flyer_customers())
		next_cooldown = rules.preview("flyer", func() -> float: return rules.flyer_cooldown())
	return {"level": rules.level("flyer"), "customers": rules.flyer_customers(), "cooldown": rules.flyer_cooldown(),
		"seconds": shop.flyer.wave_seconds, "wait": wait, "wave": rules.flyer_wave, "pending": rules.flyer_left if single else rules.flyer_pending,
		"error": rules.flyer_error(), "queue_full": rules.queue_size() >= rules.queue_capacity(),
		"upgradable": shop.flyer.track != null and not shop.flyer.track.levels.is_empty(), "gap": shop.flyer.gap,
		"upgrade_cost": cost, "upgrade_error": rules.upgrade_error("flyer"), "next_customers": next_customers, "next_cooldown": next_cooldown}


## 现在能在这台机器的面板里花钱（红 ↑）
func can_buy(id: String) -> bool:
	if not rules.station_unlocked(id): return false
	if rules.track_of(id) != null and rules.upgrade_error(id).is_empty(): return true
	if id == rules.counter_id:
		if rules.dine_group() != null and rules.seat_error().is_empty(): return true
		if shop.flyer != null and rules.upgrade_error("flyer").is_empty(): return true
		# 传单只在队伍还有空的时候提示
		if shop.flyer != null and rules.flyer_error().is_empty() and rules.queue_size() * 2 < rules.queue_capacity(): return true
	var st := shop.station(id)
	for m in st.materials:
		if rules.upgrade_error(id + "/" + m.id).is_empty(): return true
	return false


## 机器此刻在干什么：{working, progress, need（待取 n / 待操作）, input, processing, output}
func machine_status(id: String) -> Dictionary:
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
	if s.phase == "cook" and rules.pot_seconds(id) > 0.0: progress = clampf(1.0 - float(s.remaining) / rules.pot_seconds(id), 0.0, 1.0)
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
	return {"cost": rules.hire_cost(), "error": rules.hire_error(), "kind": kind, "name": k.display_name,
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
	return {"side": side, "title": t.display_name, "bought": bought, "total": t.levels.size(), "rows": rows, "cost": cost,
		"error": rules.upgrade_error(key) if cost >= 0 else "已全部升级", "name": rows[bought].name if bought < rows.size() else ""}


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
	var label: String = worker.get("task_label", "")
	if label.is_empty(): label = "idle"
	var job: Dictionary = worker.get("job", {})
	var at: String = job.get("dst", "")
	var values := {"to": station_name(at), "item": item_name(String(job.get("item", "")))}
	var specific := text("task_%s@%s" % [label, at], values)
	if not specific.is_empty(): return specific
	return text("task_" + label, values, label)


## 员工卡片：{id, kind, name, role, description, level, stats{walk, work, carry}, deployed, post, task}
func worker_card(worker: Dictionary) -> Dictionary:
	var kind := rules._kind(String(worker.kind))
	return {"id": worker.id, "kind": worker.kind, "name": kind.display_name, "role": kind.role, "description": kind.description,
		"level": int(worker.get("level", 1)), "stats": worker.stats, "deployed": worker.deployed, "post": worker.post,
		"task": task_text(worker)}


## 物品怎么画：{art: art/reference 里的图名, tint}
func item_art(id: String) -> Dictionary:
	var dish := shop.dish(id)
	var key: String = dish.item if dish != null and not dish.item.is_empty() else id
	for item in shop.items:
		if item.id == key or item.id == id:
			return {"art": item.art if not item.art.is_empty() else "pearl_tea", "tint": item.tint}
	return {"art": "pearl_tea", "tint": Color.WHITE}


## 在这台机器前干活朝哪个方向（8 方向；-1 = 不转）
func work_direction(station_id: String) -> int:
	var st := shop.station(station_id)
	return int(st.params.get("facing", -1)) if st != null else -1


## 正从展示柜接现成饮品的员工：返回那台机器（动画按“干活”放）
func pouring_station(worker: Dictionary) -> String:
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
