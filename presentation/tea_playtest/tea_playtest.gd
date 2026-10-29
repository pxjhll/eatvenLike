extends Node2D
## Playable session in the existing artwork. Sim owns all inventories, tasks and time.

const Sim := preload("res://game/tea_playtest/tea_playtest_sim.gd")
const Layout := preload("res://content/tea/art_playtest_layout.gd")
const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
const DragController := preload("res://presentation/tea_playtest/staff_drag_controller.gd")
const ROLE_NAMES := {"speed": "速度型", "carry": "力量型", "skill": "操作型"}
const ART_NAMES := {"cat": "小猫", "raccoon": "浣熊", "fox": "狐狸"}
const STATION_NAMES := {"boil": "手作煮茶", "mix": "自动调奶", "topping": "手工加料", "seal": "自动封口"}
const BADGES := {"boil": Vector2(255, 99), "mix": Vector2(416, 99), "topping": Vector2(30, 607), "seal": Vector2(547, 172)}
var sim: RefCounted
var art: Node2D
var selected_worker := 1
var _actors := {}
var _customers := {}
var _customer_positions := {}
var _cups: Array[Sprite2D] = []
var _badges := {}
var _staff_cards: Array[Button] = []
var _staff_fatigue: Array[ColorRect] = []
var _gold: Label
var _score: Label
var _stats: Label
var _shelf: Label
var _toast: Label
var _toast_left := 0.0
var _last_sold := 0
var _hire_button: Button
var _train_button: Button
var _pause_button: Button
var _belt_button: Button
var _restart_button: Button
var _old_button: Button
var _speed_button: Button
var _speed_factor := 1.0
var _font: Font
var _drag: Node2D
var _post_labels := {}


func _ready() -> void:
	DisplayServer.window_set_title("奶茶店 · 岗位试玩")
	art = $Canvas/ShopArt
	_font = load("res://art/ui/graybox_font.ttf")
	for node in art.find_children("*", "Node2D", true, false):
		if node.get_meta("art_layer", "") in ["actors", "drinks"]:
			node.visible = false
	_build_ui()
	_build_badges()
	_drag = DragController.new()
	$Canvas.add_child(_drag)
	_drag.setup(self)
	restart()


func restart() -> void:
	if is_instance_valid(_drag):
		_drag.cancel()
	sim = Sim.new()
	selected_worker = int(sim.workers[0].id)
	for actor in _actors.values():
		actor.free()
	_actors.clear()
	for customer in _customers.values():
		customer.free()
	_customers.clear()
	_customer_positions.clear()
	_last_sold = 0
	_show_toast("拖到人工工位坐班，拖到空地流动。员工可培养。")
	_refresh(0.0)
	_fit()


func _process(delta: float) -> void:
	if sim == null:
		return
	sim.advance(minf(delta, 0.25) * _speed_factor)
	_refresh(delta)
	_fit()
	_toast_left = maxf(0, _toast_left - delta)
	_toast.visible = _toast_left > 0 or _mobile_count() == 0


