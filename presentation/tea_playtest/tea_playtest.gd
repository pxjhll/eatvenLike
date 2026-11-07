extends Node2D
## Playable session in the existing artwork. Sim owns all inventories, tasks and time.

const Sim := preload("res://game/tea_playtest/tea_playtest_sim.gd")
const Layout := preload("res://content/tea/art_playtest_layout.gd")
const ArtGroups := preload("res://presentation/shop/art_groups.gd")
const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
const DragController := preload("res://presentation/tea_playtest/staff_drag_controller.gd")
const Guide := preload("res://presentation/tea_playtest/guide_overlay.gd")
const UnlockFrame := preload("res://presentation/shop/unlock_frame.gd")
const UpgradeBadge := preload("res://presentation/shop/upgrade_badge.gd")
const TuningPanel := preload("res://presentation/tea_playtest/tuning_panel.gd")
const Recorder := preload("res://presentation/tea_playtest/play_recorder.gd")
const ART_NAMES := preload("res://presentation/characters/character_library.gd").NAMES
const STATION_NAMES := {"boil": "手作煮茶", "mix": "自动调奶", "topping": "手工加料", "seal": "自动封口"}
## Machines show no standing text: a bar while working and a bubble only when they need a hand.
const BADGES := {"boil": Vector2(300, 114), "mix": Vector2(452, 79), "topping": Vector2(36, 616), "seal": Vector2(564, 178)}
const SALE_POINT := Vector2(490, 740)
const CUSTOMER_HEIGHT := Layout.CUSTOMER_HEIGHT
var sim: RefCounted
var store: RefCounted
var save_status := "自动存档已开启"
var _autosave_elapsed := 0.0
var art: Node2D
var selected_worker := 1
var _actors := {}
var _customers := {}
var _customer_positions := {}
var _customer_orders := {}
var _customer_entering := {}
## Dine-in seats already taken last frame, to tell which customer just sat down.
var _known_seats := {}
var _cups: Array[Sprite2D] = []
var _badges := {}
var _bars := {}
var _pops: Array[Dictionary] = []
var _staff_cards: Array[Button] = []
var _shelf: Label
var _seats: Label
var _toast: Label
var _toast_left := 0.0
var _last_sold := 0
var _last_revenue := 0
var _hire_button: Button
var _train_button: Button
var _pause_button: Button
var _belt_button: Button
var _restart_button: Button
var _speed_button: Button
var _speed_factor := 1.0
var _font: Font
var _drag: Node2D
var _post_labels := {}
var ui: Control
## The tutorial runs only in the real game (a scene that loads its own save); tests inject a sim.
var guide: Control
## The shop fills the screen width and scrolls up and down: _scroll is the world's
## vertical offset in screen pixels (0 = top edge showing, negative = scrolled down).
const MIN_VISIBLE_WORLD := 1100.0
const PAN_SLOP := 12.0
var _scroll := 0.0
var _scroll_min := 0.0
var _world_top := 0.0
var _world_factor := 1.0
var _pan_press := Vector2.INF
var _pan_last := Vector2.ZERO
var _panning := false
var guide_enabled := false
## 调参 knobs and the playtest log (written only in the real game, not when tests inject a sim).
var tuning: PanelContainer
var tuning_button: Button
var recorder: RefCounted
var _station_buttons := {}
## Red ↑ marks: on each open machine (and the seats chip for the counter) and on the 员工 tab,
## shown whenever something there can be bought with the coins on hand.
var _upgrade_marks := {}
var _staff_mark: Control
## A pulsing outline on whatever fixes the current bottleneck (a machine, or the staff button).
var _hint_ring: Control
var _staff_ring: Control
var _hint_text := ""
var _glass_button: Button
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
## The shelf's lower tier, where sealed takeaway cups wait.
const PICKUP_ROW_Y := 634.0
const ART_BELTS := {"BeltVertical": "seal_to_shelf"}
const STATION_REGIONS := {
	"supply": Rect2(69, 141, 134, 95), "boil": Rect2(291, 117, 143, 110),
	"mix": Rect2(440, 79, 110, 155), "topping": Rect2(23, 269, 122, 348),
	"seal": Rect2(558, 205, 134, 185), "lemonade": Rect2(31, 595, 123, 184),
	# The front lemon press (muddler, steel cup, ice box) on the counter beside the lemonade dispenser.
	"press": Rect2(189, 656, 113, 141),
}
## A locked machine is not drawn; its floor spot shows a dashed frame instead.
## The cabinet is furniture; its spot shows a frame only while an ingredient box waits to be bought.
## Only the next machine unlock shows; base furniture and the rack are present at opening.
const FRAME_RECTS := {
	"supply": Rect2(69, 155, 134, 78), "boil": Rect2(291, 136, 143, 90),
	"mix": Rect2(446, 112, 106, 116), "topping": Rect2(30, 290, 108, 285),
	"seal": Rect2(564, 228, 123, 154),
	"lemonade": Rect2(35, 625, 119, 145),
	"press": Rect2(195, 675, 108, 110),
}
const FRAME_OPENS := {"shelf": "boil"}
## Tapping the dining room (tables and chairs below the queue) opens the counter panel too.
const COUNTER_DINING_RECT := Rect2(20, 1060, 680, 380)
## The sealer → takeaway rack conveyor is bought from a dashed frame where its art goes.
## Where a seated customer stands to pick up their cup: the counter's free right end.
const PICKUP_POINT := Vector2(635, 925)
const NO_CARRIER_TEXT := "当前没有流动员工搬运，饮品可能无法送到下一站或货架。"
const BELT_ID := "seal_to_shelf"
const BELT_FRAME := Rect2(590, 385, 72, 150)
## What each kitchen belt saves, shown on its dashed frame's tooltip.
const BELT_NOTES := {
	"seal_to_shelf": "封好口的外带杯自动送上货架外带格，后厨不用再搬",
	"boil_to_mix": "煮好的茶自动送到调奶台，后厨不用再搬",
	"mix_to_topping": "调好的奶茶自动送到加料机，后厨不用再搬",
	"topping_to_seal": "加好料的奶茶自动送到封口机，后厨不用再搬",
}


