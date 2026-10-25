extends Node2D
## World adapter: only copied snapshots, readonly definitions and view-local animation.

signal station_selected(slot_id: String)
signal belt_selected(segment_id: String)
signal selection_cleared
signal staff_dropped(staff_id: String, zone: String)

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
const Station := preload("res://presentation/graybox/station_view.gd")
const Belt := preload("res://presentation/graybox/belt_view.gd")
const Actor := preload("res://presentation/graybox/actor_view.gd")
const Shelf := preload("res://presentation/graybox/shelf_view.gd")
## Share of a service step spent fetching from the window before handing over.
const FETCH_SHARE := 0.45
var _sim: GameSim
var _positions := {}
var _stations := {}
var _belts := {}
var _staff := {}
var _customers := {}
var _entities: Node2D
var _shelf: Node2D
var _kitchen_open := true
var _font: Font
const DRAG_THRESHOLD := 12.0
var _held := ""
var _held_at := Vector2.ZERO
var _dragged := ""
var _drag_zone := ""


func bind(sim: GameSim) -> void:
	unbind()
	for child in get_children():
		child.free()
	_stations.clear()
	_belts.clear()
	_staff.clear()
	_customers.clear()
	_dragged = ""
	_held = ""
	_sim = sim
	_font = load("res://art/ui/graybox_font.ttf")
	_positions = Layout.positions(sim.config)
	var lanes := Layout.shelf_lanes(sim.config, _positions)
	for connection in sim.config.connections:
		var belt := Belt.new()
		belt.points = Layout.route(connection, _positions, lanes.get(connection.id, 0))
		belt.length_cells = connection.length_cells
		add_child(belt)
		_belts[connection.id] = belt
	var items := BeltItems.new()
	items.belts = _belts.values()
	add_child(items)
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
	for item in sim.config.items:
		_shelf.item_names[item.id] = item.display_name
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


