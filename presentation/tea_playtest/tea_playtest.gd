extends Node2D
## Playable session in the existing artwork. Sim owns all inventories, tasks and time.

const Sim := preload("res://game/tea_playtest/tea_playtest_sim.gd")
const Layout := preload("res://content/tea/art_playtest_layout.gd")
const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
const DragController := preload("res://presentation/tea_playtest/staff_drag_controller.gd")
const ART_NAMES := preload("res://presentation/characters/character_library.gd").NAMES
const STATION_NAMES := {"boil": "手作煮茶", "mix": "自动调奶", "topping": "手工加料", "seal": "自动封口"}
## Machines show no standing text: a bar while working and a bubble only when they need a hand.
const BADGES := {"boil": Vector2(265, 112), "mix": Vector2(420, 112), "topping": Vector2(36, 612), "seal": Vector2(556, 178)}
const SALE_POINT := Vector2(470, 905)
var sim: RefCounted
var store: RefCounted
var save_status := "自动存档已开启"
var _autosave_elapsed := 0.0
var art: Node2D
var selected_worker := 1
var _actors := {}
var _customers := {}
var _customer_positions := {}
var _cups: Array[Sprite2D] = []
var _badges := {}
var _bars := {}
var _pops: Array[Dictionary] = []
var _staff_cards: Array[Button] = []
var _shelf: Label
var _toast: Label
var _toast_left := 0.0
var _last_sold := 0
var _last_revenue := 0
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
var ui: Control
var _station_buttons := {}
var _lemonade_cup: Node2D
## Belt mode shows a plate on every hop that can take a conveyor; drag the chip onto one (or tap it).
var belt_mode := false
var _belt_toggle: Button
var _belt_chip: Button
var _belt_slots := {}
var _belt_lines := {}
var _belt_points := {}
var _chip_home := Vector2(296, 560)
var _chip_dragging := false
## These two hops already have conveyor art in the scene; the rest are drawn as lines.
const ART_BELTS := {"BeltHorizontal": "topping_to_seal", "BeltVertical": "seal_to_shelf"}
const STATION_REGIONS := {
	"supply": Rect2(20, 155, 221, 120), "boil": Rect2(245, 122, 167, 158),
	"mix": Rect2(415, 121, 106, 160), "topping": Rect2(22, 254, 121, 339),
	"seal": Rect2(548, 207, 120, 184), "lemonade": Rect2(40, 838, 250, 200),
}
const SIGN_RECTS := {
	"supply": Rect2(28, 277, 190, 44), "boil": Rect2(246, 276, 164, 44),
	"mix": Rect2(414, 276, 132, 44), "topping": Rect2(24, 603, 168, 52),
	"seal": Rect2(543, 157, 148, 44), "lemonade": Rect2(43, 1000, 235, 52),
}


func _ready() -> void:
	DisplayServer.window_set_title("手作奶茶店")
	art = $Canvas/ShopArt
	_font = load("res://art/ui/graybox_font.ttf")
	if sim == null:
		if store == null:
			store = get_node("/root/App").art_shop_save
		sim = store.load_game()
		_speed_factor = store.loaded_speed
		if not store.last_error.is_empty():
			save_status = store.last_error
	for node in art.find_children("*", "Node2D", true, false):
		if node.get_meta("art_layer", "") in ["actors", "drinks"]:
			node.visible = false
	_build_ui()
	_build_badges()
	_drag = DragController.new()
	$Canvas.add_child(_drag)
	_drag.setup(self)
	_reset_visuals()
	if sim.has_method("station_info"):
		_build_station_signs()
	if sim.has_method("buy_belt"):
		_build_belts()
	_refresh(0.0)
	_fit()
	_show_toast(sim.current_goal() if sim.has_method("current_goal") else "欢迎开店，伙伴正在准备第一杯奶茶。")