func _ready() -> void:
	DisplayServer.window_set_title("手作奶茶店")
	art = $Canvas/ShopArt
	_font = load("res://art/ui/graybox_font.ttf")
	var guides_seen: Array = []
	if sim == null:
		guide_enabled = true
		if store == null:
			store = get_node("/root/App").art_shop_save
		sim = store.load_game()
		_speed_factor = store.loaded_speed
		guides_seen = store.loaded_guides
		if not store.last_error.is_empty():
			save_status = store.last_error
		# 刚从煎饼摊结店过来：奶茶店从空店开始（员工不带过来）
		var app := get_node_or_null("/root/App")
		if app != null and app.profile.fresh_shop and app.profile.shop == "tea":
			if sim.has_method("reset_shop"): sim.reset_shop()
			app.profile.fresh_shop = false
			app.profile.save()
			store.save_game(sim, _speed_factor, guides_seen)
	for node in art.find_children("*", "Node2D", true, false):
		if node.get_meta("art_layer", "") in ["actors", "drinks"]:
			node.visible = false
	_build_ui()
	_build_glass_toggle()
	_build_tuning()
	guide = Guide.new()
	$Overlay/UI.add_child(guide)
	guide.setup(self, guides_seen)
	guide.enabled = guide_enabled
	_build_badges()
	_drag = DragController.new()
	$Canvas.add_child(_drag)
	_drag.setup(self)
	_reset_visuals()
	if sim.has_method("station_info"):
		_build_station_signs()
	if _belts_offered():
		_build_belts()
	elif sim.has_method("retire_belts") and sim.retire_belts() > 0:
		save_now(false)
	_refresh(0.0)
	_fit()
	_show_toast(sim.current_goal() if sim.has_method("current_goal") else "欢迎开店，伙伴正在准备第一杯奶茶。")
	# A loaded shop where every kitchen hand is seated gets the same warning as the drag that seated them.
	if carrier_warning():
		_show_toast(NO_CARRIER_TEXT)


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
	_customer_orders.clear()
	_customer_entering.clear()
	_known_seats.clear()
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
	if ui.page != "characters" and not guide.freezes():
		var before: float = sim.elapsed
		sim.advance(minf(delta, 0.25) * _speed_factor)
		if recorder != null: recorder.tick(sim.elapsed - before)
	_refresh(delta)
	guide.refresh(delta)
	_fit()
	_toast_left = maxf(0, _toast_left - delta)
	_toast.visible = _toast_left > 0 or not _staffing_warning().is_empty()
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
		elif station.phase == "stir":
			need = "待操作"
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
	_shelf.visible = true
	if sim.has_method("free_seats"):
		_seats.text = "堂食 %d/%d" % [sim.diners.size() + sim.seated_orders(), sim.seats]
		_seats.visible = sim.station_unlocked("lemonade")
	if sim.has_method("station_info"):
		_refresh_station_signs()
	if _belts_offered():
		_refresh_belts()
	for post in _post_labels:
		var owner := -1
		for worker in sim.workers:
			if worker.get("post", "") == post:
				owner = int(worker.id)
				_post_labels[post].text = "前台" if post == "counter" else "坐班"
		_post_labels[post].visible = owner != -1
	var staffing_warning := _staffing_warning()
	if not staffing_warning.is_empty() and _toast_left <= 0:
		_toast.text = staffing_warning
	_update_cups()
	_update_customers(delta if not sim.paused and ui.page != "characters" and not (guide != null and guide.freezes()) else 0.0)
	if "diners" in sim:
		art.get_node("Sortables/DiningArea").refresh(sim.seats, sim.diners, _font, sim.elapsed, delta if not sim.paused and ui.page != "characters" and not (guide != null and guide.freezes()) else 0.0)
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
			draws.append({"pos": Vector2(557 + i * 51, 574), "item": shelf_items[i], "host": "Rack"})
	# Sealed takeaway cups wait on the shelf's lower tier, where the front picks them up.
	if sim.stations.has("pickup"):
		var sealed: Array = []
		for dish in sim.stations.pickup.output:
			for unused in mini(int(sim.stations.pickup.output[dish]), 3 - sealed.size()):
				sealed.append(dish)
		for i in sealed.size():
			draws.append({"pos": Vector2(557 + i * 51, PICKUP_ROW_Y), "item": sealed[i], "host": "Rack"})
	for belt in sim.belt_items:
		var route: PackedVector2Array = _belt_points.get(belt.route, Layout.belt_path(belt.route))
		var point := _along(route, float(belt.progress))
		var host := "BeltHorizontal" if belt.route == "topping_to_seal" else "BeltVertical" if belt.route == "seal_to_shelf" or not _belt_points.has(belt.route) else ""
		for i in int(belt.count):
			var offset := Vector2((i - (int(belt.count) - 1) / 2.0) * 14, -i * 2)
			draws.append({"pos": point + offset, "item": belt.item, "host": host})
	var buffer_points := {"mix": Vector2(493, 218), "topping": Vector2(78, 465), "seal": Vector2(626, 405)}
	var buffer_hosts := {"mix": "MachineTable", "topping": "PrepBench", "seal": "Sealer"}
	# One full-size cup marks a waiting output; the station sign already shows how many.
	for id in buffer_points:
		if not sim.stations.has(id):
			continue
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
	# Customers come in through the door at the bottom, up the aisle, and queue in two rows at the counter.
	# One who found a seat waits in it, and walks up to the counter's end when their cup is handed over.
	var standing := 0
	for order: Dictionary in sim.orders:
		var seat := int(order.get("seat", -1))
		var i := standing
		if seat < 0:
			standing += 1
			if i >= 8: continue
		active[order.id] = true
		if not _customers.has(order.id):
			var actor := Actor.new()
			actor.setup(Actor.Characters.customer_art(int(order.id)), _font, CUSTOMER_HEIGHT)
			art.get_node("Sortables").add_child(actor)
			_customers[order.id] = actor
			_customer_positions[order.id] = Layout.ENTRANCE
			_customer_entering[order.id] = true
		_customer_orders[order.id] = order
		var goal := Layout.queue_point(i)
		if seat >= 0: goal = PICKUP_POINT if order.reserved else Layout.seat_point(seat)
		# A newcomer walks up the aisle first, so they don't cut across the tables.
		var waypoint := Vector2(Layout.AISLE_X, Layout.DINING_LANES[0])
		var point: Vector2 = _customer_positions[order.id]
		if _customer_entering.get(order.id, false):
			point = point.move_toward(waypoint, delta * 170.0)
			if point.distance_to(waypoint) < 1.0: _customer_entering.erase(order.id)
		else:
			point = point.move_toward(goal, delta * 170.0)
		_customer_positions[order.id] = point
		if sim.has_method("order_mood"):
			_customers[order.id].show_order(String(order.dish), -1.0, sim.order_mood(order), order.get("takeaway", false))
		else:
			var patience: float = sim.CONFIG.customer_patience if "CONFIG" in sim else 0.0
			_customers[order.id].show_order(String(order.get("dish", "sealed")), 1.0 - float(order.wait) / patience if patience > 0 else -1.0)
		var pose := {"pos": point, "walking": point.distance_to(goal) > 1, "phase": "idle", "task_label": ""}
		if seat >= 0 and not order.reserved and point.distance_to(goal) <= 1:
			pose.seated = true
			pose.facing = 2 if seat % 2 == 0 else 6
		_customers[order.id].display(pose, sim.elapsed)
		# Match the dining layer while waiting in a chair; restore floor sorting on pickup.
		_customers[order.id].z_index = 1 if pose.get("seated", false) else 0
		if pose.get("seated", false): _customers[order.id].position.y -= 14.0
	# Served customers leave the queue: dine-in ones walk to the chair the sale gave them, the rest go out the door.
	var seats_now := {}
	if "diners" in sim:
		for diner in sim.diners: seats_now[int(diner.seat)] = true
	var new_seats: Array = seats_now.keys().filter(func(seat: int) -> bool: return not _known_seats.has(seat))
	new_seats.sort()
	_known_seats = seats_now
	var leaving: Array = _customers.keys().filter(func(id) -> bool: return not active.has(id))
	leaving.sort()
	var dining: Node = art.get_node_or_null("Sortables/DiningArea")
	for id in leaving:
		var order: Dictionary = _customer_orders.get(id, {})
		var art_id: String = Actor.Characters.customer_art(int(id))
		if dining != null:
			var kept := int(order.get("seat", -1))
			if kept >= 0 and kept in new_seats:
				new_seats.erase(kept)
				dining.queue_arrival(kept, _customer_positions[id], art_id)
			elif not order.get("takeaway", false) and not new_seats.is_empty():
				dining.queue_arrival(new_seats.pop_front(), _customer_positions[id], art_id)
			else:
				dining.queue_exit(_customer_positions[id], art_id, String(order.get("dish", "")))
		_customers[id].free()
		_customers.erase(id)
		_customer_positions.erase(id)
		_customer_orders.erase(id)
		_customer_entering.erase(id)


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
	_speed_button = ui.speed_button
	_toast = ui.toast


