extends CanvasLayer
## Shop controls submit existing commands; labels read snapshots, not local economy.

const Assets := preload("res://presentation/graybox/assets.gd")
const Names := {"rabbit": "兔子", "bear": "小熊", "cat": "小猫"}
const ZoneNames := {"kitchen": "后厨", "front": "前厅"}
const CARD_SIZE := Vector2(268, 120)
## 机器面板里每个物料槽一行
const MAT_ROW := 46.0
var _sim: GameSim
var _view: Node2D
var _debug: CanvasLayer
var _root: Control
var _gold: Label
var _goal: Label
var _progress: ProgressBar
var _card: Panel
var _card_title: Label
var _card_detail: Label
var _card_buttons: Array[Button] = []
## 物料槽升级按钮（原料柜的各原料、加料机的各配料），点开机器时按槽数显示
var _mat_buttons: Array[Button] = []
var _toast: Label
var _unlock: Button
var _menu: Label
var _hint: Label
var _selected := ""
var _selected_kind := ""
var _snapshot := {}
var _font: Font
var _toast_left := 0.0
var _bar: Panel
var _hire: Button
var _bar_hint: Label
var _staff_cards: Array[Button] = []
var _bar_drag := ""
var _idle_staff := []


func bind(sim: GameSim, view: Node2D, debug: CanvasLayer) -> void:
	unbind()
	for child in get_children():
		child.free()
	_card_buttons.clear()
	_mat_buttons.clear()
	_staff_cards.clear()
	_idle_staff = []
	_bar_drag = ""
	_selected = ""
	_selected_kind = ""
	_sim = sim
	_view = view
	_debug = debug
	_font = load("res://art/ui/graybox_font.ttf")
	_build()
	sim.tick_finished.connect(_on_snapshot)
	sim.command_rejected.connect(_on_rejected)
	view.station_selected.connect(_select.bind("station"))
	view.belt_selected.connect(_select.bind("belt"))
	view.selection_cleared.connect(_close)
	view.staff_dropped.connect(_assign)
	_on_snapshot(sim.last_snapshot)


func unbind() -> void:
	if is_instance_valid(_sim):
		if _sim.tick_finished.is_connected(_on_snapshot):
			_sim.tick_finished.disconnect(_on_snapshot)
		if _sim.command_rejected.is_connected(_on_rejected):
			_sim.command_rejected.disconnect(_on_rejected)
	if is_instance_valid(_view):
		for connection in _view.station_selected.get_connections() + _view.belt_selected.get_connections() + _view.selection_cleared.get_connections() + _view.staff_dropped.get_connections():
			if connection.callable.get_object() == self:
				connection.signal.disconnect(connection.callable)
	_sim = null
	_view = null


func _exit_tree() -> void:
	unbind()


