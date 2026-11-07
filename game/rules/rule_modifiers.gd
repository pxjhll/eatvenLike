class_name RuleModifiers
extends RefCounted
## 加成栈（规格 §3.13）：所有倍率类数值都从这里算，不在各处自己乘。
## 一条加成 = 来源 + 作用对象 + 乘/加/设 + 数值 + 剩余秒数（-1 = 一直有效）。
## 计算顺序固定：先 set（后加的覆盖先加的），再连乘 mul，最后加 add。

var entries: Array = []


## 加一条。target 空 = 全店；dishes 空 = 不限菜；part 空 = 整道菜。
func add(source: String, source_id: String, kind: String, op: String, value: float, target := "",
		dishes: Array = [], part := "", seconds := -1.0) -> Dictionary:
	var entry := {"source": source, "source_id": source_id, "kind": kind, "op": op, "value": value,
		"target": target, "dishes": dishes.duplicate(), "part": part, "left": seconds, "total": seconds}
	entries.append(entry)
	return entry


func add_effect(source: String, source_id: String, effect: SpecEffect, seconds := -1.0, default_dishes: Array = []) -> Dictionary:
	var dishes: Array = effect.dishes if not effect.dishes.is_empty() else default_dishes
	return add(source, source_id, effect.kind, effect.op, effect.value, effect.target, dishes, effect.price_part, seconds)


func remove(source: String, source_id := "") -> void:
	entries = entries.filter(func(e: Dictionary) -> bool:
		return not (e.source == source and (source_id.is_empty() or e.source_id == source_id)))


## 过 dt 秒，返回到期移除的加成。
func tick(dt: float) -> Array:
	var expired: Array = []
	for e in entries:
		if e.left < 0.0: continue
		e.left -= dt
		if e.left <= 0.000001: expired.append(e)
	if not expired.is_empty(): entries = entries.filter(func(e: Dictionary) -> bool: return not e in expired)
	return expired


func _matches(e: Dictionary, kind: String, target: String, dish: String, part: String) -> bool:
	if e.kind != kind: return false
	if not e.target.is_empty() and e.target != target: return false
	if e.part != part: return false
	if not dish.is_empty() and not e.dishes.is_empty() and not dish in e.dishes: return false
	if dish.is_empty() and not e.dishes.is_empty(): return false
	return true


## kind 在 target 上的最终值。dish：只算作用在这道菜上的；part：只算乘这部分价格的（空 = 整道菜）。
## also_target：同时算作用在这个对象上的（员工：自己的 id + 所在区域）。
func value(kind: String, base: float, target := "", dish := "", part := "", also_target := "") -> float:
	var result := base
	var mul := 1.0
	var plus := 0.0
	for e in entries:
		var hit := _matches(e, kind, target, dish, part) or (not also_target.is_empty() and _matches(e, kind, also_target, dish, part))
		if not hit: continue
		match e.op:
			"set": result = e.value
			"add": plus += e.value
			_: mul *= e.value
	return result * mul + plus


## 带到期时间的加成（顶栏“进行中加成”图标用）。
func timed() -> Array:
	return entries.filter(func(e: Dictionary) -> bool: return e.left >= 0.0)