func _build_tuning() -> void:
	if not sim.has_method("tuned"):
		return
	recorder = Recorder.new()
	recorder.enabled = guide_enabled
	recorder.setup(sim)
	var tuning_shade := ColorRect.new()
	tuning_shade.name = "TuningShade"
	tuning_shade.color = Color(0.12, 0.09, 0.065, 0.34)
	tuning_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Overlay/UI.add_child(tuning_shade)
	tuning_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tuning_shade.offset_top = 106
	tuning_shade.offset_bottom = -112
	tuning_shade.hide()
	tuning = TuningPanel.new()
	$Overlay/UI.add_child(tuning)
	tuning.setup(self, guide_enabled)
	tuning.visibility_changed.connect(func() -> void: tuning_shade.visible = tuning.visible)
	tuning_button = Button.new()
	tuning_button.name = "Tuning"
	tuning_button.text = "调参"
	tuning_button.custom_minimum_size = Vector2(68, 34)
	tuning_button.theme = ui.theme
	tuning_button.add_theme_font_size_override("font_size", 17)
	tuning_button.pressed.connect(func() -> void:
		ui.open_page("shop")
		tuning.toggle())
	# The reference header has only speed and menu. Developer controls live in the
	# menu footer, keeping the business target readable on a portrait viewport.
	var footer: Node = ui._save_caption.get_parent()
	footer.add_child(tuning_button)


