extends Node2D
## Four empty tables; purchased chairs and seated customers are independent visual layers.
const Layout := preload("res://content/tea/art_playtest_layout.gd")
const Prop := preload("res://presentation/tea_playtest/fitted_prop.gd")
const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
var _chairs: Array[Sprite2D] = []
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

func refresh(seats: int, diners: Array, font: Font, clock: float) -> void:
	_available.clear()
	_occupied.clear()
	for i in mini(seats, Layout.DINING_SEATS.size()): _available.append(i)
	for diner in diners:
		var seat := int(diner.seat)
		if seat in _available: _occupied.append(seat)
	if not is_inside_tree(): return
	_build_furniture()
	for i in _chairs.size():
		# Furniture is present at opening; seat purchases still control actual diner capacity.
		_chairs[i].modulate = Color.WHITE
	for seat in _diners.keys():
		if not seat in _occupied:
			_diners[seat].free()
			_diners.erase(seat)
	for diner in diners:
		var seat := int(diner.seat)
		if not seat in _occupied: continue
		if not _diners.has(seat):
			var actor := Actor.new()
			actor.setup("squirrel" if seat % 2 else "hamster", font, 90)
			add_child(actor)
			_diners[seat] = actor
		_diners[seat].display({"pos": Layout.DINING_SEATS[seat] + Vector2(0, -12), "walking": false, "phase": "idle", "task_label": ""}, clock)
		_diners[seat].task.visible = false

func available_seats() -> Array[int]:
	return _available.duplicate()

func occupied_seats() -> Array[int]:
	return _occupied.duplicate()