func _process(delta: float) -> void:
	if _root != null:
		_root.position.x = (get_viewport().get_visible_rect().size.x - 720) / 2.0
	if _card != null and _card.visible:
		_place_card()
	if _toast_left > 0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left * 3.0, 0.0, 1.0)


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.size = Vector2(720, 1280)
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 16
	_root.theme = theme
	add_child(_root)
	_panel(Rect2(32, 26, 168, 58), Color("fff8e4"), _root)
	var coin := TextureRect.new()
	coin.texture = Assets.icon("coin")
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.position = Vector2(44, 37)
	coin.size = Vector2(36, 36)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(coin)
	_gold = _label("", Vector2(88, 36), 26, Color("90773b"), _root)
	_panel(Rect2(212, 26, 370, 58), Color("eef3e9"), _root)
	_goal = _label("", Vector2(228, 32), 14, Color("526b65"), _root)
	_progress = ProgressBar.new()
	_progress.position = Vector2(228, 60)
	_progress.size = Vector2(338, 10)
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("dbe3d2")
	bg.set_corner_radius_all(5)
	_progress.add_theme_stylebox_override("background", bg)
	var fill := bg.duplicate()
	fill.bg_color = Color("92b29b")
	_progress.add_theme_stylebox_override("fill", fill)
	_root.add_child(_progress)
	var save := _button("", Rect2(594, 30, 42, 50), "save", _root)
	save.tooltip_text = "保存进度"
	save.pressed.connect(func() -> void:
		var err := App.save_now()
		_show_toast("已保存" if err == OK else "保存失败：" + error_string(err)))
	var debug := _button("", Rect2(642, 30, 42, 50), "debug", _root)
	debug.tooltip_text = "显示 / 收起调试面板"
	debug.pressed.connect(func() -> void: _debug.visible = not _debug.visible)
	var art := _button("ART", Rect2(594, 88, 90, 28), "hint", _root)
	art.tooltip_text = "Art preview"
	art.pressed.connect(func() -> void: _sim.get_parent().open_art_preview())
	var play := _button("试玩", Rect2(594, 120, 90, 28), "hint", _root)
	play.pressed.connect(func() -> void:
		if App.save_now() != OK:
			_show_toast("保存失败，未离开当前游戏")
			return
		App._pending_shop_state = _sim.to_dict()
		App.sim = null
		_sim.get_tree().change_scene_to_file("res://presentation/tea_playtest/tea_playtest.tscn"))
	_hint = _label("", Vector2(40, 1104), 13, Color("8a978d"), _root)
	_toast = _label("", Vector2(0, 1264), 14, Color("a16e47"), _root)
	_toast.size = Vector2(720, 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu = _label("", Vector2(56, 750), 16, Color("526b65"), _root)
	_unlock = _button("", Rect2(74, 1124, 572, 42), "lock", _root)
	_unlock.pressed.connect(_unlock_next)
	_build_staff_bar()
	_build_card()


func _unlock_next() -> void:
	var stage := _next_stage(_snapshot)
	if stage == null:
		return
	if stage.line_cost > 0:
		_sim.submit(UnlockLineCommand.new())
		return
	for slot_id in stage.unlock_slots:
		if not slot_id in _snapshot.progress.unlocked_slots:
			_sim.submit(UnlockStationCommand.new(slot_id))
			return


## 员工栏（只在经营模式）：已雇未上岗的员工卡片 + 招人按钮。
## 拖卡片到工位上岗；把在岗的人拖回这里就是下岗（决定⑩）。
func _build_staff_bar() -> void:
	_bar = _panel(Rect2(32, 1194, 656, 68), Color("f2f0e4"), _root)
	_hire = _button("", Rect2(44, 1202, 136, 52), "hire", _root)
	_hire.pressed.connect(func() -> void: _sim.submit(HireStaffCommand.new()))
	_bar_hint = _label("", Vector2(196, 1218), 13, Color("8a978d"), _root)


## 一张未上岗员工的卡片，按下就跟着手指走，松手落在工位上就上岗
func _staff_card(staff_id: String, index: int) -> Button:
	var card := _button(_sim.workforce.display_name(staff_id), Rect2(196 + index * 116, 1202, 108, 52), "assign", _root)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and _bar_drag == staff_id:
			card.position += event.relative
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_bar_drag = staff_id
				card.z_index = 10
			elif _bar_drag == staff_id:
				_finish_bar_drag(card.position + event.position))
	return card


## 松手：落在前厅工位上就上岗，落在开放的后厨就去后厨，落在别处什么也不做
func _finish_bar_drag(at: Vector2) -> void:
	var staff_id := _bar_drag
	_bar_drag = ""
	for card in _staff_cards:
		card.queue_free()
	_staff_cards.clear()
	_idle_staff = ["?"]
	if _view == null or staff_id == "":
		return
	var point: Vector2 = _view.get_global_transform_with_canvas().affine_inverse() * (at + Vector2(_root.position.x, 0))
	var target: String = _view.spot_at(point)
	if target == "" and _view._zone_at(point) == _sim.config.kitchen_zone:
		target = _sim.config.kitchen_zone
	if target != "":
		_assign(staff_id, target)


