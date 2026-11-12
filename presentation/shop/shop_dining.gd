extends Node2D
## 堂食区（通用）：桌椅、坐着的客人、桌上的杯子。位置全读场景锚点 Tables/<组>、Seats/<组>、Lanes、Aisle、Entrance。
## 买到的座位才摆出椅子；每张桌子 per_table 个座位（锚点 Tables/<组> 的 meta）。

const Prop := preload("res://presentation/shop/fitted_prop.gd")
const Actor := preload("res://presentation/shop/shop_actor.gd")
const Presentation := preload("res://content/characters/actor_presentation.tres")
## 杯子立在桌面上：离客人那一侧多远、抬多高
const CUP_SIDE := 34.0
const CUP_LIFT := 92.0
const TABLE_CUP_HEIGHT := 36.0

var group := ""
var anchors: ShopAnchors
var art_of: Callable = func(_item: String) -> Dictionary: return {}
var customer_height := 110.0
var _actor_unit_scale := 1.0
var _chairs: Array[Sprite2D] = []
var _tables: Array[Sprite2D] = []
var _cups := {}
var _diners := {}
var _available: Array[int] = []
var _occupied: Array[int] = []
## 走路中的客人：{actor, path, step, item, seat}；走到座位的坐下
var _walkers: Array = []
var _arrivals := {}
var _exits: Array = []


func setup(anchors_: ShopAnchors, group_: String, item_art: Callable, height: float, unit_scale := 1.0) -> void:
	anchors = anchors_
	group = group_
	art_of = item_art
	customer_height = height
	_actor_unit_scale = unit_scale
	y_sort_enabled = true
	_build_furniture()


## A new run discards guests and pending movement while retaining the art and furniture.
func reset() -> void:
	var dynamic_nodes := {}
	for node in _diners.values() + _cups.values():
		if is_instance_valid(node): dynamic_nodes[node.get_instance_id()] = node
	for walker in _walkers:
		if is_instance_valid(walker.actor): dynamic_nodes[walker.actor.get_instance_id()] = walker.actor
	_diners.clear()
	_cups.clear()
	_walkers.clear()
	_arrivals.clear()
	_exits.clear()
	_available.clear()
	_occupied.clear()
	for node in dynamic_nodes.values(): node.free()


func seats() -> Array[Vector2]:
	return anchors.points("Seats/" + group)


func tables() -> Array[Vector2]:
	return anchors.points("Tables/" + group)


func per_table() -> int:
	return int(anchors.meta("Tables/" + group, "per_table", 2))


func _build_furniture() -> void:
	if not _chairs.is_empty() or anchors == null: return
	var table_points := tables()
	for i in table_points.size():
		var path := "Tables/%s/%d" % [group, i]
		var table := _prop(String(anchors.meta(path, "art", "dining_table")), float(anchors.meta(path, "width", 180.0)), table_points[i])
		table.name = "Table%d" % (i + 1)
		_tables.append(table)
	var seat_points := seats()
	for i in seat_points.size():
		var path := "Seats/%s/%d" % [group, i]
		var chair := _prop(String(anchors.meta(path, "art", "dining_chair_left")), float(anchors.meta(path, "width", 70.0)), seat_points[i])
		chair.name = "Chair%d" % (i + 1)
		_chairs.append(chair)


func _prop(id: String, width: float, point: Vector2) -> Sprite2D:
	var sprite := Prop.new()
	sprite.asset_path = "res://art/reference/%s.png" % id
	sprite.display_width = width
	sprite.position = point
	sprite.set_meta("asset_id", id)
	sprite.set_meta("art_layer", "dining")
	add_child(sprite)
	return sprite


## 坐下的位置（椅面，比椅子的落地点高一点）
func seat_point(seat: int) -> Vector2:
	return seats()[seat] + Vector2(anchors.meta("Seats/" + group, "sit_offset", Vector2(0, -12) * _actor_unit_scale))


