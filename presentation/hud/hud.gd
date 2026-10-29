class_name ShopHud
extends CanvasLayer
## 调试 HUD：显示快照文字，按钮只发命令。正式的 KitchenView / StationView / StaffView 以后替换它。

var _sim: GameSim
var _status: Label
var _toast: Label
var _toast_left := 0.0
var _buttons: Array[Dictionary] = []


func bind(sim: GameSim) -> void:
	unbind()
	for child in get_children():
		child.free()
	_buttons.clear()
	_sim = sim
	_build()
	sim.tick_finished.connect(_on_tick)
	sim.command_rejected.connect(_on_rejected)
	sim.shop_completed.connect(_on_completed)
	_on_tick(sim.last_snapshot)


func unbind() -> void:
	if is_instance_valid(_sim):
		if _sim.tick_finished.is_connected(_on_tick):
			_sim.tick_finished.disconnect(_on_tick)
		if _sim.command_rejected.is_connected(_on_rejected):
			_sim.command_rejected.disconnect(_on_rejected)
		if _sim.shop_completed.is_connected(_on_completed):
			_sim.shop_completed.disconnect(_on_completed)
	_sim = null
	_buttons.clear()


func _exit_tree() -> void:
	unbind()


func _app() -> Node:
	return Engine.get_main_loop().root.get_node("App")


func _on_rejected(_command: SimCommand, reason: String) -> void:
	_show_toast(reason)


func _on_completed() -> void:
	_show_toast("店铺完成，可以换店")


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.text = ""


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_font_override("font", load("res://art/ui/graybox_font.ttf"))
	root.position = Vector2(16, 16)
	root.custom_minimum_size = Vector2(688, 0)
	add_child(root)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_toast = Label.new()
	_toast.modulate = Color(1.0, 0.6, 0.4)
	root.add_child(_toast)
	var buttons := HFlowContainer.new()
	root.add_child(buttons)
	var has_line := false
	for stage in _sim.config.progression.stages:
		has_line = has_line or stage.line_cost > 0
	if has_line:
		_add_button(buttons, "解锁下一条线", UnlockLineCommand.new)
	for slot in _sim.config.slots:
		var def := slot.station
		if slot.parallel_of != "":
			_add_button(buttons, "并联 %s（%d）" % [def.display_name, def.parallel_cost], ActivateParallelCommand.new.bind(slot.id), def.zone == _sim.config.kitchen_zone)
		elif slot.initially_locked and not has_line:
			_add_button(buttons, "解锁 %s（%d）" % [def.display_name, def.unlock_cost], UnlockStationCommand.new.bind(slot.id), def.zone == _sim.config.kitchen_zone)
		if not def.upgrade_costs.is_empty():
			_add_button(buttons, "升级 %s" % slot.id, UpgradeStationCommand.new.bind(slot.id), def.zone == _sim.config.kitchen_zone)
	for s in _sim.last_snapshot.workforce.staff:
		for zone in _sim.config.zones:
			_add_button(buttons, "%s → %s" % [s.staff, zone], AssignStaffCommand.new.bind(s.staff, zone), zone == _sim.config.kitchen_zone)
	var save := Button.new()
	save.text = "存档"
	save.pressed.connect(func() -> void: _app().save_now())
	buttons.add_child(save)
	var switch := Button.new()
	switch.text = "换店"
	switch.pressed.connect(func() -> void:
		var reason: String = _app().switch_shop()
		if reason != "":
			_show_toast(reason))
	buttons.add_child(switch)


func _add_button(parent: Control, text: String, make_command: Callable, kitchen_only: bool = false) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void: _sim.submit(make_command.call()))
	parent.add_child(b)
	_buttons.append({"button": b, "kitchen_only": kitchen_only})


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = 2.0


func _closed_kitchen_slot(slot_id: String, snap: Dictionary) -> bool:
	if snap.kitchen_open:
		return false
	for slot in _sim.config.slots:
		if slot.id == slot_id:
			return slot.station.zone == _sim.config.kitchen_zone
	return false


func _on_tick(snap: Dictionary) -> void:
	for entry in _buttons:
		entry.button.visible = snap.kitchen_open or not entry.kitchen_only
	var lines := PackedStringArray()
	lines.append("时间 %.1f 秒  金币 %d  累计营业额 %d" % [snap.time, snap.gold, snap.revenue])
	lines.append("备料架 %s  排队 %d 人" % [snap.production.shelf, snap.front_hall.orders.size()])
	lines.append("")
	for st in snap.production.stations + snap.front_hall.counters:
		if _closed_kitchen_slot(st.slot, snap):
			continue
		lines.append("%s  Lv%d  %s  %s  入 %s  出 %s  进度 %d%%" % [
			st.slot, st.level, StationState.Status.keys()[st.status], StationState.Phase.keys()[st.phase],
			st.inputs, st.outputs, roundi(st.progress * 100.0)])
	for seg in snap.production.segments:
		var hidden := false
		for connection in _sim.config.connections:
			if connection.id == seg.id:
				hidden = _closed_kitchen_slot(connection.from_slot, snap) or _closed_kitchen_slot(connection.to_slot, snap)
		if hidden:
			continue
		if not seg.items.is_empty():
			lines.append("传送带 %s：%d 件%s" % [seg.id, seg.items.size(), "" if seg.connected else "（已断开）"])
	lines.append("")
	for s in snap.workforce.staff:
		var doing := "空闲" if s.request < 0 else "工作中 %.1f/%.1f 秒" % [s.work_done, s.work_seconds]
		if s.target != "":
			doing += "，调往 %s" % s.target
		lines.append("%s @ %s  %s" % [s.staff, s.zone, doing])
	lines.append("")
	for task in snap.tasks:
		lines.append("任务 %s  %d%%" % [task.name, roundi(task.progress * 100.0)])
	if snap.progress.completed:
		lines.append("店铺完成！")
	_status.text = "\n".join(lines)
