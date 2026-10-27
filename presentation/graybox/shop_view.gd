extends Node2D
## World adapter: only copied snapshots, readonly definitions and view-local animation.

signal station_selected(slot_id: String)
signal selection_cleared
## target：前厅位点 id、后厨设备 id，或空（拖回员工栏 = 下岗）
signal staff_dropped(staff_id: String, target: String)
## 布局模式里把一台设备拖到新位置（cell = 左上角那一格）；拖回设备栏 = 拿回（cell 无意义，to_bar = true）
signal device_dropped(device_id: String, cell: Vector2i, to_bar: bool)

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
const Station := preload("res://presentation/graybox/station_view.gd")
const Device := preload("res://presentation/graybox/device_view.gd")
const Belt := preload("res://presentation/graybox/belt_view.gd")
const Actor := preload("res://presentation/graybox/actor_view.gd")
const Shelf := preload("res://presentation/graybox/shelf_view.gd")
## Share of a service step spent fetching from the window before handing over.
const FETCH_SHARE := 0.45
var _sim: GameSim
var _positions := {}
var _stations := {}
## 后厨设备（生效的或草稿里的）：id -> DeviceView
var _devices := {}
var _belts := {}
var _belt_layer: Node2D
## 上次建后厨用的布局签名，变了才重建
var _layout_key := ""
var _layout_mode := false
## 布局模式里正在拖的设备 / 设备栏里拖出来的预览：{"def": StationDef, "cell": Vector2i, "ok": bool}
var _preview := {}
var _moving := ""
var _moving_offset := Vector2.ZERO
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
var _drag_target := ""
## 松手时手指落在底部员工栏上（= 下岗）
var _dropped_on_bar := false


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
	_devices.clear()
	_layout_key = ""
	_moving = ""
	_preview = {}
	_belt_layer = Node2D.new()
	add_child(_belt_layer)
	var items := BeltItems.new()
	items.view = self
	add_child(items)
	_entities = Node2D.new()
	_entities.y_sort_enabled = true
	add_child(_entities)
	for spot in sim.config.front_spots:
		var station := Station.new()
		station.setup(spot.station)
		station.unlock_price = spot.unlock_cost
		station.position = _positions[spot.id]
		_entities.add_child(station)
		_stations[spot.id] = station
	_shelf = Shelf.new()
	_shelf.position = _positions.shelf
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
	var node: Node2D = _stations.get(slot_id, _devices.get(slot_id))
	if node == null:
		return Rect2()
	var box: Rect2 = node.bounds()
	return Rect2(to_screen(box.position), box.size)


func select(kind: String, id: String) -> void:
	for slot_id in _stations:
		_stations[slot_id].selected = kind == "station" and slot_id == id
		_stations[slot_id].queue_redraw()
	for device_id in _devices:
		_devices[device_id].selected = kind == "station" and device_id == id
		_devices[device_id].queue_redraw()


## 设备栏拖出来的设备跟着手指：point 是世界坐标，返回会放到哪一格（左上角）
func preview_device(def: StationDef, point: Vector2) -> Vector2i:
	var cell := _top_left(def, point)
	_preview = {"def": def, "cell": cell, "ok": _sim.layout.validate_place(def.id, cell) == ""}
	queue_redraw()
	return cell


func clear_preview() -> void:
	_preview = {}
	queue_redraw()


## 手指拿着设备中心时，设备左上角落在哪一格
func _top_left(def: StationDef, point: Vector2) -> Vector2i:
	return Layout.cell_at(point - (Vector2(def.footprint) - Vector2.ONE) * Layout.CELL / 2.0)