func restart() -> void:
	if is_instance_valid(_drag):
		_drag.cancel()
	if sim.has_method("reset_shop"):
		sim.reset_shop()
	else:
		sim = Sim.new()
	_reset_visuals()
	_show_toast("店铺已重新开始。")
	_refresh(0.0)
	_fit()
	save_now(false)


func _reset_visuals() -> void:
	ui.show_selection = false
	var roster := all_staff()
	selected_worker = int(roster[0].id) if not roster.is_empty() else -1
	for actor in _actors.values():
		actor.free()
	_actors.clear()
	for customer in _customers.values():
		customer.free()
	_customers.clear()
	_customer_positions.clear()
	_last_sold = sim.sold
	_last_revenue = _revenue()
	for pop in _pops:
		pop.label.free()
	_pops.clear()


func _revenue() -> int:
	return int(sim.revenue) if "revenue" in sim else sim.sold * sim.SALE_PRICE


func _process(delta: float) -> void:
	if sim == null:
		return
	# Viewing a character freezes business without changing the saved pause flag.
	if ui.page != "characters":
		sim.advance(minf(delta, 0.25) * _speed_factor)
	_refresh(delta)
	_fit()
	_toast_left = maxf(0, _toast_left - delta)
	_toast.visible = _toast_left > 0 or _mobile_count() == 0
	_update_pops(delta)
	if store != null:
		_autosave_elapsed += delta
		if _autosave_elapsed >= 10.0:
			_autosave_elapsed = 0.0
			save_now(false)


func _refresh(delta: float) -> void:
	ui.refresh()
	var deployed := {}
	for worker in sim.workers:
		deployed[int(worker.id)] = true
	for id in _actors.keys():
		if not deployed.has(int(id)):
			_actors[id].free()
			_actors.erase(id)
	for node in art.find_children("*", "Node2D", true, false):
		if node.get_meta("art_layer", "") == "belts":
			if sim.has_method("buy_belt"): node.visible = sim.belts.has(ART_BELTS.get(String(node.name), ""))
			else: node.visible = sim.use_belts or not sim.belt_items.is_empty()
	for worker in sim.workers:
		if not _actors.has(worker.id):
			var actor := Actor.new()
			actor.setup(worker.art, _font)
			art.get_node("Sortables").add_child(actor)
			_actors[worker.id] = actor
		_actors[worker.id].selected = ui.show_selection and int(worker.id) == selected_worker
		_actors[worker.id].display(worker, sim.elapsed)
		_actors[worker.id].task.visible = ui.show_selection and int(worker.id) == selected_worker and ui.page == "shop"
	for id in _badges:
		var station: Dictionary = sim.stations[id]
		var need := ""
		var output_count := _total(station.output)
		var working: bool = station.phase in ["heating", "mixing", "working", "sealing"]
		if working:
			pass
		elif station.phase == "awaiting_take":
			need = "待取茶"
		elif output_count > 0:
			need = "待取 %d" % output_count
		elif _total(station.input) > 0 and id in ["boil", "topping"]:
			need = "待操作"
		var open: bool = not sim.has_method("station_unlocked") or sim.station_unlocked(id)
		_bars[id].visible = open and working
		_bars[id].value = float(station.progress)
		_badges[id].text = need
		_badges[id].visible = open and not working and not need.is_empty()
		_badges[id].tooltip_text = "%s · 输入 %d · 加工 %d · 输出 %d" % [STATION_NAMES[id], _total(station.input), station.get("processing", 0), output_count]
	var limit: int = sim.shelf_limit() if sim.has_method("shelf_limit") else 3
	_shelf.text = "货架 %d/%d" % [sim.shelf_count, limit]
	_shelf.visible = not sim.has_method("station_unlocked") or sim.station_unlocked("seal")
	if sim.has_method("station_info"):
		_refresh_station_signs()
	if sim.has_method("buy_belt"):
		_refresh_belts()
	for post in _post_labels:
		var owner := -1
		for worker in sim.workers:
			if worker.get("post", "") == post:
				owner = int(worker.id)
				_post_labels[post].text = "前台" if post == "counter" else "坐班"
		_post_labels[post].visible = owner != -1
	if _mobile_count() == 0 and _toast_left <= 0:
		_toast.text = "店内暂无员工，请从员工名册派遣伙伴。" if sim.workers.is_empty() else "缺少流动员工，搬运将等待；拖到空地可恢复流动。"
	_update_cups()
	_update_customers(delta if not sim.paused and ui.page != "characters" else 0.0)
	if sim.sold > _last_sold:
		_pop_income(_revenue() - _last_revenue)
	_last_sold = sim.sold
	_last_revenue = _revenue()