## Converts a world position into canvas coordinates for anchoring UI cards.
func to_screen(world_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas() * world_point


func station_anchor(slot_id: String) -> Rect2:
	var box: Rect2 = _stations[slot_id].bounds()
	return Rect2(to_screen(box.position), box.size)


func belt_anchor(segment_id: String) -> Vector2:
	var points: PackedVector2Array = _belts[segment_id].points
	return to_screen(Layout.along(points, 0.5))


func select(kind: String, id: String) -> void:
	for slot_id in _stations:
		_stations[slot_id].selected = kind == "station" and slot_id == id
		_stations[slot_id].queue_redraw()
	for segment_id in _belts:
		_belts[segment_id].selected = kind == "belt" and segment_id == id


func _on_snapshot(snapshot: Dictionary) -> void:
	_kitchen_open = bool(snapshot.kitchen_open)
	for slot in _sim.config.slots:
		_stations[slot.id].visible = _kitchen_open or slot.station.zone != _sim.config.kitchen_zone
	for connection in _sim.config.connections:
		var hidden := false
		for slot in _sim.config.slots:
			if slot.id in [connection.from_slot, connection.to_slot] and slot.station.zone == _sim.config.kitchen_zone:
				hidden = not _kitchen_open
		_belts[connection.id].visible = not hidden
	queue_redraw()
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
	var inactive := {}
	for row in snapshot.production.stations:
		if row.status != StationState.Status.ACTIVE:
			inactive[row.slot] = true
	for connection in _sim.config.connections:
		_belts[connection.id].ghost = inactive.has(connection.from_slot) or inactive.has(connection.to_slot)
	for data in snapshot.production.segments:
		if _belts.has(data.id):
			_belts[data.id].data = data
	_queue_buffers_on_belts(snapshot)
	_shelf.items = _menu_items(snapshot)
	_shelf.stock = snapshot.production.shelf
	_shelf.queue_redraw()
	var requests := {}
	for request in snapshot.production.requests + snapshot.front_hall.requests:
		requests[request.id] = request
	var places := {}
	for i in snapshot.front_hall.orders.size():
		places[int(snapshot.front_hall.orders[i].id)] = i
	_place_staff(snapshot, requests, places)
	_place_customers(snapshot)


## A machine's waiting inputs show at the end of its first incoming belt, its finished outputs at the start of its first outgoing one.
func _queue_buffers_on_belts(snapshot: Dictionary) -> void:
	var rows := {}
	for row in snapshot.production.stations:
		rows[row.slot] = row
	var has_input := {}
	var has_output := {}
	for connection in _sim.config.connections:
		var belt: Node2D = _belts[connection.id]
		belt.queued_end = {}
		belt.queued_start = {}
		if rows.has(connection.to_slot) and not has_input.has(connection.to_slot):
			belt.queued_end = rows[connection.to_slot].inputs
			has_input[connection.to_slot] = true
		if rows.has(connection.from_slot) and not has_output.has(connection.from_slot):
			belt.queued_start = rows[connection.from_slot].outputs
			has_output[connection.from_slot] = true


func _place_staff(snapshot: Dictionary, requests: Dictionary, places: Dictionary) -> void:
	var front_index := 0
	var kitchen_index := 0
	for data in snapshot.workforce.staff:
		if not _staff.has(data.staff):
			var created := Actor.new()
			created.setup(data.staff)
			created.position = _zone_home(data.zone, 0)
			created.target = created.position
			_entities.add_child(created)
			_staff[data.staff] = created
		var actor: Node2D = _staff[data.staff]
		var progress := float(data.work_done) / maxf(float(data.work_seconds), 0.001)
		actor.working = data.request != -1
		actor.work_progress = progress
		actor.idle = data.request == -1 and data.target == ""
		actor.carry_item = ""
		var zone: String = data.target if data.target != "" and data.request == -1 else data.zone
		var index := front_index if zone == "front" else kitchen_index
		if zone == "front":
			front_index += 1
		else:
			kitchen_index += 1
		if actor.dragging:
			continue
		var request: Dictionary = requests.get(int(data.request), {})
		var serving := not request.is_empty() and places.has(int(request.order))
		if not serving:
			actor.finish_service()
		if not request.is_empty() and _positions.has(request.slot):
			actor.target = Layout.work_spot(_positions[request.slot])
		elif serving:
			# Service: fetch from the pass-through window, then hand over at the customer's place.
			var duration := float(data.work_seconds) / _sim.workforce.efficiency(data.staff, data.zone)
			actor.display_service(int(data.request), progress, duration,
				Vector2(Layout.WINDOW.x - 30, Layout.STAFF_LINE - 34), Layout.serve_spot(places[int(request.order)]),
				_dish_item(snapshot.front_hall.orders[places[int(request.order)]].dish), FETCH_SHARE)
		elif not _zone_rect(zone).has_point(actor.target):
			actor.target = _zone_home(zone, index)
		elif zone == "front":
			actor.target = Layout.front_idle_spot(index)
		# An idle kitchen worker stays where the last job ended until another station needs them.
	_separate_idle_workers()


## Two workers never share a spot: an idle one steps aside for whoever is working there.
func _separate_idle_workers() -> void:
	for id in _staff:
		var actor: Node2D = _staff[id]
		if actor.working or actor.dragging:
			continue
		for attempt in 4:
			var crowded := false
			for other_id in _staff:
				if other_id != id and _staff[other_id].target.distance_to(actor.target) < 40.0:
					crowded = true
			if not crowded:
				break
			actor.target += Vector2(-52, 8)


func _place_customers(snapshot: Dictionary) -> void:
	var seen := {}
	for i in snapshot.front_hall.orders.size():
		var order: Dictionary = snapshot.front_hall.orders[i]
		seen[order.id] = true
		if not _customers.has(order.id):
			var created := Actor.new()
			created.setup(str(order.id), false)
			created.position = Layout.ENTRANCE
			_entities.add_child(created)
			_customers[order.id] = created
		var actor: Node2D = _customers[order.id]
		actor.target = Layout.customer_spot(i)
		actor.wait_ratio = float(order.wait) / maxf(_sim.config.customer_patience, 0.01)
		actor.order_item = _dish_item(order.dish)
	for id in _customers.keys():
		if not seen.has(id):
			_customers[id].leaving = true
			_customers[id].target = Layout.ENTRANCE + Vector2(-20, 0)
			_customers.erase(id)


## Finished goods of the dishes on the menu so far, in unlock order.
func _menu_items(snapshot: Dictionary) -> Array:
	var out := []
	var stages := _sim.config.progression.stages
	for i in mini(int(snapshot.progress.stage) + 1, stages.size()):
		var item := _dish_item(stages[i].dish_id)
		if not item in out:
			out.append(item)
	return out


func _dish_item(dish_id: String) -> String:
	for dish in _sim.config.dishes:
		if dish.id == dish_id:
			return dish.item_id
	return ""


func _zone_home(zone: String, index: int) -> Vector2:
	if zone == "front":
		return Layout.front_idle_spot(index)
	return Layout.KITCHEN_HOME + Vector2(index * 70, 0)


func _zone_rect(zone: String) -> Rect2:
	return Layout.FRONT if zone == "front" else Layout.KITCHEN


func _zone_at(point: Vector2) -> String:
	if _kitchen_open and Layout.KITCHEN.has_point(point):
		return "kitchen"
	if Layout.FRONT.has_point(point):
		return "front"
	return ""


func _on_sale(_sale_id: int, amount: int) -> void:
	if not is_inside_tree():
		return
	var label := Label.new()
	label.text = "+%d" % amount
	label.position = Layout.COUNTER + Vector2(170, -110)
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color("a68b43"))
	label.z_index = 20
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)