## The open 调参 panel sits over the kitchen; taps and drags on it never reach the floor.
func tuning_covers(screen: Vector2) -> bool:
	return tuning != null and tuning.visible and tuning.get_global_rect().has_point(screen)


func _bought(what: String, gold_before: int) -> void:
	if recorder != null: recorder.log_buy(what, gold_before)


func _build_badges() -> void:
	var parent: Node = $Canvas/WorldLabels
	for id in BADGES:
		if not sim.stations.has(id):
			continue
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
	_shelf = _chip(parent, Vector2(560, 684))
	# The chip sits above the dining furniture and opens the seat purchase panel.
	_seats = _chip(parent, Vector2(42, 918))
	_seats.mouse_filter = Control.MOUSE_FILTER_STOP
	_seats.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: ui.open_station("counter"))
	_seats.visible = false
	for post in Layout.POST_POINTS:
		var label := _chip(parent, Layout.POST_POINTS[post] + Vector2(-26, 14))
		label.visible = false
		_post_labels[post] = label


func _chip(parent: Node, point: Vector2) -> Label:
	var label := _label(parent, point, 16)
	var box := preload("res://presentation/ui/reference_theme.gd").style("pill", 12)
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
	var coin := TextureRect.new()
	coin.texture = preload("res://art/ui/coin_small.png")
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.size = Vector2(26, 26)
	coin.position = Vector2(-30, 6)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_child(coin)
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


## A hire goes straight to work (kitchen first, then the counter); drag them onto a post later to change jobs.
func hire_worker() -> void:
	if sim.has_method("staff_slots") and not ui.has_staff_room():
		_show_toast("店里没有空位了，解锁新设备后可以多派伙伴。")
		return
	var gold_before: int = sim.gold
	if sim.hire():
		_bought("hire", gold_before)
		selected_worker = int(all_staff().back().id)
		var deployed: bool = not sim.has_method("deploy_worker") or sim.deploy_worker(selected_worker).is_empty()
		_show_toast("新伙伴上岗了！拖动伙伴可以换岗位。" if deployed else "新伙伴已加入名册，可在员工界面派遣。")
		save_now(false)
	_refresh(0.0)


func _train_selected() -> void:
	if sim.train(selected_worker):
		_show_toast("培养完成，擅长的能力已提升。")
		save_now(false)
	_refresh(0.0)


func buy_staff_upgrade(side: String) -> void:
	var info: Dictionary = sim.staff_upgrade_info(side)
	var gold_before: int = sim.gold
	var error: String = sim.buy_staff_upgrade(side)
	if error.is_empty(): _bought("staff_%s/%s" % [side, info.name], gold_before)
	_show_toast(error if not error.is_empty() else "%s升级：%s" % ["前台" if side == "front" else "后厨", info.name])
	if error.is_empty():
		save_now(false)
	_refresh(0.0)