func _total(stock: Dictionary) -> int:
	var result := 0
	for amount in stock.values():
		result += int(amount)
	return result


func _update_cups() -> void:
	var draws := []
	var shelf_items: Array = []
	if sim.has_method("station_info"):
		for dish in sim.shelf_stock:
			for unused in mini(int(sim.shelf_stock[dish]), 3 - shelf_items.size()):
				shelf_items.append(dish)
	else:
		for unused in mini(sim.shelf_count, 3):
			shelf_items.append("sealed")
	for i in shelf_items.size():
		draws.append({"pos": Vector2(546 + i * 51, 601), "item": shelf_items[i], "host": "Rack"})
	for belt in sim.belt_items:
		var route: PackedVector2Array = _belt_points.get(belt.route, Layout.belt_path(belt.route))
		var point := _along(route, float(belt.progress))
		var host := "BeltHorizontal" if belt.route == "topping_to_seal" else "BeltVertical" if belt.route == "seal_to_shelf" or not _belt_points.has(belt.route) else ""
		for i in int(belt.count):
			var offset := Vector2((i - (int(belt.count) - 1) / 2.0) * 14, -i * 2)
			draws.append({"pos": point + offset, "item": belt.item, "host": host})
	var buffer_points := {"mix": Vector2(505, 247), "topping": Vector2(78, 445), "seal": Vector2(613, 405)}
	var buffer_hosts := {"mix": "MachineTable", "topping": "PrepBench", "seal": "Sealer"}
	# One full-size cup marks a waiting output; the station sign already shows how many.
	for id in buffer_points:
		for item in sim.stations[id].output:
			if int(sim.stations[id].output[item]) > 0:
				draws.append({"pos": buffer_points[id], "item": item, "host": buffer_hosts[id]})
				break
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
		var texture: Texture2D = load("res://art/reference/" + Actor.item_asset(row.item) + ".png")
		sprite.texture = texture
		sprite.modulate = Actor.item_color(row.item)
		sprite.scale = Vector2.ONE * Actor.CUP_HEIGHT / texture.get_height()
		# A cup resting on furniture sorts just in front of that furniture's floor anchor,
		# so it stays on top of its host but behind staff standing closer to the camera.
		var sort_y: float = row.pos.y if row.host.is_empty() else maxf(row.pos.y, art.get_node("Sortables/" + row.host).position.y + 1.0)
		sprite.position = Vector2(row.pos.x, sort_y)
		sprite.offset = Vector2(-texture.get_width() / 2.0, -texture.get_height() - (sort_y - row.pos.y) / sprite.scale.y)


func _update_customers(delta: float) -> void:
	var active := {}
	# Up to three customers stand at the counter; the rest wait in a second row behind them.
	for i in mini(sim.orders.size(), 6):
		var order: Dictionary = sim.orders[i]
		active[order.id] = true
		if not _customers.has(order.id):
			var actor := Actor.new()
			actor.setup("squirrel" if int(order.id) % 2 else "hamster", _font, 110.0)
			art.get_node("Sortables").add_child(actor)
			_customers[order.id] = actor
			_customer_positions[order.id] = Vector2(740, 1163)
		var goal := Vector2(350 + i * 126, 1163) if i < 3 else Vector2(287 + (i - 3) * 126, 1108)
		var point: Vector2 = _customer_positions[order.id]
		point = point.move_toward(goal, delta * 170.0)
		_customer_positions[order.id] = point
		var patience: float = sim.CONFIG.customer_patience if "CONFIG" in sim else 0.0
		_customers[order.id].show_order(String(order.get("dish", "sealed")), 1.0 - float(order.wait) / patience if patience > 0 else -1.0)
		_customers[order.id].display({"pos": point, "walking": point.distance_to(goal) > 1, "phase": "idle", "task_label": ""}, sim.elapsed)
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
	ui = $Overlay/UI/HUD
	ui.setup(self)
	_hire_button = ui.hire_button
	_train_button = ui.train_button
	_pause_button = ui.pause_button
	_belt_button = ui.belt_button
	_restart_button = ui.restart_button
	_old_button = ui.old_button
	_speed_button = ui.speed_button
	_toast = ui.toast


