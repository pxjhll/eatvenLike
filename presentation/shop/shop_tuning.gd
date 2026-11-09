extends PanelContainer
## 调参面板（通用）：试玩时现场乘在店铺数据上的倍率（用餐时间、来客间隔、每台机器的时间、员工速度、售价），
## 不用重新导出就能比手感。存在 user://tuning.cfg，和存档分开；从下一杯、下一位客人开始生效。
## 有哪些行由店铺数据决定：有时间的机器各一行，名字是机器名 +“时间”（goals.texts 的 tune_<键> 可以改）。

const FILE := "user://tuning.cfg"
const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const Icons := preload("res://presentation/ui/reference_icons.gd")
const TUNE_MIN := 0.25
const TUNE_MAX := 3.0
## 机器行前面和后面的固定行：[键, 名字]
const HEAD_ROWS := [["seat", "用餐时间"], ["customer", "来客间隔"]]
const TAIL_ROWS := [["walk", "员工走路速度"], ["work", "员工干活速度"], ["price", "售价"]]
const STEP := 0.05

var game: Node
## [键, 名字]：开面板时按店铺数据算出来
var rows: Array = []
var persist := false
var _sliders := {}
var _values := {}
## What each knob gives right now (秒一杯 …), shown under its name: phones have no hover.
var _nows := {}
var _font: Font
var _log_info: Label
var _available := Vector2(720, 1280)


func setup(owner_game: Node, save_to_disk: bool) -> void:
	game = owner_game
	persist = save_to_disk
	_font = ReferenceTheme.ui_font()
	rows = _rows()
	if persist: _load()
	_build()
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()
		fit_to_size(_available)


func set_value(key: String, value: float) -> void:
	var before: float = game.rules.tuned(key)
	game.rules.tune[key] = clampf(snappedf(value, STEP), TUNE_MIN, TUNE_MAX)
	if not is_equal_approx(before, game.rules.tune[key]) and game.recorder != null: game.recorder.log_tune(key, game.rules.tune[key])
	if _sliders.has(key) and not is_equal_approx(_sliders[key].value, game.rules.tune[key]): _sliders[key].set_value_no_signal(game.rules.tune[key])
	refresh()
	if persist: _save()


func reset_all() -> void:
	for row in rows: set_value(row[0], 1.0)


func refresh() -> void:
	for row in rows:
		var key: String = row[0]
		_values[key].text = "×%.2f" % game.rules.tuned(key)
		_nows[key].text = _now(key)
	if _log_info != null and game.recorder != null:
		_log_info.text = "开店录制：%d 条（每 60 秒一条，购买和调参也会录）" % game.recorder.line_count() if game.recorder.enabled else "开店录制：这里不保存"


func _rows() -> Array:
	var rules: ShopRules = game.rules
	var out: Array = HEAD_ROWS.duplicate() if rules.dine_group() != null else [HEAD_ROWS[1]]
	for st in rules.shop.stations:
		if st.block in ["counter", "supply", "pickup"] or game.view.seconds(st.id) <= 0.0: continue
		out.append([st.id, game.view.text("tune_" + st.id, {}, game.view.station_name(st.id) + "时间")])
	out.append_array(TAIL_ROWS)
	return out


## 这一格现在是多少，用玩家感觉得到的单位
func _now(key: String) -> String:
	var rules: ShopRules = game.rules
	match key:
		"seat": return "%.0f 秒" % rules.seat_seconds()
		"customer": return "%.1f 秒一位" % rules._order_interval()
		"walk", "work": return ""
		"price":
			var dish: SpecDish = rules.shop.dishes[mini(1, rules.shop.dishes.size() - 1)]
			return "%s · %s" % [dish.display_name, game.view.quote_text(rules.dish_quote(dish.id))]
	if rules.shop.station(key) != null:
		return game.view.timing_text(key)
	return ""