func _facing(seat: int) -> int:
	return int(anchors.meta("Seats/%s/%d" % [group, seat], "facing", 2))


## 座位前那一排走道：落在座位上方最近的一条
func _lane(seat: int) -> int:
	var lanes := anchors.points("Lanes")
	var best := 0
	for i in lanes.size():
		if lanes[i].y < seats()[seat].y: best = i
	return best


func seat_path(from: Vector2, seat: int) -> PackedVector2Array:
	var lanes := anchors.points("Lanes")
	var aisle := anchors.point("Aisle")
	var lane := _lane(seat)
	var target := seat_point(seat)
	var route := PackedVector2Array([Vector2(from.x, lanes[0].y)])
	if lane > 0:
		route.append(Vector2(aisle.x, lanes[0].y))
		route.append(Vector2(aisle.x, lanes[lane].y))
	route.append(Vector2(target.x, lanes[lane].y))
	route.append(target)
	return route


func exit_path(from: Vector2, seat := -1) -> PackedVector2Array:
	var lanes := anchors.points("Lanes")
	var y: float = lanes[_lane(seat) if seat >= 0 else 0].y
	return PackedVector2Array([Vector2(from.x, y), Vector2(anchors.point("Aisle").x, y), anchors.point("Entrance")])


func queue_arrival(seat: int, from: Vector2, art: String) -> void:
	_arrivals[seat] = {"from": from, "art": art}


func queue_exit(from: Vector2, art: String, item: String) -> void:
	_exits.append({"from": from, "art": art, "item": item})


func refresh(seat_count: int, diners: Array, font: Font, clock: float, delta := 0.0) -> void:
	_available.clear()
	_occupied.clear()
	if anchors == null: return
	for i in mini(seat_count, seats().size()): _available.append(i)
	var items := {}
	for diner in diners:
		var seat := int(diner.seat)
		if seat in _available:
			_occupied.append(seat)
			items[seat] = String(diner.dish)
	if not is_inside_tree(): return
	_build_furniture()
	for i in _chairs.size(): _chairs[i].visible = i in _available
	for i in _tables.size(): _tables[i].visible = i * per_table() in _available
	for seat in _diners.keys():
		if not seat in _occupied:
			_walk(_diners[seat], exit_path(_diners[seat].position, seat), "", -1)
			_diners.erase(seat)
	for exit in _exits:
		_walk(_actor(exit.art, font), exit_path(exit.from), exit.item, -1, exit.from)
	_exits.clear()
	for seat in _occupied:
		if _diners.has(seat) or _walking_to(seat): continue
		if _arrivals.has(seat):
			_walk(_actor(_arrivals[seat].art, font), seat_path(_arrivals[seat].from, seat), items[seat], seat, _arrivals[seat].from)
		else:
			# 读档（或没看到排队就坐上的）直接坐着
			_diners[seat] = _actor(Actor.Characters.customer_art(seat + 1), font)
	_arrivals.clear()
	_advance(delta, clock)
	for seat in _cups.keys():
		if not _diners.has(seat):
			_cups[seat].queue_free()
			_cups.erase(seat)
	for seat in _diners:
		_table_cup(seat, items.get(seat, ""))
		_diners[seat].display({"pos": seat_point(seat), "walking": false, "seated": true,
			"facing": _facing(seat), "phase": "idle", "task_label": ""}, clock)
		_diners[seat].task.visible = false
		_diners[seat].z_index = 1
		_diners[seat].position.y -= 14 * _actor_unit_scale
		if _diners[seat].frame_actor == null: _diners[seat].face(seat % 2 == 0)