func _build_badges() -> void:
	var parent: Node = $Canvas/WorldLabels
	for id in BADGES:
		var bar := ProgressBar.new()
		bar.position = BADGES[id]
		bar.size = Vector2(110, 14)
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.theme = ui.theme
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(bar)
		_bars[id] = bar
		var label := _chip(parent, BADGES[id] + Vector2(10, -6))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		_badges[id] = label
	_shelf = _chip(parent, Vector2(560, 706))
	for post in Layout.POST_POINTS:
		var label := _chip(parent, Layout.POST_POINTS[post] + Vector2(-26, 14))
		label.visible = false
		_post_labels[post] = label


func _chip(parent: Node, point: Vector2) -> Label:
	var label := _label(parent, point, 16)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("fff5e2")
	box.border_color = Color("b38c62")
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	label.add_theme_stylebox_override("normal", box)
	label.add_theme_constant_override("outline_size", 0)
	return label


func _pop_income(amount: int) -> void:
	if amount <= 0:
		return
	var label := _label($Canvas/WorldLabels, SALE_POINT, 30)
	label.text = "+%d" % amount
	label.add_theme_color_override("font_color", Color("8b6446"))
	label.add_theme_constant_override("outline_size", 7)
	_pops.append({"label": label, "age": 0.0})


func _update_pops(delta: float) -> void:
	for pop in _pops.duplicate():
		pop.age += delta
		pop.label.position = SALE_POINT - Vector2(0, pop.age * 50.0)
		pop.label.modulate.a = clampf(1.4 - pop.age, 0, 1)
		if pop.age >= 1.4:
			pop.label.free()
			_pops.erase(pop)


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


func hire_worker() -> void:
	if sim.hire():
		selected_worker = int(all_staff().back().id)
		_show_toast("新伙伴已加入名册，可在员工界面派遣。" if sim.has_method("all_workers") else "新伙伴加入，会自动领取适合的任务。")
		save_now(false)
	_refresh(0.0)


func train_selected() -> void:
	if sim.train(selected_worker):
		_show_toast("培养完成，擅长的能力已提升。")
		save_now(false)
	_refresh(0.0)


func toggle_transport() -> void:
	sim.set_belts(not sim.use_belts)
	_show_toast("切换为传送带运输" if sim.use_belts else "切换为人工搬运")
	save_now(false)
	_refresh(0.0)


func open_page(page: String) -> void:
	ui.open_page(page)


func select_worker(id: int, from_card := false) -> void:
	selected_worker = id
	if not from_card:
		ui.show_selection = true
	_refresh(0)


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
	$Overlay/UI.size = Vector2(720, 1280)
	ui.fit_to_size($Overlay/UI.size)


func _mobile_count() -> int:
	var count := 0
	for worker in sim.workers:
		if worker.get("post", "").is_empty():
			count += 1
	return count


func all_staff() -> Array:
	return sim.all_workers() if sim.has_method("all_workers") else sim.workers


func staff_is_deployed(id: int) -> bool:
	for worker in sim.workers:
		if int(worker.id) == id:
			return true
	return false