func train_selected() -> void:
	if sim.has_method("buy_staff_upgrade"):
		buy_staff_upgrade("front")
		return
	_train_selected()


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
	# Keep the user's higher mixer clear of the HUD without changing scene coordinates.
	var fitted_size := Layout.WORLD_SIZE + Vector2(0, 50)
	# Fill the screen width; the part that does not fit vertically is reached by scrolling.
	# Wide (landscape) windows stop zooming once MIN_VISIBLE_WORLD units of height would be lost.
	var world_factor := minf(size.x / fitted_size.x, size.y / MIN_VISIBLE_WORLD)
	_world_factor = world_factor
	var world_height := fitted_size.y * world_factor
	_scroll_min = minf(0.0, size.y - world_height)
	# A world shorter than the window sits centred and does not scroll.
	_world_top = maxf(0.0, (size.y - world_height) / 2.0)
	$Canvas.position.x = (size.x - fitted_size.x * world_factor) / 2.0
	$Canvas.scale = Vector2.ONE * world_factor
	scroll_world_by(0.0)
	# Keep HUD panels inside the shop width; vertical anchors still follow the visible window.
	$Overlay/UI.position = Vector2($Canvas.position.x, 0)
	$Overlay/UI.scale = Vector2.ONE * world_factor
	$Overlay/UI.size = Vector2(720, size.y / world_factor)
	ui.fit_to_size($Overlay/UI.size)
	if tuning != null and tuning.has_method("fit_to_size"):
		tuning.fit_to_size($Overlay/UI.size)


## Moves the shop up or down by a screen distance, clamped to the world's edges.
func scroll_world_by(delta: float) -> void:
	_scroll = clampf(_scroll + delta, _scroll_min, 0.0)
	$Canvas.position.y = _world_top + 50.0 * _world_factor + _scroll


## Scrolls just enough that a world rectangle sits between the header and the bottom bar.
func reveal_world(rect: Rect2) -> void:
	var canvas: Transform2D = $Canvas.get_global_transform_with_canvas()
	var top: float = (canvas * rect.position).y
	var bottom: float = (canvas * rect.end).y
	var view_height: float = get_viewport_rect().size.y
	var header: float = 110.0 * _world_factor
	var footer: float = view_height - 120.0 * _world_factor
	if bottom > footer:
		scroll_world_by(footer - bottom)
	elif top < header:
		scroll_world_by(header - top)


func _build_glass_toggle() -> void:
	_glass_button = Button.new()
	_glass_button.text = "玻璃隔板"
	_glass_button.toggle_mode = true
	_glass_button.custom_minimum_size.y = 64
	_glass_button.icon = preload("res://presentation/ui/reference_icons.gd").texture("glass")
	_glass_button.expand_icon = true
	_glass_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_glass_button.add_theme_constant_override("icon_max_width", 38)
	_glass_button.add_theme_constant_override("h_separation", 18)
	_glass_button.add_theme_font_size_override("font_size", 25)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_glass_button.add_theme_stylebox_override(state, preload("res://presentation/ui/reference_theme.gd").style("card", 14, state))
	_glass_button.theme = ui.theme
	_glass_button.toggled.connect(set_glass_visible)
	ui._page_nodes.menu.add_child(_glass_button)
	ui._page_nodes.menu.move_child(_glass_button, ui.restart_button.get_index())
	var glass_switch := preload("res://presentation/ui/reference_toggle.gd").new()
	glass_switch.anchor_left = 1.0
	glass_switch.anchor_right = 1.0
	glass_switch.anchor_top = 0.5
	glass_switch.anchor_bottom = 0.5
	glass_switch.offset_left = -90
	glass_switch.offset_right = -26
	glass_switch.offset_top = -17
	glass_switch.offset_bottom = 17
	_glass_button.add_child(glass_switch)


func set_glass_visible(show_glass: bool) -> void:
	art.get_node("Sortables/Checkout/GlassPartition").visible = show_glass
	_glass_button.set_pressed_no_signal(show_glass)


func _mobile_count() -> int:
	var count := 0
	for worker in sim.workers:
		if worker.get("post", "").is_empty():
			count += 1
	return count


func _staffing_warning() -> String:
	if sim.workers.is_empty():
		return "店内暂无员工，请从员工名册派遣伙伴。"
	if _mobile_count() > 0:
		return ""
	if sim.has_method("station_unlocked"):
		var kitchen_open := false
		for id in ["boil", "mix", "topping", "press", "seal"]:
			kitchen_open = kitchen_open or sim.station_unlocked(id)
		if not kitchen_open:
			return ""
	return "缺少流动员工，搬运将等待；拖到空地可恢复流动。"


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
	var message: String = error if not error.is_empty() else "伙伴已回到名册。" if returning else "伙伴已派到店内。"
	if error.is_empty() and returning and carrier_warning():
		message = NO_CARRIER_TEXT
	_show_toast(message)
	if error.is_empty():
		save_now(false)
	_refresh(0)