func _table_cup(seat: int, item: String) -> void:
	if item.is_empty(): return
	if _cups.has(seat): return
	var art: Dictionary = art_of.call(item)
	var sprite := Sprite2D.new()
	sprite.texture = Actor.ItemArt.texture_from_look(art)
	sprite.self_modulate = art.get("tint", Color.WHITE)
	sprite.scale = Vector2.ONE * TABLE_CUP_HEIGHT * _actor_unit_scale / sprite.texture.get_height()
	sprite.centered = false
	var table: Vector2 = tables()[seat / per_table()]
	sprite.position = table + Vector2(-CUP_SIDE if seat % 2 == 0 else CUP_SIDE, 2.0) * _actor_unit_scale
	sprite.offset = Vector2(-sprite.texture.get_width() / 2.0, -sprite.texture.get_height() - (CUP_LIFT + 2.0) * _actor_unit_scale / sprite.scale.y)
	sprite.z_index = 1
	sprite.set_meta("art_layer", "drinks")
	sprite.set_meta("item_id",item)
	add_child(sprite)
	_cups[seat] = sprite


func _actor(art: String, font: Font) -> Node2D:
	var actor := Actor.new()
	actor.item_art = art_of
	actor.setup(art, font, customer_height)
	actor.scale = Vector2.ONE * _actor_unit_scale
	add_child(actor)
	return actor


func _walk(actor: Node2D, path: PackedVector2Array, item: String, seat: int, start := Vector2.INF) -> void:
	if start != Vector2.INF: actor.position = start
	_walkers.append({"actor": actor, "path": path, "step": 0, "item": item, "seat": seat})


func _walking_to(seat: int) -> bool:
	for walker in _walkers:
		if walker.seat == seat: return true
	return false


func _advance(delta: float, clock: float) -> void:
	for index in range(_walkers.size() - 1, -1, -1):
		var walker: Dictionary = _walkers[index]
		var actor: Node2D = walker.actor
		var point: Vector2 = actor.position
		var budget := delta * Presentation.customer_speed * _actor_unit_scale
		while budget > 0.0 and walker.step < walker.path.size():
			var target: Vector2 = walker.path[walker.step]
			var gap := point.distance_to(target)
			if gap <= budget:
				point = target
				budget -= gap
				walker.step += 1
			else:
				point = point.move_toward(target, budget)
				budget = 0.0
		var done: bool = walker.step >= walker.path.size()
		actor.display({"pos": point, "walking": not done, "phase": "idle", "task_label": "",
			"carry_item": walker.item, "carry_count": 1 if not String(walker.item).is_empty() else 0}, clock)
		actor.task.visible = false
		if not done: continue
		_walkers.remove_at(index)
		if walker.seat >= 0 and walker.seat in _occupied and not _diners.has(walker.seat):
			_diners[walker.seat] = actor
		else:
			actor.queue_free()


func walking_count() -> int:
	return _walkers.size()


## In the shared protocol every customer belongs to ShopRules/ShopPlay.
## Dining renders only authored furniture and table items, never a second actor.
func refresh_authoritative(seat_count: int, customers: Array) -> void:
	_available.clear()
	_occupied.clear()
	if anchors==null: return
	_build_furniture()
	for index in mini(seat_count,seats().size()): _available.append(index)
	for i in _chairs.size(): _chairs[i].visible = i in _available
	for i in _tables.size(): _tables[i].visible = i*per_table() in _available
	var served_seats: Array[int] = []
	for row: Dictionary in customers:
		var seat := int(row.seat)
		if row.seated and row.target.begins_with("seat:"+group+"/") and seat in _available:
			_occupied.append(seat)
			if row.state in ["diner","eating"]:
				served_seats.append(seat)
				if _cups.has(seat) and _cups[seat].get_meta("item_id","")!=String(row.dish):
					_cups[seat].free()
					_cups.erase(seat)
				_table_cup(seat,String(row.dish))
	for seat in _cups.keys():
		if not seat in served_seats:
			_cups[seat].free()
			_cups.erase(seat)


func available_seats() -> Array[int]:
	return _available.duplicate()


func occupied_seats() -> Array[int]:
	return _occupied.duplicate()