func toggle_deployment() -> void:
	if not sim.has_method("deploy_worker"):
		return
	var returning := staff_is_deployed(selected_worker)
	var error: String = sim.recall_worker(selected_worker) if returning else sim.deploy_worker(selected_worker)
	_show_toast(error if not error.is_empty() else "伙伴已回到名册。" if returning else "伙伴已派到店内。")
	if error.is_empty():
		save_now(false)
	_refresh(0)


func station_action(action: String, station: String, material := "") -> void:
	var error := ""
	match action:
		"unlock": error = sim.unlock_station(station)
		"upgrade": error = sim.upgrade_station(station)
		"material": error = sim.upgrade_material(station, material)
	_show_toast(error if not error.is_empty() else "设备已解锁。" if action == "unlock" else "升级完成。")
	if error.is_empty():
		save_now(false)
	_refresh(0)


func save_now(notify := true) -> Error:
	if store == null:
		return OK
	var result: Error = store.save_game(sim, _speed_factor)
	save_status = "进度已保存" if result == OK else store.last_error
	if notify:
		_show_toast(save_status)
	return result


func go_to_old_game() -> void:
	if save_now(false) != OK:
		_show_toast(save_status)
		return
	get_tree().change_scene_to_file("res://presentation/shop.tscn")


func _build_station_signs() -> void:
	for id in SIGN_RECTS:
		var button := Button.new()
		button.position = SIGN_RECTS[id].position
		button.size = SIGN_RECTS[id].size
		button.theme = ui.theme
		button.add_theme_font_size_override("font_size", 18)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(ui.open_station.bind(id))
		$Canvas/WorldLabels.add_child(button)
		_station_buttons[id] = button
	# The glass is opaque art, so the cups are children of the case and stand on its upper shelf.
	_lemonade_cup = Node2D.new()
	art.get_node("Sortables/DisplayCase").add_child(_lemonade_cup)
	for x in [-80, 0, 80]:
		var cup := Sprite2D.new()
		cup.texture = load("res://art/reference/fruit_tea.png")
		cup.scale = Vector2.ONE * Actor.CUP_HEIGHT / cup.texture.get_height()
		cup.centered = false
		cup.offset = Vector2(-cup.texture.get_width() / 2.0, -cup.texture.get_height())
		cup.position = Vector2(x, -126)
		_lemonade_cup.add_child(cup)


func _refresh_station_signs() -> void:
	for id in _station_buttons:
		var info: Dictionary = sim.station_info(id)
		_station_buttons[id].visible = not info.unlocked and id in ["boil", "mix", "topping", "lemonade"]
		# Before the revenue gate the plate says when it opens; after it, what it costs.
		var gated: bool = String(info.unlock_error).begins_with("营业额")
		var title: String = info.get("line_name", info.name) if id == "boil" else info.name
		_station_buttons[id].text = "%s\n%s" % [title, "营业额 %d 开放" % info.get("unlock_revenue", 0) if gated else "%d 金币" % info.unlock_cost]
		_station_buttons[id].tooltip_text = info.description + "\n" + info.get("unlock_error", "")
	for id in Layout.STATION_ART:
		if id in ["counter", "shelf"]:
			continue
		var node: Node2D = art.get_node_or_null(Layout.STATION_ART[id])
		if node != null:
			node.modulate = Color.WHITE if sim.station_unlocked(id) else Color(0.6, 0.6, 0.6, 0.48)
	if is_instance_valid(_lemonade_cup):
		_lemonade_cup.visible = sim.station_unlocked("lemonade")