## A press on a worker becomes a drag only after the finger moves; a still tap selects what is underneath.
## An active press owns motion and release before GUI controls can swallow them.
func _input(event: InputEvent) -> void:
	if _held == "":
		return
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position if event is InputEventMouse else Vector2.ZERO
	if event is InputEventMouseMotion:
		if _dragged == "" and point.distance_to(_held_at) > DRAG_THRESHOLD:
			_dragged = _held
			_staff[_dragged].cancel_service_motion()
			_staff[_dragged].dragging = true
			_staff[_dragged].z_index = 10
			selection_cleared.emit()
		if _dragged != "":
			_staff[_dragged].position = point + Vector2(0, 40)
			_drag_zone = _zone_at(point)
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_held = ""
		if _dragged != "":
			_drop()
		else:
			_select_at(_held_at)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_press(get_global_transform_with_canvas().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()


func _press(point: Vector2) -> void:
	for id in _staff:
		if _staff[id].hit(point):
			_held = id
			_held_at = point
			return
	_select_at(point)


func _select_at(point: Vector2) -> void:
	var nodes: Array = _stations.keys()
	nodes.sort_custom(func(a: String, b: String) -> bool: return _stations[a].position.y > _stations[b].position.y)
	for id in nodes:
		if _stations[id].visible and _stations[id].hit(point):
			station_selected.emit(id)
			return
	for id in _belts:
		if _belts[id].visible and _belts[id].hit(point):
			belt_selected.emit(id)
			return
	selection_cleared.emit()


func _drop() -> void:
	var actor: Node2D = _staff[_dragged]
	actor.dragging = false
	actor.z_index = 0
	if _drag_zone != "":
		# Land where the finger let go; the snapshot moves the worker on from there.
		actor.target = actor.position
		staff_dropped.emit(_dragged, _drag_zone)
	_dragged = ""
	_drag_zone = ""
	queue_redraw()
	if is_instance_valid(_sim):
		_on_snapshot(_sim.last_snapshot)


func _draw() -> void:
	if _font == null:
		return
	draw_style_box(_panel(Color("b8c8c0"), 20), Rect2(32, 104, 656, 1094))
	draw_texture_rect(Assets.texture("res://art/env/env_kitchen_floor.png"), Layout.KITCHEN, true)
	draw_texture_rect(Assets.texture("res://art/env/env_front_floor.png"), Layout.FRONT, true)
	draw_texture_rect(Assets.texture("res://art/env/env_divider.png"), Rect2(36, Layout.KITCHEN.end.y - 4, 648, 32), true)
	draw_texture_rect(Assets.texture("res://art/env/env_window.png"), Rect2(Layout.WINDOW.x - 52, Layout.WINDOW.y - 46, 104, 56), false)
	draw_string(_font, Vector2(56, 146), "后厨" if _kitchen_open else "前厅备饮 · 柠檬水", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("77908e"))
	draw_string(_font, Vector2(56, 842), "前厅", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("a48d71"))
	draw_string(_font, Vector2(56, 1180), "入口", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a48d71"))
	if not _kitchen_open:
		draw_style_box(_panel(Color("d6dfd5"), 16), Rect2(56, 354, 608, 360))
		draw_string(_font, Vector2(190, 510), "解锁珍珠奶茶后开放后厨", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("6a8175"))
		draw_string(_font, Vector2(180, 550), "先经营柠檬水，在前厅购买新菜", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("6a8175"))
	if _dragged != "":
		for zone in ["kitchen", "front"]:
			if zone == "kitchen" and not _kitchen_open:
				continue
			var rect := _zone_rect(zone)
			var hot: bool = zone == _drag_zone
			draw_rect(rect, Color(0.95, 0.8, 0.4, 0.22 if hot else 0.06))
			draw_rect(rect.grow(-3), Color("e6bb60") if hot else Color(1, 1, 1, 0.5), false, 4.0 if hot else 2.0)
			var label := ("调到后厨" if zone == "kitchen" else "调到前厅")
			draw_string(_font, rect.get_center() + Vector2(-48, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.4, 0.33, 0.2, 0.75 if hot else 0.3))


func _panel(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


class BeltItems extends Node2D:
	var belts: Array = []

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		for belt in belts:
			if belt.visible:
				belt.draw_items(self)