func _on_snapshot(snapshot: Dictionary) -> void:
	_kitchen_open = bool(snapshot.kitchen_open)
	_layout_mode = int(snapshot.mode) == GameSim.Mode.LAYOUT
	_sync_kitchen(snapshot)
	for spot in _sim.config.front_spots:
		_stations[spot.id].visible = int(snapshot.progress.stage) >= spot.stage
	queue_redraw()
	var claimed := {}
	for staff in snapshot.workforce.staff:
		if staff.request != -1:
			claimed[staff.request] = float(staff.work_done) / maxf(float(staff.work_seconds), 0.001)
	for data in snapshot.production.stations + snapshot.front_hall.counters:
		var node: Node2D = _stations.get(data.slot, _devices.get(data.slot))
		if node != null and not (_layout_mode and node is Device):
			var visual: Dictionary = data.duplicate()
			visual.staff_working = claimed.has(data.request)
			visual.manual_progress = claimed.get(data.request, 0.0)
			node.display(visual)
	if not _layout_mode:
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


## 后厨按快照里的布局重建：经营模式画生效的设备和带子，布局模式画草稿
func _sync_kitchen(snapshot: Dictionary) -> void:
	var source: Dictionary = snapshot.layout.get("draft", snapshot.layout) if _layout_mode else snapshot.layout
	var key := JSON.stringify([_layout_mode, source.devices, source.belts, source.get("problem", "")])
	if key == _layout_key:
		return
	_layout_key = key
	for id in _devices:
		_devices[id].queue_free()
	_devices.clear()
	for id in _belts:
		_belts[id].queue_free()
	_belts.clear()
	var by_id := {}
	for d in source.devices:
		by_id[d.id] = d
		var device := Device.new()
		device.setup(_sim.config.device_def(d.def), d.id, Vector2i(d.cell[0], d.cell[1]))
		device.draft = _layout_mode
		device.is_new = bool(d.get("new", false))
		_entities.add_child(device)
		_devices[d.id] = device
	for b in source.belts:
		var belt := Belt.new()
		belt.points = Layout.belt_points(_sim.config, by_id, b)
		belt.length_cells = float(b.path.size())
		belt.ghost = _layout_mode
		_belt_layer.add_child(belt)
		_belts[b.id] = belt


## 设备里等着的原料画在进来的带子末端，做好的成品画在出去的第一条带子开头
func _queue_buffers_on_belts(snapshot: Dictionary) -> void:
	var rows := {}
	for row in snapshot.production.stations:
		rows[row.slot] = row
	var has_input := {}
	var has_output := {}
	for data in snapshot.production.segments:
		if not _belts.has(data.id):
			continue
		var belt: Node2D = _belts[data.id]
		belt.queued_end = {}
		belt.queued_start = {}
		if rows.has(data.to) and not has_input.has(data.to + data.item):
			belt.queued_end = {data.item: rows[data.to].inputs.get(data.item, 0)}
			has_input[data.to + data.item] = true
		if rows.has(data.from) and not has_output.has(data.from + data.item):
			belt.queued_start = {data.item: rows[data.from].outputs.get(data.item, 0)}
			has_output[data.from + data.item] = true


func _place_staff(snapshot: Dictionary, requests: Dictionary, places: Dictionary) -> void:
	for data in snapshot.workforce.staff:
		if not _staff.has(data.staff):
			var created := Actor.new()
			created.setup(data.staff)
			created.position = Layout.ENTRANCE
			created.target = created.position
			_entities.add_child(created)
			_staff[data.staff] = created
		var actor: Node2D = _staff[data.staff]
		var progress := float(data.work_done) / maxf(float(data.work_seconds), 0.001)
		actor.working = data.request != -1
		actor.work_progress = progress
		actor.idle = data.request == -1
		actor.carry_item = ""
		# 没上岗的人在底部员工栏里，不在店里画
		actor.visible = String(data.post) != ""
		if actor.dragging:
			continue
		var request: Dictionary = requests.get(int(data.request), {})
		var serving := not request.is_empty() and places.has(int(request.order))
		if not serving:
			actor.finish_service()
		if _devices.has(String(data.post)):
			var device: Node2D = _devices[data.post]
			actor.target = Layout.device_post(device.definition, device.cell)
		elif serving:
			# Service: fetch where the drink comes from (the stand it is poured at, or the
			# pass-through window), then hand over at the customer's place.
			var duration := float(data.work_seconds) / _sim.workforce.efficiency(data.staff, data.zone)
			var source := String(request.get("source", ""))
			var pickup := Vector2(_positions.shelf.x - 30, Layout.STAFF_LINE - 34)
			if source != "" and _positions.has(source):
				pickup = Layout.work_spot(_positions[source])
			actor.display_service(int(data.request), progress, duration,
				pickup, Layout.serve_spot(places[int(request.order)]),
				_dish_item(snapshot.front_hall.orders[places[int(request.order)]].dish), FETCH_SHARE)
		elif String(data.post) != "" and _positions.has(data.post):
			actor.target = Layout.post_spot(_positions[data.post], _post_index(snapshot, data))
	_separate_idle_workers()


