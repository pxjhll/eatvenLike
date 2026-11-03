extends Node2D
## Four empty tables; purchased chairs and seated customers are independent visual layers.
const Layout := preload("res://content/tea/art_playtest_layout.gd")
const Prop := preload("res://presentation/tea_playtest/fitted_prop.gd")
const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
var _chairs: Array[Sprite2D] = []
var _tables: Array[Sprite2D] = []
var _diners := {}
var _available: Array[int] = []
var _occupied: Array[int] = []

func _ready() -> void:
	y_sort_enabled = true
	_build_furniture()

func _build_furniture() -> void:
	if not _chairs.is_empty(): return
	for i in Layout.DINING_TABLES.size():
		var table := _prop("dining_table", 180, Layout.DINING_TABLES[i])
		table.name = "Table%d" % (i + 1)
		_tables.append(table)
	for i in Layout.DINING_SEATS.size():
		var chair := _prop("dining_chair_left" if i % 2 == 0 else "dining_chair_right", 70, Layout.DINING_SEATS[i])
		chair.name = "Chair%d" % (i + 1)
		_chairs.append(chair)

func _prop(id: String, width: float, point: Vector2) -> Sprite2D:
	var sprite := Prop.new()
	sprite.asset_path = "res://art/reference/%s.png" % id
	sprite.display_width = width
	sprite.position = point
	sprite.set_meta("asset_id", id)
	sprite.set_meta("art_layer", "dining")
	sprite.set_meta("layout_group", "基础物品")
	sprite.set_meta("unlock_rule", "always")
	add_child(sprite)
	return sprite

const WALK_SPEED := 170.0
const EMPTY_CHAIR := Color(1, 1, 1, 0.35)
## Customers on their way: {actor, path, step, item, seat}. A seat walker sits down at the end of its path.
var _walkers: Array = []
## Served dine-in customers handed over by the queue this frame: seat -> {from, art}.
var _arrivals := {}
var _exits: Array = []

## A dine-in customer just served at the counter walks from there to their chair.
func queue_arrival(seat: int, from: Vector2, art: String) -> void:
	_arrivals[seat] = {"from": from, "art": art}

## A takeaway customer (or one with no seat) walks out through the door with their cup.
func queue_exit(from: Vector2, art: String, item: String) -> void:
	_exits.append({"from": from, "art": art, "item": item})

func refresh(seats: int, diners: Array, font: Font, clock: float, delta := 0.0) -> void:
	_available.clear()
	_occupied.clear()
	for i in mini(seats, Layout.DINING_SEATS.size()): _available.append(i)
	var items := {}
	for diner in diners:
		var seat := int(diner.seat)
		if seat in _available:
			_occupied.append(seat)
			items[seat] = String(diner.dish)
	if not is_inside_tree(): return
	_build_furniture()
	for i in _chairs.size():
		# All chairs are drawn; the ones not bought yet are faint.
		_chairs[i].modulate = Color.WHITE if i in _available else EMPTY_CHAIR
	for i in _tables.size():
		_tables[i].modulate = Color.WHITE if i * 2 in _available else EMPTY_CHAIR
	for seat in _diners.keys():
		if not seat in _occupied:
			# Time's up: the customer stands up and leaves through the aisle.
			_walk(_diners[seat], Layout.exit_path(_diners[seat].position, seat), "", -1)
			_diners.erase(seat)
	for exit in _exits:
		_walk(_actor(exit.art, font), Layout.exit_path(exit.from), exit.item, -1, exit.from)
	_exits.clear()
	for seat in _occupied:
		if _diners.has(seat) or _walking_to(seat): continue
		if _arrivals.has(seat):
			_walk(_actor(_arrivals[seat].art, font), Layout.seat_path(_arrivals[seat].from, seat), items[seat], seat, _arrivals[seat].from)
		else:
			# A loaded save (or a seat filled without a visible queue) starts seated.
			_diners[seat] = _actor("squirrel" if seat % 2 else "hamster", font)
	_arrivals.clear()
	_advance(delta, clock)
	for seat in _diners:
		_diners[seat].display({"pos": Layout.seat_point(seat), "walking": false, "phase": "idle", "task_label": "",
			"carry_item": items.get(seat, ""), "carry_count": 1}, clock)
		_diners[seat].task.visible = false
		# Sitting on the chair: drawn over it, slightly raised onto the seat.
		_diners[seat].z_index = 1
		_diners[seat].position.y -= 14

func _actor(art: String, font: Font) -> Node2D:
	var actor := Actor.new()
	actor.setup(art, font, 80)
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
		var budget := delta * WALK_SPEED
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

func available_seats() -> Array[int]:
	return _available.duplicate()

func occupied_seats() -> Array[int]:
	return _occupied.duplicate()