## True when someone works the kitchen but every kitchen hand is seated: nobody carries between machines.
func carrier_warning() -> bool:
	return sim.has_method("no_kitchen_carrier") and sim.no_kitchen_carrier()


func station_action(action: String, station: String, material := "") -> void:
	var error := ""
	var gold_before: int = sim.gold
	match action:
		"unlock": error = sim.unlock_station(station)
		"upgrade": error = sim.upgrade_station(station)
		"material": error = sim.upgrade_material(station, material)
		"box": error = sim.unlock_box(material)
		"seat": error = sim.buy_seat()
		"flyers": error = sim.buy_flyers()
		"flyer_upgrade": error = sim.upgrade_flyers()
	var done: String = {"unlock": "设备已解锁。", "box": "原料箱已解锁。", "seat": "加了两个座位。", "flyers": "传单发出去了。", "flyer_upgrade": "传单升级了。"}.get(action, "升级完成。")
	_show_toast(error if not error.is_empty() else done)
	if error.is_empty():
		var level: int = sim.station_levels.get(station, 0) if action != "material" else sim.material_levels.get(station, {}).get(material, 0)
		_bought("%s %s%s Lv%d" % [action, station, ("/" + material) if material != "" else "", level], gold_before)
		save_now(false)
	_refresh(0)


func save_now(notify := true) -> Error:
	if store == null:
		return OK
	var result: Error = store.save_game(sim, _speed_factor, guide.seen_list() if guide != null else [])
	save_status = "进度已保存" if result == OK else store.last_error
	if notify:
		_show_toast(save_status)
	return result


func _build_station_signs() -> void:
	for id in FRAME_RECTS:
		var frame := UnlockFrame.new()
		frame.position = FRAME_RECTS[id].position
		frame.size = FRAME_RECTS[id].size
		frame.theme = ui.theme
		frame.add_theme_font_size_override("font_size", 17)
		frame.pressed.connect(ui.open_station.bind(FRAME_OPENS.get(id, id)))
		$Canvas/WorldLabels.add_child(frame)
		_station_buttons[id] = frame
	for id in STATION_REGIONS:
		var mark := UpgradeBadge.new()
		var region: Rect2 = STATION_REGIONS[id]
		mark.center_on(Vector2(region.end.x - 14, region.position.y + 14))
		$Canvas/WorldLabels.add_child(mark)
		_upgrade_marks[id] = mark
	if sim.has_method("buy_belt"):
		var belt_frame := UnlockFrame.new()
		belt_frame.position = BELT_FRAME.position
		belt_frame.size = BELT_FRAME.size
		belt_frame.theme = ui.theme
		belt_frame.add_theme_font_size_override("font_size", 17)
		belt_frame.pressed.connect(buy_belt)
		$Canvas/WorldLabels.add_child(belt_frame)
		_station_buttons["belt"] = belt_frame
		_build_kitchen_belts()
	if sim.has_method("buy_seat"):
		var seat_frame := UnlockFrame.new()
		seat_frame.theme = ui.theme
		seat_frame.add_theme_font_size_override("font_size", 17)
		seat_frame.pressed.connect(station_action.bind("seat", "counter"))
		$Canvas/WorldLabels.add_child(seat_frame)
		_station_buttons["seat"] = seat_frame
	_upgrade_marks.counter = UpgradeBadge.new()
	_seats.add_child(_upgrade_marks.counter)
	_staff_mark = UpgradeBadge.new()
	ui.staff_button.add_child(_staff_mark)
	_hint_ring = HintRing.new()
	$Canvas/WorldLabels.add_child(_hint_ring)
	_staff_ring = HintRing.new()
	ui.staff_button.add_child(_staff_ring)