func _build() -> void:
	name = "TuningPanel"
	theme = ReferenceTheme.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(688, 0)
	var style := ReferenceTheme.style("paper", 28)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	column.add_child(heading)
	var title := _label("调参", 36)
	heading.add_child(title)
	var hint := _label("1.00 = 原设定", 19)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(hint)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reset := _button("全部还原")
	reset.name = "Reset"
	reset.pressed.connect(reset_all)
	heading.add_child(reset)
	var close := _button("收起")
	close.name = "Close"
	close.add_theme_stylebox_override("normal", ReferenceTheme.style("gold", 14))
	close.pressed.connect(toggle)
	heading.add_child(close)
	var group: VBoxContainer
	for index in rows.size():
		var row: Array = rows[index]
		if index == 0 or index == rows.size() - TAIL_ROWS.size():
			var group_panel := PanelContainer.new()
			var group_style := ReferenceTheme.style("card", 18)
			group_style.set_content_margin_all(5)
			group_panel.add_theme_stylebox_override("panel", group_style)
			column.add_child(group_panel)
			group = VBoxContainer.new()
			group.add_theme_constant_override("separation", 1)
			group_panel.add_child(group)
		var key: String = row[0]
		var row_panel := PanelContainer.new()
		var row_style := ReferenceTheme.style("card", 12)
		row_style.content_margin_top = 7
		row_style.content_margin_bottom = 7
		row_panel.add_theme_stylebox_override("panel", row_style)
		group.add_child(row_panel)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		row_panel.add_child(line)
		var name_box := VBoxContainer.new()
		name_box.custom_minimum_size = Vector2(164, 0)
		name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_box.add_theme_constant_override("separation", 0)
		line.add_child(name_box)
		var name_label := _label(row[1], 24)
		name_box.add_child(name_label)
		var now_label := _label("", 16)
		now_label.modulate = Color(1, 1, 1, 0.75)
		name_box.add_child(now_label)
		_nows[key] = now_label
		var slider := HSlider.new()
		slider.name = "Slider_" + key
		slider.min_value = TUNE_MIN
		slider.max_value = TUNE_MAX
		slider.step = STEP
		slider.value = game.rules.tuned(key)
		slider.custom_minimum_size = Vector2(150, 29)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void: set_value(key, value))
		line.add_child(slider)
		_sliders[key] = slider
		var value := _label("", 22)
		value.custom_minimum_size.x = 86
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var value_style := ReferenceTheme.style("pill", 10)
		value_style.content_margin_top = 5
		value_style.content_margin_bottom = 5
		value.add_theme_stylebox_override("normal", value_style)
		line.add_child(value)
		_values[key] = value
	var explanation := _label("基准操作不含员工加成和行走；从下一次操作生效。", 18)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(explanation)
	_log_info = _label("", 16)
	_log_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_log_info)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 12)
	actions.add_theme_constant_override("v_separation", 12)
	column.add_child(actions)
	var previous := _button("上一家店")
	previous.name = "PreviousShop"
	previous.icon = Icons.texture("previous")
	previous.tooltip_text = "存好这家店，跳到上一家店（那家有存档就接着玩）"
	previous.pressed.connect(func() -> void: game.jump_shop(-1))
	actions.add_child(previous)
	var next := _button("下一家店")
	next.name = "NextShop"
	next.icon = Icons.texture("next")
	next.tooltip_text = "存好这家店，跳到下一家店（那家有存档就接着玩）"
	next.pressed.connect(func() -> void: game.jump_shop(1))
	actions.add_child(next)
	var mark := _button("标出此时")
	mark.name = "Mark"
	mark.icon = Icons.texture("tag")
	mark.tooltip_text = "不好玩时点一下，录制里会留一个标"
	mark.pressed.connect(_mark)
	actions.add_child(mark)
	var copy := _button("复制录制")
	copy.name = "Copy"
	copy.icon = Icons.texture("record")
	copy.pressed.connect(_copy)
	actions.add_child(copy)
	var export := _button("导出文件")
	export.name = "Export"
	export.icon = Icons.texture("export")
	export.pressed.connect(_export)
	actions.add_child(export)
	var clear := _button("清空录制")
	clear.name = "Clear"
	clear.icon = Icons.texture("trash")
	clear.pressed.connect(_clear)
	actions.add_child(clear)
	for action: Button in actions.get_children():
		action.custom_minimum_size.y = 60
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.add_theme_font_size_override("font_size", 24)
		action.add_theme_constant_override("icon_max_width", 36)
		action.add_theme_constant_override("h_separation", 12)
	if get_parent() is Control:
		get_parent().resized.connect(func() -> void: fit_to_size(get_parent().size))
	fit_to_size(get_parent().size if get_parent() is Control else _available)
	refresh()


## Match the compact reference sheet while fitting the world-scaled UI and phone viewport.
func fit_to_size(available: Vector2) -> void:
	_available = available
	if not is_inside_tree(): return
	reset_size()
	var content := get_combined_minimum_size()
	var factor := minf(1.0, minf((available.x - 24.0) / content.x, (available.y - 216.0) / content.y))
	scale = Vector2.ONE * maxf(0.1, factor)
	size = Vector2(maxf(content.x, (available.x - 24.0) / scale.x), content.y)
	position = Vector2((available.x - size.x * scale.x) / 2.0, maxf(104.0, available.y - 110.0 - size.y * scale.y))


func _mark() -> void:
	if game.recorder == null: return
	game.recorder.write({"t": int(game.rules.clock), "mark": true, "stage": game.rules.stage_index, "gold": game.rules.gold, "queue": game.rules.orders.size()})
	game._show_toast("已标出，录制里会看到这个时间点")
	refresh()


func _copy() -> void:
	if game.recorder == null: return
	var content: String = game.recorder.text()
	DisplayServer.clipboard_set(content)
	game._show_toast("已复制 %d 条，可以直接发给 Claude" % game.recorder.line_count())


func _export() -> void:
	if game.recorder == null: return
	var result: String = game.recorder.export_file()
	game._show_toast(result)


func _clear() -> void:
	if game.recorder == null: return
	game.recorder.clear()
	game._show_toast("录制已清空，从现在重新录")
	refresh()


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.3, 0.2, 0.14))
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(96, 44)
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, ReferenceTheme.style("cream", 14, state))
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 20)
	return button


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(FILE) != OK: return
	for row in rows:
		var value: Variant = config.get_value("tune", row[0], 1.0)
		if (value is float or value is int) and is_finite(float(value)):
			game.rules.tune[row[0]] = clampf(float(value), TUNE_MIN, TUNE_MAX)


func _save() -> void:
	var config := ConfigFile.new()
	for row in rows: config.set_value("tune", row[0], game.rules.tuned(row[0]))
	config.save(FILE)