## Rank of this worker among the ones standing on the same post, so two never stack.
func _post_index(snapshot: Dictionary, data: Dictionary) -> int:
	var index := 0
	for other in snapshot.workforce.staff:
		if other.staff == data.staff:
			break
		if other.post == data.post:
			index += 1
	return index


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
	for i in mini(int(snapshot.front_hall.menu_stage) + 1, stages.size()):
		var item := _dish_item(stages[i].dish_id)
		if not item in out:
			out.append(item)
	return out


func _dish_item(dish_id: String) -> String:
	for dish in _sim.config.dishes:
		if dish.id == dish_id:
			return dish.item_id
	return ""


## 拖到哪里了：前厅位点或后厨要员工的设备；拖回底部员工栏是下岗（空字符串）
func _target_at(point: Vector2) -> String:
	var spot := spot_at(point)
	if spot != "":
		return spot
	_dropped_on_bar = point.y > Layout.FRONT.end.y
	return ""


## 手指下面能上岗的工位：解锁了的前厅位点，或者要员工的后厨设备（本体或工位格都算）
func spot_at(point: Vector2) -> String:
	if _sim == null:
		return ""
	for spot in _sim.config.front_spots:
		if spot.posts > 0 and _sim.front_hall.is_active(spot.id) and _stations[spot.id].hit(point):
			return spot.id
	if _layout_mode:
		return ""
	for id in _devices:
		var device: Node2D = _devices[id]
		if not device.definition.needs_staff():
			continue
		var work := Layout.cell_rect(device.cell + device.definition.work_cell)
		if device.hit(point) or work.has_point(point):
			return id
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
	if _moving != "":
		_drag_device(event)
		return
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
			_drag_target = _target_at(point)
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
	if _layout_mode:
		for id in _devices:
			if _devices[id].hit(point):
				_moving = id
				_moving_offset = _devices[id].bounds().get_center() - point
				selection_cleared.emit()
				return
		selection_cleared.emit()
		return
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
	for id in _devices:
		if _devices[id].hit(point):
			station_selected.emit(id)
			return
	selection_cleared.emit()