func _refresh_station_signs() -> void:
	var next_stage: int = int(sim.stage_index) + 1 if sim.station_unlocked("lemonade") else 0
	var box: String = sim.pending_box()
	for id in _station_buttons:
		if id == "belt":
			var row: Dictionary = {}
			for candidate in sim.belt_rows():
				if candidate.id == BELT_ID: row = candidate
			var belt_frame: Button = _station_buttons[id]
			belt_frame.visible = not row.is_empty() and row.available and not row.owned
			if not belt_frame.visible:
				continue
			belt_frame.can_unlock = String(row.error).is_empty()
			belt_frame.text = "传送带\n%d 金币" % row.cost
			belt_frame.tooltip_text = BELT_NOTES[BELT_ID] + "\n" + String(row.error)
			continue
		if id.begins_with("belt:"):
			var belt_id: String = String(id).trim_prefix("belt:")
			var belt_row: Dictionary = {}
			for candidate in sim.belt_rows():
				if candidate.id == belt_id: belt_row = candidate
			var segment_frame: Button = _station_buttons[id]
			var owned: bool = not belt_row.is_empty() and belt_row.owned
			if _belt_lines.has(belt_id): _belt_lines[belt_id].visible = owned
			segment_frame.visible = not belt_row.is_empty() and belt_row.available and not owned
			if not segment_frame.visible:
				continue
			segment_frame.can_unlock = String(belt_row.error).is_empty()
			segment_frame.text = "传送带\n%d 金币" % belt_row.cost
			segment_frame.tooltip_text = BELT_NOTES.get(belt_id, belt_row.name) + "\n" + String(belt_row.error)
			continue
		if id == "seat":
			# The next table to buy: a dashed frame over its faint chairs, once the lemonade stand is open.
			var seat_frame: Button = _station_buttons[id]
			var table_index: int = int(sim.seats) / 2
			seat_frame.visible = sim.station_unlocked("lemonade") and sim.seat_cost() >= 0 and table_index < Layout.DINING_TABLES.size()
			if not seat_frame.visible:
				continue
			var table: Vector2 = Layout.DINING_TABLES[table_index]
			seat_frame.position = table + Vector2(-60, -78)
			seat_frame.size = Vector2(120, 72)
			seat_frame.can_unlock = sim.seat_error().is_empty()
			seat_frame.text = "加 %d 个座位\n%d 金币" % [sim.PROGRESSION.seat_step, sim.seat_cost()]
			seat_frame.tooltip_text = "有空座位的堂食客人先坐下再点单，坐着等更有耐心\n" + sim.seat_error()
			continue
		if id == "supply":
			# The cabinet frame asks for the ingredient box the newest machine needs.
			var box_frame: Button = _station_buttons[id]
			box_frame.visible = not box.is_empty()
			if box.is_empty():
				continue
			var definition = sim._box_def(box)
			box_frame.can_unlock = sim.box_error(box).is_empty()
			box_frame.text = "%s箱\n%d 金币" % [definition.display_name, definition.box_cost]
			box_frame.tooltip_text = "解锁后%s才有原料" % sim.station_info_name(definition.box_machine)
			continue
		var sign: String = FRAME_OPENS.get(id, id)
		var info: Dictionary = sim.station_info(sign)
		var frame: Button = _station_buttons[id]
		frame.visible = not info.unlocked and int(info.stage) == next_stage
		frame.can_unlock = id == sign and String(info.unlock_error).is_empty()
		frame.tooltip_text = info.description + "\n" + info.get("unlock_error", "")
		if id != sign:
			continue
		var title: String = info.get("line_name", info.name) if id == "boil" else info.name
		frame.text = "%s\n%d 金币" % [title, info.unlock_cost]
	ArtGroups.refresh(art, sim)
	for id in _upgrade_marks:
		var frame: Button = _station_buttons.get(id)
		_upgrade_marks[id].visible = can_buy_at(id) and not (frame != null and frame.visible)
	# Beside the seats chip rather than on it, so the seat count stays readable.
	_upgrade_marks.counter.center_on(Vector2(_seats.size.x + 16, _seats.size.y / 2.0))
	_staff_mark.visible = ui.staff_affordable()
	var hint: Dictionary = sim.bottleneck_hint() if sim.has_method("bottleneck_hint") else {}
	var target := String(hint.get("target", ""))
	# The full reason shows once, when the line first jams; the goal bar keeps the short form.
	if not hint.is_empty() and _hint_text != String(hint.text): _show_toast(String(hint.text))
	_hint_text = String(hint.get("text", ""))
	_hint_ring.visible = STATION_REGIONS.has(target)
	if _hint_ring.visible:
		_hint_ring.position = STATION_REGIONS[target].position - Vector2(6, 6)
		_hint_ring.size = STATION_REGIONS[target].size + Vector2(12, 12)
	_staff_ring.visible = target.begins_with("staff_")
	if _staff_ring.visible:
		_staff_ring.position = Vector2(-4, -4)
		_staff_ring.size = ui.staff_button.size + Vector2(8, 8)
	_staff_mark.center_on(Vector2(ui.staff_button.size.x - 14, 12))


## The kitchen belts without their own art: drawn as a strip along the segment's points, each
## bought from a dashed frame at its middle. The sealer → rack belt keeps its art and frame.
func _build_kitchen_belts() -> void:
	var lines := Node2D.new()
	lines.name = "KitchenBelts"
	art.add_child(lines)
	art.move_child(lines, art.get_node("Sortables").get_index())
	for row in sim.belt_rows():
		if not row.id in sim.GAME_BELTS or row.id in ART_BELTS.values():
			continue
		_belt_points[row.id] = row.points
		var line := Line2D.new()
		line.points = row.points
		line.width = 24
		line.default_color = Color("6b5444")
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		var inner := Line2D.new()
		inner.points = row.points
		inner.width = 14
		inner.default_color = Color("a68b70")
		inner.joint_mode = Line2D.LINE_JOINT_ROUND
		line.add_child(inner)
		line.visible = false
		lines.add_child(line)
		_belt_lines[row.id] = line
		var frame := UnlockFrame.new()
		frame.size = Vector2(118, 64)
		frame.position = _along(row.points, 0.5) - frame.size / 2.0
		frame.theme = ui.theme
		frame.add_theme_font_size_override("font_size", 17)
		frame.pressed.connect(buy_belt.bind(row.id))
		$Canvas/WorldLabels.add_child(frame)
		_station_buttons["belt:" + row.id] = frame


