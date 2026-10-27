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
	_add_button(buttons, "一键布局", func() -> SimCommand: return EnterLayoutCommand.new())
	_add_button(buttons, "一键部署", func() -> SimCommand: return AutoDeployCommand.new())
	_add_button(buttons, "确认布局", func() -> SimCommand: return ConfirmLayoutCommand.new())
	_add_button(buttons, "取消布局", func() -> SimCommand: return CancelLayoutCommand.new())
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


func _add_button(parent: Control, text: String, make_command: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void: _sim.submit(make_command.call()))
	parent.add_child(b)
	_buttons.append({"button": b})


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = 2.0


func _on_tick(snap: Dictionary) -> void:
	for entry in _buttons:
		entry.button.visible = snap.kitchen_open
	var lines := PackedStringArray()
	lines.append("时间 %.1f 秒  金币 %d  累计营业额 %d%s" % [snap.time, snap.gold, snap.revenue, "  布局模式" if snap.mode == GameSim.Mode.LAYOUT else ""])
	lines.append("备料架 %s  排队 %d 人" % [snap.production.shelf, snap.front_hall.orders.size()])
	lines.append("")
	for st in snap.production.stations + snap.front_hall.counters:
		lines.append("%s %s  Lv%d  %s  %s  入 %s  出 %s  进度 %d%%" % [
			st.slot, st.def, st.level, StationState.Status.keys()[st.status], StationState.Phase.keys()[st.phase],
			st.inputs, st.outputs, roundi(st.progress * 100.0)])
	for seg in snap.production.segments:
		if not seg.items.is_empty():
			lines.append("传送带 %s：%d 件" % [seg.id, seg.items.size()])
	lines.append("")
	for s in snap.workforce.staff:
		var doing := "空闲" if s.request < 0 else "工作中 %.1f/%.1f 秒" % [s.work_done, s.work_seconds]
		lines.append("%s @ %s  %s" % [s.staff, s.post if s.post != "" else "员工栏", doing])
	lines.append("")
	for task in snap.tasks:
		lines.append("任务 %s  %d%%" % [task.name, roundi(task.progress * 100.0)])
	if snap.progress.completed:
		lines.append("店铺完成！")
	_status.text = "\n".join(lines)
