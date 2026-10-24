extends Node2D
## World adapter: only copied snapshots, readonly definitions and view-local animation.

signal station_selected(slot_id: String)

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
const Station := preload("res://presentation/graybox/station_view.gd")
const Belt := preload("res://presentation/graybox/belt_view.gd")
const Actor := preload("res://presentation/graybox/actor_view.gd")
const Shelf := preload("res://presentation/graybox/shelf_view.gd")
var _sim: GameSim
var _positions := {}
var _stations := {}
var _belts := {}
var _staff := {}
var _customers := {}
var _entities: Node2D
var _shelf: Node2D
var _font: Font


func bind(sim: GameSim) -> void:
	unbind()
	for child in get_children():
		child.free()
	_stations.clear()
	_belts.clear()
	_staff.clear()
	_customers.clear()
	_sim = sim
	_font = load("res://art/ui/graybox_font.ttf")
	_positions = Layout.positions(sim.config)
	for connection in sim.config.connections:
		var belt := Belt.new()
		belt.points = Layout.route(connection, _positions)
		belt.length_cells = connection.length_cells
		add_child(belt)
		_belts[connection.id] = belt
	_entities = Node2D.new()
	_entities.y_sort_enabled = true
	add_child(_entities)
	for slot in sim.config.slots:
		var station := Station.new()
		station.setup(slot.station)
		station.position = _positions[slot.id]
		_entities.add_child(station)
		_stations[slot.id] = station
	_shelf = Shelf.new()
	_shelf.position = Layout.SHELF
	_shelf.capacity = sim.config.shelf_capacity
	_entities.add_child(_shelf)
	sim.tick_finished.connect(_on_snapshot)
	sim.sale_settled.connect(_on_sale)
	_on_snapshot(sim.last_snapshot)
	_center()
	queue_redraw()


func unbind() -> void:
	if is_instance_valid(_sim):
		if _sim.tick_finished.is_connected(_on_snapshot):
			_sim.tick_finished.disconnect(_on_snapshot)
		if _sim.sale_settled.is_connected(_on_sale):
			_sim.sale_settled.disconnect(_on_sale)
	_sim = null


func _exit_tree() -> void:
	unbind()


func _process(_delta: float) -> void:
	_center()


func _center() -> void:
	if is_inside_tree():
		position.x = (get_viewport_rect().size.x - 720) / 2.0


func _on_snapshot(snapshot: Dictionary) -> void:
	var claimed := {}
	for staff in snapshot.workforce.staff:
		if staff.request != -1:
			claimed[staff.request] = float(staff.work_done) / maxf(float(staff.work_seconds), 0.001)
	for data in snapshot.production.stations + snapshot.front_hall.counters:
		if _stations.has(data.slot):
			var visual: Dictionary = data.duplicate()
			visual.staff_working = claimed.has(data.request)
			visual.manual_progress = claimed.get(data.request, 0.0)
			_stations[data.slot].display(visual)
	for data in snapshot.production.segments:
		if _belts.has(data.id):
			_belts[data.id].data = data
	_shelf.stock = snapshot.production.shelf
	_shelf.queue_redraw()
	var requests := {}
	for request in snapshot.production.requests + snapshot.front_hall.requests:
		requests[request.id] = request
	for data in snapshot.workforce.staff:
		var zone: String = data.target if data.target != "" and data.request == -1 else data.zone
		var destination := Vector2(230, 635) if zone == "kitchen" else Vector2(470, 860)
		if data.request != -1 and requests.has(data.request):
			var request: Dictionary = requests[data.request]
			if _positions.has(request.slot):
				destination = _positions[request.slot] + Vector2(-72, 20)
		if not _staff.has(data.staff):
			var actor := Actor.new()
			actor.setup(data.staff)
			actor.position = destination
			_entities.add_child(actor)
			_staff[data.staff] = actor
		var actor: Node2D = _staff[data.staff]
		actor.target = destination
		actor.working = data.request != -1
		actor.work_progress = float(data.work_done) / maxf(float(data.work_seconds), 0.001)
		actor.idle = data.request == -1 and data.target == ""
	var seen := {}
	for i in snapshot.front_hall.orders.size():
		var order: Dictionary = snapshot.front_hall.orders[i]
		seen[order.id] = true
		var destination := Vector2(378 - i * 53, 1042)
		if not _customers.has(order.id):
			var actor := Actor.new()
			actor.setup(str(order.id), false)
			actor.position = Vector2(55, 1080)
			_entities.add_child(actor)
			_customers[order.id] = actor
		var actor: Node2D = _customers[order.id]
		actor.target = destination
		actor.wait_ratio = float(order.wait) / maxf(_sim.config.customer_patience, 0.01)
		for dish in _sim.config.dishes:
			if dish.id == order.dish:
				actor.order_item = dish.item_id
	for id in _customers.keys():
		if not seen.has(id):
			_customers[id].leaving = true
			_customers[id].target = Vector2(15, 1090)
			_customers.erase(id)


func _on_sale(_sale_id: int, amount: int) -> void:
	if not is_inside_tree():
		return
	var label := Label.new()
	label.text = "+%d" % amount
	label.position = Vector2(604, 895)
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color("a68b43"))
	label.z_index = 20
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", 855.0, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var nodes: Array = _stations.values()
		nodes.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.y > b.position.y)
		for node in nodes:
			if node.hit(point):
				for id in _stations:
					_stations[id].selected = _stations[id] == node
					_stations[id].queue_redraw()
					if _stations[id] == node:
						station_selected.emit(id)
				get_viewport().set_input_as_handled()
				return


func _draw() -> void:
	if _font == null:
		return
	draw_style_box(_panel(Color("b8c8c0"), 20), Rect2(32, 207, 656, 900))
	draw_texture_rect(Assets.texture("res://art/env/env_kitchen_floor.png"), Rect2(40, 214, 640, 568), true)
	draw_texture_rect(Assets.texture("res://art/env/env_front_floor.png"), Rect2(40, 816, 640, 280), true)
	draw_texture_rect(Assets.texture("res://art/env/env_divider.png"), Rect2(36, 187, 648, 32), true)
	draw_texture_rect(Assets.texture("res://art/env/env_divider.png"), Rect2(36, 783, 648, 32), true)
	draw_texture_rect(Assets.texture("res://art/env/env_window.png"), Rect2(422, 761, 128, 70), false)
	draw_string(_font, Vector2(62, 253), "后厨", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("77908e"))
	draw_string(_font, Vector2(64, 865), "前厅", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("a48d71"))
	draw_string(_font, Vector2(80, 1100), "入口", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("a48d71"))


func _panel(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