## Buys a kitchen belt from its dashed frame (the sealer → takeaway rack one by default).
func buy_belt(id := BELT_ID) -> void:
	var before: int = sim.gold
	var error: String = sim.buy_belt(id)
	if not error.is_empty():
		_show_toast(error)
		return
	_bought("belt " + id, before)
	_show_toast("传送带装好了：" + String(BELT_NOTES.get(id, "")).get_slice("，", 0))
	save_now(false)
	_refresh(0.0)


## Anything in this machine's panel the player can pay for right now: its next level, an ingredient
## level, or for the counter a seat or a flyer round. Locked machines use their dashed frame instead.
func can_buy_at(id: String) -> bool:
	if not sim.station_unlocked(id):
		return false
	if sim._upgrade_error(id).is_empty():
		return true
	if id == "counter":
		# A flyer is worth a nudge only while the line has room for the extra customers.
		return sim.seat_error().is_empty() or sim.flyer_upgrade_error().is_empty() or (sim.flyer_error().is_empty() and sim.orders.size() * 2 < sim._queue_capacity())
	var definition = sim._definition(id)
	if definition != null:
		for material in definition.materials:
			if sim._material_error(id, material.id).is_empty():
				return true
	return false


func _belts_offered() -> bool:
	return sim.has_method("buy_belt") and sim.BELTS_IN_GAME


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
	# Handle the native touch once; its emulated mouse press would open the sheet
	# before the touch reaches the GUI, where the new shade would close it again.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if not sim.has_method("station_info"):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if not ui.blocks_world(event.position) and not tuning_covers(event.position):
			scroll_world_by(80.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -80.0)
			get_viewport().set_input_as_handled()
		return
	var pressed: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	pressed = pressed or (event is InputEventScreenTouch and event.pressed)
	var released: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	released = released or (event is InputEventScreenTouch and not event.pressed and not event.canceled)
	if pressed:
		# A press on a staff member belongs to the staff drag; anything else may become a scroll or a tap.
		_panning = false
		_pan_press = Vector2.INF
		if ui.blocks_world(event.position) or tuning_covers(event.position) or _drag.worker_id != -1:
			return
		_pan_press = event.position
		_pan_last = event.position
		return
	if _pan_press == Vector2.INF:
		return
	var moved: bool = event is InputEventScreenDrag or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT)
	if moved:
		if _drag.worker_id != -1:
			_pan_press = Vector2.INF
			return
		# A dimmed tutorial step points at a fixed spot, so the shop holds still under it.
		if not _panning and event.position.distance_to(_pan_press) > PAN_SLOP and not (guide != null and guide.freezes()):
			_panning = true
		if _panning:
			scroll_world_by(event.position.y - _pan_last.y)
			get_viewport().set_input_as_handled()
		_pan_last = event.position
		return
	if event is InputEventScreenTouch and event.canceled:
		_pan_press = Vector2.INF
		_panning = false
		return
	if not released:
		return
	var was_pan := _panning
	_pan_press = Vector2.INF
	_panning = false
	if was_pan or _drag.worker_id != -1:
		return
	# A tap (press and release without scrolling) opens what is under it.
	var point: Vector2 = $Canvas.get_global_transform_with_canvas().affine_inverse() * event.position
	for id in STATION_REGIONS:
		if STATION_REGIONS[id].has_point(point):
			ui.open_station(id)
			get_viewport().set_input_as_handled()
			return
	if _opens_counter(point):
		ui.open_station("counter")
		get_viewport().set_input_as_handled()


## The counter panel (seats, flyers) opens from the small 堂食 chip, its red ↑ beside it,
## the counter itself or the dining room. Machines on the counter are checked first.
func _opens_counter(point: Vector2) -> bool:
	if not _seats.visible:
		return false
	var chip := Rect2(_seats.position, _seats.size).grow_individual(12, 14, 52, 14)
	return chip.has_point(point) or Layout.POST_RECTS.counter.has_point(point) or COUNTER_DINING_RECT.has_point(point)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST] and sim != null:
		save_now(false)


func _exit_tree() -> void:
	if sim != null:
		save_now(false)


## Pulsing yellow outline drawn around the fix for the current bottleneck; it never takes taps.
class HintRing extends Control:
	var _clock := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _process(delta: float) -> void:
		if not visible: return
		_clock += delta
		modulate.a = 0.55 + 0.45 * sin(_clock * 5.0)
		queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.border_color = Color("ffc928")
		box.set_border_width_all(5)
		box.set_corner_radius_all(14)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