func _build_belts() -> void:
	var lines := Node2D.new()
	lines.name = "BeltSegments"
	art.add_child(lines)
	art.move_child(lines, art.get_node("Sortables").get_index())
	for row in sim.belt_rows():
		_belt_points[row.id] = row.points
		if not row.id in ART_BELTS.values():
			var line := Line2D.new()
			line.points = row.points
			line.width = 24
			line.default_color = Color("6b5444")
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			var inner := Line2D.new()
			inner.points = row.points
			inner.width = 14
			inner.default_color = Color("a68b70")
			line.add_child(inner)
			lines.add_child(line)
			_belt_lines[row.id] = line
		var slot := Button.new()
		slot.theme = ui.theme
		slot.add_theme_font_size_override("font_size", 17)
		slot.focus_mode = Control.FOCUS_NONE
		slot.size = Vector2(118, 46)
		slot.position = _along(row.points, 0.5) - slot.size / 2.0
		slot.pressed.connect(belt_action.bind(row.id))
		$Canvas/WorldLabels.add_child(slot)
		_belt_slots[row.id] = slot
	_belt_toggle = Button.new()
	_belt_toggle.theme = ui.theme
	_belt_toggle.focus_mode = Control.FOCUS_NONE
	_belt_toggle.position = Vector2(290, 616)
	_belt_toggle.size = Vector2(150, 48)
	_belt_toggle.pressed.connect(func() -> void: belt_mode = not belt_mode; _refresh(0))
	$Canvas/WorldLabels.add_child(_belt_toggle)
	_belt_chip = Button.new()
	_belt_chip.theme = ui.theme
	_belt_chip.focus_mode = Control.FOCUS_NONE
	_belt_chip.text = "拖动装带"
	_belt_chip.size = Vector2(118, 48)
	_belt_chip.position = _chip_home
	_belt_chip.gui_input.connect(_on_chip_input)
	$Canvas/WorldLabels.add_child(_belt_chip)


func _refresh_belts() -> void:
	var can_place := false
	for row in sim.belt_rows():
		if _belt_lines.has(row.id):
			_belt_lines[row.id].visible = row.owned
		var slot: Button = _belt_slots[row.id]
		slot.visible = belt_mode and row.available
		slot.text = "收起 +%d" % row.cost if row.owned else "传送带\n%d 金币" % row.cost
		slot.tooltip_text = row.name + ("" if row.owned else "\n" + row.error)
		can_place = can_place or (row.available and not row.owned)
	_belt_toggle.visible = sim.stage_index >= 1
	_belt_toggle.text = "完成" if belt_mode else "传送带"
	_belt_chip.visible = belt_mode and can_place
	if not _chip_dragging:
		_belt_chip.position = _chip_home


func belt_action(id: String) -> void:
	var owned: bool = sim.belts.has(id)
	var error: String = sim.remove_belt(id) if owned else sim.buy_belt(id)
	_show_toast(error if not error.is_empty() else "传送带已收起，金币已退回。" if owned else "传送带已装上，这段不用再人工搬运。")
	if error.is_empty():
		save_now(false)
	_refresh(0)


func _on_chip_input(event: InputEvent) -> void:
	var press: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch
	if press and event.pressed:
		_chip_dragging = true
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _chip_dragging:
		_belt_chip.global_position = _belt_chip.get_global_transform() * event.position - _belt_chip.get_global_rect().size / 2.0
	elif press and not event.pressed and _chip_dragging:
		_chip_dragging = false
		var point: Vector2 = _belt_chip.get_global_transform() * event.position
		_belt_chip.position = _chip_home
		for id in _belt_slots:
			var slot: Button = _belt_slots[id]
			if slot.visible and not sim.belts.has(id) and slot.get_global_rect().grow(24).has_point(point):
				belt_action(id)
				return
		_show_toast("把传送带拖到两台机器之间的价格牌上。")


func _unhandled_input(event: InputEvent) -> void:
	if not sim.has_method("station_info"):
		return
	var pressed: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	pressed = pressed or (event is InputEventScreenTouch and event.pressed)
	if not pressed or ui.blocks_world(event.position) or _drag.worker_id != -1:
		return
	var point: Vector2 = $Canvas.get_global_transform_with_canvas().affine_inverse() * event.position
	for id in STATION_REGIONS:
		if STATION_REGIONS[id].has_point(point):
			ui.open_station(id)
			get_viewport().set_input_as_handled()
			return


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST] and sim != null:
		save_now(false)


func _exit_tree() -> void:
	if sim != null:
		save_now(false)