func _refresh(delta: float) -> void:
	_gold.text = "金币 %d" % sim.gold
	_score.text = "已售 %d 杯" % sim.sold
	_speed_button.text = "倍速 ×%d" % int(_speed_factor)
	_hire_button.text = "招募 %d" % sim.hire_cost() if sim.workers.size() < 3 else "员工已满"
	_hire_button.disabled = sim.workers.size() >= 3 or sim.gold < sim.hire_cost()
	_pause_button.text = "继续" if sim.paused else "暂停"
	_belt_button.text = "运输：传送带" if sim.use_belts else "运输：人工搬运"
	for node in art.find_children("*", "Node2D", true, false):
		if node.get_meta("art_layer", "") == "belts":
			node.visible = sim.use_belts or not sim.belt_items.is_empty()
	var selected: Dictionary = sim.workers[0]
	for worker in sim.workers:
		if int(worker.id) == selected_worker:
			selected = worker
		if not _actors.has(worker.id):
			var actor := Actor.new()
			actor.setup(worker.art, _font)
			art.get_node("Sortables").add_child(actor)
			_actors[worker.id] = actor
		_actors[worker.id].selected = int(worker.id) == selected_worker
		_actors[worker.id].display(worker, sim.elapsed)
	_stats.text = "%s  移速 %d  搬量 %d  操作 %.1f" % [ART_NAMES[selected.art], selected.speed, selected.capacity, selected.skill]
	var cost: int = sim.train_cost(selected_worker)
	_train_button.text = "培养 %d" % cost
	_train_button.disabled = sim.gold < cost
	for i in 3:
		if i < sim.workers.size():
			var worker: Dictionary = sim.workers[i]
			var label: String = worker.get("task_label", "")
			var post: String = worker.get("post", "")
			var mode := "流动" if post.is_empty() else ("煮茶坐班" if post == "boil" else "加料坐班")
			var task_text: String = Actor.TASKS.get(label, "待命" if label.is_empty() else label)
			if worker.get("assignment_pending", false):
				task_text = "交接中 · " + task_text
			_staff_cards[i].text = "%s · %s Lv%d\n%s" % [ART_NAMES[worker.art], mode, worker.level, task_text]
			_staff_cards[i].modulate = Color.WHITE if int(worker.id) == selected_worker else Color("e4d7c1")
			_staff_fatigue[i].size.x = 202.0 * clampf(worker.fatigue, 0, 1)
			_staff_fatigue[i].visible = true
			_staff_cards[i].tooltip_text = "移速 %d · 搬量 %d · 操作 %.1f · 软疲劳 %d%%" % [worker.speed, worker.capacity, worker.skill, int(worker.fatigue * 100)]
		else:
			_staff_cards[i].text = "招募伙伴\n一起制作与配送"
			_staff_cards[i].modulate = Color("e4d7c1")
			_staff_fatigue[i].visible = false
	for id in _badges:
		var station: Dictionary = sim.stations[id]
		var state := "等原料"
		var output_count := _total(station.output)
		if station.phase in ["heating", "mixing", "working", "sealing"]:
			state = "%d%%" % int(float(station.progress) * 100)
		elif output_count > 0:
			state = "待取 %d" % output_count
		elif station.phase == "awaiting_take":
			state = "等待取茶"
		elif _total(station.input) > 0:
			state = "待操作"
		_badges[id].text = STATION_NAMES[id] + " " + state
		_badges[id].tooltip_text = "输入 %d · 加工 %d · 输出 %d" % [_total(station.input), station.get("processing", 0), output_count]
	_shelf.text = "成品货架  %d / 3" % sim.shelf_count
	for post in _post_labels:
		var owner := -1
		for worker in sim.workers:
			if worker.get("post", "") == post:
				owner = int(worker.id)
				_post_labels[post].text = ART_NAMES[worker.art] + " · 坐班"
		_post_labels[post].visible = owner != -1
	if _mobile_count() == 0 and _toast_left <= 0:
		_toast.text = "缺少流动员工，搬运将等待；拖到空地可恢复流动。"
	_update_cups()
	_update_customers(delta if not sim.paused else 0.0)
	if sim.sold > _last_sold:
		_show_toast("奶茶已送达，获得金币！")
	_last_sold = sim.sold


func _total(stock: Dictionary) -> int:
	var result := 0
	for amount in stock.values():
		result += int(amount)
	return result


func _update_cups() -> void:
	var draws := []
	for i in sim.shelf_count:
		draws.append({"pos": Vector2(546 + i * 51, 601), "item": "sealed", "height": 53.0, "z": 0})
	for belt in sim.belt_items:
		var route := Layout.belt_path(belt.route)
		var point := _along(route, float(belt.progress))
		for i in int(belt.count):
			var offset := Vector2((i - (int(belt.count) - 1) / 2.0) * 14, -i * 2)
			draws.append({"pos": point + offset, "item": belt.item, "height": 51.0, "z": 0})
	var buffer_points := {"mix": Vector2(488, 270), "topping": Vector2(78, 445), "seal": Vector2(613, 405)}
	for id in buffer_points:
		var count := mini(_total(sim.stations[id].output), 3)
		for i in count:
			draws.append({"pos": buffer_points[id] + Vector2(i * 19, 0), "item": "milk_tea" if id == "mix" else "topped", "height": 37.0, "z": 0})
	while _cups.size() < draws.size():
		var sprite := Sprite2D.new()
		sprite.centered = false
		art.get_node("Sortables").add_child(sprite)
		_cups.append(sprite)
	for i in _cups.size():
		var sprite := _cups[i]
		sprite.visible = i < draws.size()
		if not sprite.visible:
			continue
		var row: Dictionary = draws[i]
		var texture: Texture2D = load("res://art/reference/" + ("cream_tea" if row.item in ["tea", "milk_tea"] else "pearl_tea") + ".png")
		sprite.texture = texture
		sprite.scale = Vector2.ONE * float(row.height) / texture.get_height()
		sprite.position = row.pos - Vector2(texture.get_width() * sprite.scale.x / 2.0, float(row.height))
		# Cup top-left is offset visually; explicit depth keeps it above the belt/shelf.
		sprite.z_index = 1


func _update_customers(delta: float) -> void:
	var active := {}
	for i in sim.orders.size():
		var order: Dictionary = sim.orders[i]
		active[order.id] = true
		if not _customers.has(order.id):
			var actor := Actor.new()
			actor.setup("squirrel" if int(order.id) % 2 else "hamster", _font, 110.0)
			art.get_node("Sortables").add_child(actor)
			_customers[order.id] = actor
			_customer_positions[order.id] = Vector2(740, 1163)
		var goal := Vector2(350 + i * 126, 1163)
		var point: Vector2 = _customer_positions[order.id]
		point = point.move_toward(goal, delta * 170.0)
		_customer_positions[order.id] = point
		_customers[order.id].display({"pos": point, "walking": point.distance_to(goal) > 1, "phase": "idle", "task_label": "珍珠奶茶"}, sim.elapsed)
	for id in _customers.keys():
		if not active.has(id):
			_customers[id].free()
			_customers.erase(id)
			_customer_positions.erase(id)