## 布局模式里拖设备：跟着手指出预览，松手落在后厨就挪过去，落在底部设备栏就拿回
func _drag_device(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	var device: Node2D = _devices.get(_moving)
	if device == null:
		_moving = ""
		return
	var def: StationDef = device.definition
	if event is InputEventMouseMotion:
		var cell := _top_left(def, point + _moving_offset)
		_preview = {"def": def, "cell": cell, "ok": _sim.layout.validate_move(_moving, cell) == "", "moving": _moving}
		device.modulate.a = 0.35
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var id := _moving
		_moving = ""
		device.modulate.a = 1.0
		var to_bar := point.y > Layout.FRONT.end.y
		var cell := _top_left(def, point + _moving_offset)
		_preview = {}
		queue_redraw()
		if to_bar or cell != device.cell:
			device_dropped.emit(id, cell, to_bar)
		get_viewport().set_input_as_handled()


func _drop() -> void:
	var actor: Node2D = _staff[_dragged]
	actor.dragging = false
	actor.z_index = 0
	if _drag_target != "" or _dropped_on_bar:
		# Land where the finger let go; the snapshot moves the worker on from there.
		actor.target = actor.position
		staff_dropped.emit(_dragged, _drag_target)
	_dragged = ""
	_drag_target = ""
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
	var window: Vector2 = _positions.get("shelf", Layout.WINDOW)
	draw_texture_rect(Assets.texture("res://art/env/env_window.png"), Rect2(window.x - 52, Layout.WINDOW.y - 46, 104, 56), false)
	_draw_grid()
	draw_string(_font, Vector2(56, 146), "后厨 · 布局模式（时间暂停）" if _layout_mode else "后厨", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("77908e"))
	draw_string(_font, Vector2(56, 842), "前厅", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("a48d71"))
	draw_string(_font, Vector2(56, 1180), "入口", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a48d71"))
	if _layout_mode:
		_draw_ghosts()
	if not _preview.is_empty():
		var def: StationDef = _preview.def
		var rect := Layout.device_rect(def, _preview.cell)
		var color := Color(0.45, 0.75, 0.55, 0.35) if _preview.ok else Color(0.9, 0.3, 0.25, 0.35)
		draw_rect(rect.grow(-4), color)
		draw_rect(rect.grow(-4), Color(color, 0.9), false, 3.0)
		if def.needs_staff():
			draw_rect(Layout.cell_rect(_preview.cell + def.work_cell).grow(-12), Color(color, 0.6), false, 2.0)
	if _dragged != "":
		_draw_drop_targets()


## 后厨地面格；布局模式里格线更明显，可放原料柜的墙边格和货架接口另外标出来
func _draw_grid() -> void:
	var grid := _sim.config.grid
	if grid == null:
		return
	var line := Color(1, 1, 1, 0.5 if _layout_mode else 0.18)
	for x in grid.kitchen_rect.size.x + 1:
		var px := Layout.GRID_ORIGIN.x + x * Layout.CELL
		draw_line(Vector2(px, Layout.GRID_ORIGIN.y), Vector2(px, Layout.GRID_ORIGIN.y + grid.kitchen_rect.size.y * Layout.CELL), line, 2.0)
	for y in grid.kitchen_rect.size.y + 1:
		var py := Layout.GRID_ORIGIN.y + y * Layout.CELL
		draw_line(Vector2(Layout.GRID_ORIGIN.x, py), Vector2(Layout.GRID_ORIGIN.x + grid.kitchen_rect.size.x * Layout.CELL, py), line, 2.0)
	if not _layout_mode:
		return
	for c in grid.supply_wall_cells:
		draw_rect(Layout.cell_rect(c).grow(-6), Color(0.85, 0.75, 0.55, 0.25))
	var shelf := Layout.cell_rect(grid.shelf_cell).grow(-6)
	draw_rect(shelf, Color(0.95, 0.85, 0.5, 0.35))
	draw_string(_font, shelf.position + Vector2(8, shelf.size.y - 10), "货架口", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("8a7139"))


## 推荐位的虚线框：已开放、草稿里还没有这台设备时才画
func _draw_ghosts() -> void:
	var placed := {}
	for id in _devices:
		placed[_devices[id].definition.id] = true
	var open: Array = _sim.last_snapshot.get("open_devices", [])
	for rec in _sim.config.grid.recommended:
		var def := _sim.config.device_def(String(rec.station))
		if def == null or placed.has(def.id) or not def.id in open:
			continue
		var rect := Layout.device_rect(def, rec.cell).grow(-8)
		_dashed_rect(rect, Color(1, 1, 1, 0.85))
		draw_string(_font, rect.position + Vector2(10, 24), def.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))


func _dashed_rect(rect: Rect2, color: Color) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 2.0, 10.0)


## 拖员工时把能上岗的地方框出来
func _draw_drop_targets() -> void:
	for id in _devices:
		var device: Node2D = _devices[id]
		if not device.definition.needs_staff():
			continue
		var rect := Layout.cell_rect(device.cell + device.definition.work_cell).grow(-6)
		var hot: bool = id == _drag_target
		draw_rect(rect, Color(0.95, 0.8, 0.4, 0.4 if hot else 0.15))
		draw_rect(rect, Color("e6bb60") if hot else Color(1, 1, 1, 0.6), false, 4.0 if hot else 2.0)


func _panel(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


class BeltItems extends Node2D:
	var view: Node2D

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		for belt in view._belts.values():
			if is_instance_valid(belt) and belt.visible:
				belt.draw_items(self)