func _refresh_staff_bar() -> void:
	var idle := []
	for staff in _snapshot.workforce.staff:
		if String(staff.post) == "" and String(staff.zone) == "":
			idle.append(String(staff.staff))
	# 拖动中不要重建卡片，否则手里的那张会被换掉
	if _bar_drag == "" and idle != _idle_staff:
		_idle_staff = idle
		for card in _staff_cards:
			card.queue_free()
		_staff_cards.clear()
		for i in idle.size():
			_staff_cards.append(_staff_card(idle[i], i))
	var cost := _sim.workforce.hire_cost()
	_hire.text = "招人 %d" % cost
	_hire.disabled = int(_snapshot.gold) < cost
	_bar_hint.text = ""
	if idle.is_empty():
		_bar_hint.text = "店里还没人，先招一个" if _sim.workforce.staff_count() == 0 else "所有人都在岗上"


func _build_card() -> void:
	_card = _panel(Rect2(Vector2.ZERO, CARD_SIZE), Color("fffaf0"), _root)
	var style: StyleBoxFlat = _card.get_theme_stylebox("panel")
	style.border_color = Color("d9cfb4")
	style.set_border_width_all(2)
	style.shadow_color = Color(0.2, 0.25, 0.25, 0.18)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_title = _label("", Vector2(16, 12), 18, Color("3f5557"), _card)
	_card_detail = _label("", Vector2(16, 40), 13, Color("7f8d86"), _card)
	for i in 2:
		var button := _button("", Rect2(16 + i * 122, 68, 114, 40), "upgrade", _card)
		button.pressed.connect(_act.bind(i))
		_card_buttons.append(button)
	for i in 4:
		var button := _button("", Rect2(16, 116 + i * MAT_ROW, 236, 38), "upgrade", _card)
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_act_material.bind(i))
		button.visible = false
		_mat_buttons.append(button)
	_card.visible = false


func _on_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_gold.text = str(snapshot.gold)
	var completed := 0.0
	var current := ""
	for task in snapshot.tasks:
		completed += task.progress
		if current == "" and task.progress < 1.0:
			current = task.name
	# Tasks of dishes not yet unlocked still count, so the bar reads as progress toward the next shop.
	var total := 0
	for stage in _sim.config.progression.stages:
		total += stage.tasks.size()
	_progress.value = completed / maxf(total, 1)
	var next := _next_stage(snapshot)
	var menu: Array[String] = []
	for dish in _sim.config.dishes:
		if dish.item_id in snapshot.available or _poured(dish.id):
			menu.append(dish.display_name)
	_menu.text = "菜单：" + (" / ".join(menu) if not menu.is_empty() else "还没有")
	_unlock.visible = next != null
	if next != null and next.line_cost > 0:
		_unlock.text = "解锁%s · 金币 %d · 营业额 %d/%d" % [next.line_name, next.line_cost, snapshot.revenue, next.revenue_threshold]
		_unlock.disabled = snapshot.gold < next.line_cost or snapshot.revenue < next.revenue_threshold
	elif next != null:
		var next_slot: SlotDef
		for slot in _sim.config.slots:
			if slot.id in next.unlock_slots and not slot.id in snapshot.progress.unlocked_slots:
				next_slot = slot
		if next_slot != null:
			var cost := next_slot.station.unlock_cost
			_unlock.text = "解锁%s · 金币 %d · 营业额 %d/%d" % [_dish_name(next.dish_id), cost, snapshot.revenue, next.revenue_threshold]
			_unlock.disabled = snapshot.gold < cost or snapshot.revenue < next.revenue_threshold
	_refresh_staff_bar()
	_hint.text = "按住员工拖到工位上上岗，拖回员工栏是下岗；点机器看升级" if snapshot.kitchen_open else "点价格牌解锁柠檬茶台，招一个人拖到柜台"
	if snapshot.progress.completed:
		_goal.text = "本店目标已达成"
	elif current != "":
		_goal.text = "目标：" + current
	elif next != null:
		_goal.text = "目标：营业额 %d/%d，解锁%s" % [snapshot.revenue, next.revenue_threshold, next.line_name if next.line_name != "" else _dish_name(next.dish_id)]
	else:
		_goal.text = "目标：菜单与任务"
	_refresh_card()