func _along(points: PackedVector2Array, progress: float) -> Vector2:
	var length := 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	var remaining := clampf(progress, 0, 1) * length
	for i in points.size() - 1:
		var segment := points[i].distance_to(points[i + 1])
		if remaining <= segment:
			return points[i].lerp(points[i + 1], remaining / maxf(segment, 0.001))
		remaining -= segment
	return points[-1]


func _build_ui() -> void:
	var root: Control = $Overlay/UI
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 16
	root.theme = theme
	_panel(root, Rect2(12, 8, 696, 88))
	_gold = _label(root, Vector2(26, 18), 23)
	_score = _label(root, Vector2(204, 22), 20)
	_speed_button = _button(root, Rect2(352, 15, 114, 35), "倍速 ×1", func() -> void:
		_speed_factor = 1.0 if _speed_factor >= 4.0 else _speed_factor * 2.0
		_refresh(0.0))
	_hire_button = _button(root, Rect2(476, 15, 112, 35), "招募", hire_worker)
	_pause_button = _button(root, Rect2(598, 15, 96, 35), "暂停", func() -> void: sim.paused = not sim.paused)
	_stats = _label(root, Vector2(26, 63), 13)
	_belt_button = _button(root, Rect2(282, 57, 150, 31), "运输：传送带", toggle_transport)
	_train_button = _button(root, Rect2(441, 57, 100, 31), "培养", train_selected)
	_restart_button = _button(root, Rect2(550, 57, 68, 31), "重开", restart)
	_old_button = _button(root, Rect2(627, 57, 67, 31), "旧版", func() -> void: get_tree().change_scene_to_file("res://presentation/shop.tscn"))
	_panel(root, Rect2(12, 1201, 696, 76))
	for i in 3:
		var card := _button(root, Rect2(20 + i * 228, 1207, 222, 62), "", _staff_clicked.bind(i))
		card.clip_text = true
		card.add_theme_font_size_override("font_size", 15)
		_staff_cards.append(card)
		var background := ColorRect.new()
		background.position = Vector2(30 + i * 228, 1262)
		background.size = Vector2(202, 4)
		background.color = Color("dacdb6")
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(background)
		var fill := ColorRect.new()
		fill.position = background.position
		fill.size = Vector2(0, 4)
		fill.color = Color("b59162")
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(fill)
		_staff_fatigue.append(fill)
	_toast = _label(root, Vector2(20, 1177), 14)
	_toast.size = Vector2(680, 22)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_badges() -> void:
	var parent: Node = $Canvas/WorldLabels
	for id in BADGES:
		var label := _label(parent, BADGES[id], 15)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size.x = 168 if id == "topping" else 150
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		_badges[id] = label
	_shelf = _label(parent, Vector2(514, 714), 16)
	for post in Layout.POST_POINTS:
		var label := _label(parent, Layout.POST_POINTS[post] + Vector2(-60, 14), 14)
		label.size.x = 120
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.visible = false
		_post_labels[post] = label


func _label(parent: Node, point: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = point
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("573c2a"))
	label.add_theme_color_override("font_outline_color", Color("fff3dd"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _panel(parent: Node, rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f9ebd3")
	style.border_color = Color("79573c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _button(parent: Node, rect: Rect2, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f4dfbc")
	style.border_color = Color("956d4a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color("fff1d4")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = Color("dfc49b")
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color("583b29"))
	button.add_theme_color_override("font_hover_color", Color("583b29"))
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func hire_worker() -> void:
	if sim.hire():
		selected_worker = int(sim.workers.back().id)
		_show_toast("新伙伴加入，会自动领取适合的任务。")
	_refresh(0.0)


func train_selected() -> void:
	if sim.train(selected_worker):
		_show_toast("培养完成，擅长的能力已提升。")
	_refresh(0.0)


func toggle_transport() -> void:
	sim.set_belts(not sim.use_belts)
	_show_toast("切换为传送带运输" if sim.use_belts else "切换为人工搬运")
	_refresh(0.0)


func _staff_clicked(index: int) -> void:
	if index < sim.workers.size():
		selected_worker = int(sim.workers[index].id)
	else:
		hire_worker()
	_refresh(0.0)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = 4.0
	_toast.visible = true


func _fit() -> void:
	var size := get_viewport_rect().size
	var factor := minf(size.x / 720.0, size.y / 1280.0)
	var offset := (size - Vector2(720, 1280) * factor) / 2.0
	$Canvas.position = offset
	$Canvas.scale = Vector2.ONE * factor
	$Overlay/UI.position = offset
	$Overlay/UI.scale = Vector2.ONE * factor


func _mobile_count() -> int:
	var count := 0
	for worker in sim.workers:
		if worker.get("post", "").is_empty():
			count += 1
	return count