func _select(id: String, kind: String) -> void:
	_selected = id
	_selected_kind = kind
	_view.select(kind, id)
	_card.visible = true
	_card.scale = Vector2(0.9, 0.9)
	_card.pivot_offset = _card.size / 2.0
	create_tween().tween_property(_card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_card()
	_place_card()


func _close() -> void:
	_selected = ""
	_selected_kind = ""
	if _view != null:
		_view.select("", "")
	if _card != null:
		_card.visible = false


func _place_card() -> void:
	if _selected == "" or _view == null:
		return
	var screen := Rect2(Vector2.ZERO, Vector2(720, 1280))
	var anchor: Rect2
	if _selected_kind == "station":
		anchor = _view.station_anchor(_selected)
	else:
		anchor = Rect2(_view.belt_anchor(_selected), Vector2.ZERO)
	anchor.position.x -= _root.position.x
	var size := _card.size
	var at := Vector2(anchor.get_center().x - size.x / 2.0, anchor.end.y + 34)
	if at.y + size.y > 1200:
		at.y = anchor.position.y - size.y - 40
	at.y = maxf(at.y, 96.0)
	at.x = clampf(at.x, screen.position.x + 12, screen.end.x - size.x - 12)
	_card.position = at


func _refresh_card() -> void:
	if _selected == "" or _card == null or not _card.visible:
		return
	_show_materials(0)
	if _selected_kind == "belt":
		_refresh_belt_card()
		return
	var row := _row()
	if row.is_empty():
		return
	var spot := _spot()
	if spot != null:
		_refresh_spot_card(spot, row)
		return
	var slot := _slot()
	if slot == null:
		return
	var def: StationDef = slot.station
	_card_buttons[1].visible = false
	_card_buttons[0].size.x = 236
	_card_buttons[0].icon = Assets.icon("upgrade")
	var line := _line_stage(slot.id)
	if row.status == StationState.Status.LOCKED and line != null:
		_refresh_line_card(line)
		return
	if row.status != StationState.Status.ACTIVE:
		var price := def.parallel_cost if slot.parallel_of != "" else def.unlock_cost
		_card_title.text = def.display_name
		_card_detail.text = "加一台同样的机器，本段设备数量翻倍" if slot.parallel_of != "" else "启用这个机位"
		_card_buttons[0].text = "启用  %d" % price
		_card_buttons[0].disabled = _snapshot.gold < price
		var stage := _stage_unlocking(slot.id)
		if stage != null:
			_card_detail.text = "解锁新菜：%s" % _dish_name(stage.dish_id)
			_card_buttons[0].text = "购买  %d" % price
			if _snapshot.revenue < stage.revenue_threshold:
				_card_detail.text = "营业额 %d/%d 后可买，解锁%s" % [_snapshot.revenue, stage.revenue_threshold, _dish_name(stage.dish_id)]
				_card_buttons[0].disabled = true
		return
	if def.zone == _sim.config.kitchen_zone and not _snapshot.kitchen_open:
		_card_title.text = def.display_name
		_card_detail.text = "解锁新菜后开放后厨"
		_card_buttons[0].text = "后厨未开放"
		_card_buttons[0].disabled = true
		return
	var level := int(row.level)
	var maximum := mini(def.level_speed.size(), def.upgrade_costs.size() + 1)
	var full := level >= maximum
	_card_title.text = "%s  Lv%d" % [def.display_name, level]
	_refresh_materials(def, row)
	if full:
		_card_detail.text = "已经是最高等级"
		_card_buttons[0].text = "已满级"
		_card_buttons[0].disabled = true
		return
	var price: int = def.upgrade_costs[level - 1]
	_card_detail.text = "速度 ×%.2f → ×%.2f" % [def.level_speed[level - 1], def.level_speed[level]]
	for m in def.materials:
		if m.unlock_level == level + 1:
			_card_detail.text += "，开放" + m.display_name
	_card_buttons[0].text = "升级机器  %d" % price
	_card_buttons[0].disabled = _snapshot.gold < price


## 还没买的整条线：点哪一台都是同一张价格牌，一次买齐（首店流程稿 3）
func _refresh_line_card(stage: ShopStageDef) -> void:
	var names: Array[String] = []
	for slot in _sim.config.slots:
		if slot.id in stage.unlock_slots:
			names.append(slot.station.display_name)
	_card_title.text = stage.line_name
	_card_detail.text = " + ".join(names) + "，一起解锁"
	_card_buttons[0].text = "解锁  %d" % stage.line_cost
	_card_buttons[0].disabled = _snapshot.gold < stage.line_cost or _snapshot.revenue < stage.revenue_threshold
	if _snapshot.revenue < stage.revenue_threshold:
		_card_detail.text = "营业额 %d/%d 后可解锁" % [_snapshot.revenue, stage.revenue_threshold]


## 机器面板下半部分：每个物料槽一行，能单独升级；没开放的写要机器几级
func _refresh_materials(def: StationDef, row: Dictionary) -> void:
	_show_materials(def.materials.size())
	for i in def.materials.size():
		var m: MaterialSlotDef = def.materials[i]
		var button := _mat_buttons[i]
		var level := int(row.mat_levels.get(m.id, 1))
		var what := "售价" if def.mode == StationDef.Mode.TOPPING else "出货"
		if int(row.level) < m.unlock_level:
			button.text = "%s · 机器 Lv%d 开放" % [m.display_name, m.unlock_level]
			button.disabled = true
		elif level >= m.max_level():
			button.text = "%s Lv%d · %s ×%.2f · 满级" % [m.display_name, level, what, m.bonus(level)]
			button.disabled = true
		else:
			var price: int = m.upgrade_costs[level - 1]
			button.text = "%s Lv%d · %s ×%.2f→×%.2f · %d" % [m.display_name, level, what, m.bonus(level), m.bonus(level + 1), price]
			button.disabled = int(_snapshot.gold) < price


func _show_materials(count: int) -> void:
	for i in _mat_buttons.size():
		_mat_buttons[i].visible = i < count
	_card.size = CARD_SIZE + Vector2(0, count * MAT_ROW)


func _act_material(index: int) -> void:
	var slot := _slot()
	if slot == null or index >= slot.station.materials.size():
		return
	_sim.submit(UpgradeMaterialCommand.new(slot.id, slot.station.materials[index].id))


## 前厅位点：没解锁时是价格牌，解锁后和别的工位一样能升级。
func _refresh_spot_card(spot: FrontSpotDef, row: Dictionary) -> void:
	var def: StationDef = spot.station
	_card_buttons[1].visible = false
	_card_buttons[0].size.x = 236
	_card_buttons[0].icon = Assets.icon("upgrade")
	if row.status != StationState.Status.ACTIVE:
		_card_title.text = def.display_name
		_card_detail.text = "点一下在前厅摆上它" if spot.posts == 0 else "点一下摆上它，再派一名员工"
		_card_buttons[0].text = "购买  %d" % spot.unlock_cost
		_card_buttons[0].disabled = int(_snapshot.gold) < spot.unlock_cost
		return
	var level := int(row.level)
	var maximum := mini(def.level_speed.size(), def.upgrade_costs.size() + 1)
	_card_title.text = "%s  Lv%d" % [def.display_name, level]
	if level >= maximum:
		_card_detail.text = "已经是最高等级" if maximum > 1 else "这个工位不升级"
		_card_buttons[0].text = "已满级" if maximum > 1 else "不用升级"
		_card_buttons[0].disabled = true
		return
	var price: int = def.upgrade_costs[level - 1]
	_card_detail.text = "速度 ×%.2f → ×%.2f" % [def.level_speed[level - 1], def.level_speed[level]]
	_card_buttons[0].text = "升级  %d" % price
	_card_buttons[0].disabled = int(_snapshot.gold) < price


func _refresh_belt_card() -> void:
	var segment := {}
	for data in _snapshot.production.segments:
		if data.id == _selected:
			segment = data
	var connection := _connection()
	if segment.is_empty() or connection == null:
		return
	_card_title.text = "传送带"
	_card_detail.text = "%s → %s · 线上 %d 件" % [_slot_name(connection.from_slot), _slot_name(connection.to_slot), segment.items.size()]
	_card_buttons[0].size.x = 114
	_card_buttons[0].icon = Assets.icon("belt")
	_card_buttons[0].text = "断开" if segment.connected else "接上"
	_card_buttons[0].disabled = false
	_card_buttons[1].visible = true
	_card_buttons[1].icon = Assets.icon("delete")
	_card_buttons[1].text = "清空"
	_card_buttons[1].disabled = segment.items.is_empty()
	if not _snapshot.kitchen_open and (_kitchen_slot(connection.from_slot) or _kitchen_slot(connection.to_slot)):
		_card_detail.text = "解锁新菜后开放后厨"
		_card_buttons[0].disabled = true
		_card_buttons[1].disabled = true


func _kitchen_slot(slot_id: String) -> bool:
	for slot in _sim.config.slots:
		if slot.id == slot_id:
			return slot.station.zone == _sim.config.kitchen_zone
	return false


## 拖拽落点：前厅位点 = 上岗（满了就和台上的人换岗），工作区 = 后厨调岗，空 = 下岗。
func _assign(id: String, target: String) -> void:
	var me := {}
	for staff in _snapshot.workforce.staff:
		if staff.staff == id:
			me = staff
	if me.is_empty():
		return
	var name: String = _sim.workforce.display_name(id)
	if target == "":
		if String(me.post) == "" and String(me.zone) == "":
			return
		_sim.submit(AssignStaffCommand.new(id, ""))
		_show_toast("%s 下岗了" % name)
		return
	if _sim.front_hall.has_spot(target):
		if String(me.post) == target:
			return
		var capacity := _sim.front_hall.post_capacity(target)
		if _sim.workforce.post_occupancy(target) >= capacity:
			# 工位满了：和台上的人换岗，而不是挤下去
			for staff in _snapshot.workforce.staff:
				if staff.post == target:
					_sim.submit(SwapStaffCommand.new(id, String(staff.staff)))
					_show_toast("%s 和 %s 换了岗" % [name, _sim.workforce.display_name(String(staff.staff))])
					return
			return
		_sim.submit(AssignStaffCommand.new(id, target))
		_show_toast("%s 去了%s" % [name, _sim.front_hall.station_def(target).display_name])
		return
	# Already heading there, or already there with nothing pending: nothing to do.
	if me.target == target or (me.zone == target and me.target == "" and String(me.post) == ""):
		return
	_sim.submit(AssignStaffCommand.new(id, target))
	_show_toast("%s 调往%s" % [name, ZoneNames.get(target, target)])


func _act(button: int) -> void:
	if _selected_kind == "belt":
		var connection := _connection()
		if connection == null:
			return
		if button == 1:
			_sim.submit(ClearItemsCommand.new(_selected))
			return
		for data in _snapshot.production.segments:
			if data.id == _selected:
				_sim.submit(SetConnectionCommand.new(connection.from_slot, connection.to_slot, not data.connected))
		return
	var row := _row()
	if row.is_empty():
		return
	if _spot() != null:
		if row.status == StationState.Status.ACTIVE:
			_sim.submit(UpgradeStationCommand.new(_selected))
		else:
			_sim.submit(UnlockFrontSpotCommand.new(_selected))
		return
	var slot := _slot()
	if slot == null:
		return
	if row.status == StationState.Status.EMPTY_PARALLEL:
		_sim.submit(ActivateParallelCommand.new(_selected))
	elif row.status == StationState.Status.LOCKED and _line_stage(slot.id) != null:
		_sim.submit(UnlockLineCommand.new())
	elif row.status == StationState.Status.LOCKED:
		_sim.submit(UnlockStationCommand.new(_selected))
	else:
		_sim.submit(UpgradeStationCommand.new(_selected))


func _spot() -> FrontSpotDef:
	for spot in _sim.config.front_spots:
		if spot.id == _selected:
			return spot
	return null


func _slot() -> SlotDef:
	for slot in _sim.config.slots:
		if slot.id == _selected:
			return slot
	return null


## 整条一起解锁的阶段（line_cost > 0）里有这个机位就返回它
func _line_stage(slot_id: String) -> ShopStageDef:
	var stage := _stage_unlocking(slot_id)
	return stage if stage != null and stage.line_cost > 0 else null


## 出品台现打的饮品：出品台开着就在菜单上
func _poured(dish_id: String) -> bool:
	for spot in _sim.config.front_spots:
		if spot.station.mode == StationDef.Mode.DISPENSER and dish_id in spot.station.dishes and _sim.front_hall.is_active(spot.id):
			return true
	return false


## The stage whose purchase list holds this slot, if any.
func _stage_unlocking(slot_id: String) -> ShopStageDef:
	for stage in _sim.config.progression.stages:
		if slot_id in stage.unlock_slots:
			return stage
	return null


func _next_stage(snapshot: Dictionary) -> ShopStageDef:
	var stages := _sim.config.progression.stages
	var index := int(snapshot.progress.stage) + 1
	return stages[index] if index < stages.size() else null


func _dish_name(dish_id: String) -> String:
	for dish in _sim.config.dishes:
		if dish.id == dish_id:
			return dish.display_name
	return dish_id


func _slot_name(id: String) -> String:
	if id == "shelf":
		return "备料架"
	for spot in _sim.config.front_spots:
		if spot.id == id:
			return spot.station.display_name
	for slot in _sim.config.slots:
		if slot.id == id:
			return slot.station.display_name
	return id


func _connection() -> ConnectionDef:
	for connection in _sim.config.connections:
		if connection.id == _selected:
			return connection
	return null


func _row() -> Dictionary:
	for row in _snapshot.production.stations + _snapshot.front_hall.counters:
		if row.slot == _selected:
			return row
	return {}


func _on_rejected(_command: SimCommand, reason: String) -> void:
	_show_toast(reason)


func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.modulate.a = 1.0
	_toast_left = 2.0


func _label(text: String, at: Vector2, size: int, color: Color, parent: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _panel(rect: Rect2, color: Color, parent: Control) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _button(text: String, rect: Rect2, icon: String, parent: Control) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = Assets.icon(icon)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 22)
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("42695d"))
	button.add_theme_color_override("font_disabled_color", Color("a8b3a9"))
	for type in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e2eddf") if type != "pressed" else Color("c5dbc9")
		if type == "disabled":
			style.bg_color = Color("eef0e6")
		style.set_corner_radius_all(10)
		button.add_theme_stylebox_override(type, style)
	# Press feedback: a quick squash so taps feel physical.
	button.button_down.connect(func() -> void:
		button.pivot_offset = button.size / 2.0
		create_tween().tween_property(button, "scale", Vector2(0.93, 0.93), 0.05))
	button.button_up.connect(func() -> void:
		create_tween().tween_property(button, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK))
	parent.add_child(button)
	return button
