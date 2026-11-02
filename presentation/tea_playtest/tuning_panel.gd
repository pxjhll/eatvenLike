extends PanelContainer
## 调参面板: playtest knobs that scale the .tres numbers live (dine-in time, customer flow, machine times,
## staff speed, prices), so feel can be compared without a rebuild. Values stay in user://tuning.cfg,
## apart from the shop save, and apply from the next cup / customer on.

const FILE := "user://tuning.cfg"
## key, label, what the multiplier does to the number shown
const ROWS := [
	["seat", "用餐时间"], ["customer", "来客间隔"], ["boil", "煮茶时间"], ["mix", "调奶时间"],
	["seal", "封口时间"], ["topping", "加料时间"], ["press", "手打时间"], ["lemonade", "柠檬水时间"],
	["walk", "员工走路速度"], ["work", "员工干活速度"], ["price", "售价"],
]
const STEP := 0.05

var game: Node
var persist := false
var _sliders := {}
var _values := {}
var _font: Font
var _log_info: Label


func setup(owner_game: Node, save_to_disk: bool) -> void:
	game = owner_game
	persist = save_to_disk
	_font = load("res://art/ui/graybox_font.ttf")
	if persist: _load()
	_build()
	visible = false


func toggle() -> void:
	visible = not visible
	if visible: refresh()


func set_value(key: String, value: float) -> void:
	var before: float = game.sim.tuned(key)
	game.sim.tune[key] = clampf(snappedf(value, STEP), game.sim.TUNE_MIN, game.sim.TUNE_MAX)
	if not is_equal_approx(before, game.sim.tune[key]) and game.recorder != null: game.recorder.log_tune(key, game.sim.tune[key])
	if _sliders.has(key) and not is_equal_approx(_sliders[key].value, game.sim.tune[key]): _sliders[key].set_value_no_signal(game.sim.tune[key])
	refresh()
	if persist: _save()


func reset_all() -> void:
	for row in ROWS: set_value(row[0], 1.0)


func refresh() -> void:
	for row in ROWS:
		var key: String = row[0]
		_values[key].text = "×%.2f  %s" % [game.sim.tuned(key), _now(key)]
	if _log_info != null and game.recorder != null:
		_log_info.text = "开店录制：%d 条（每 60 秒一条，购买和调参也会录）" % game.recorder.line_count() if game.recorder.enabled else "开店录制：这里不保存"


## What the knob gives right now, in the units a player feels.
func _now(key: String) -> String:
	var sim = game.sim
	match key:
		"seat": return "%.0f 秒" % sim.seat_seconds()
		"customer": return "%.1f 秒一位" % sim._order_interval()
		"boil": return "%.0f 秒一锅" % sim._machine_duration("boil")
		"mix": return "%.1f 秒一杯" % sim._machine_duration("mix")
		"seal": return "%.1f 秒一杯" % sim.seal_seconds()
		"topping": return "%.1f 秒一杯" % (sim._topping_seconds() / sim._speed("topping") * sim.tuned("topping"))
		"press": return "%.1f 秒一杯" % (sim.PRESS_DEF.art_seconds / sim._speed("press") * sim.tuned("press"))
		"lemonade": return "%.1f 秒一杯" % (sim._definition("lemonade").cycle_seconds / sim._speed("lemonade") * sim.tuned("lemonade"))
		"price": return "奶茶 %d 金币" % sim._dish_price("plain_milk_tea")
	return ""


func _build() -> void:
	name = "TuningPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2(16, 112)
	custom_minimum_size = Vector2(688, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.97, 0.9, 0.94)
	style.border_color = Color(0.55, 0.4, 0.28)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _label("调参（1.00 = 原设定）", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var reset := _button("全部还原")
	reset.name = "Reset"
	reset.pressed.connect(reset_all)
	heading.add_child(reset)
	var close := _button("收起")
	close.name = "Close"
	close.pressed.connect(toggle)
	heading.add_child(close)
	for row in ROWS:
		var key: String = row[0]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		column.add_child(line)
		var name_label := _label(row[1], 22)
		name_label.custom_minimum_size = Vector2(150, 0)
		line.add_child(name_label)
		var slider := HSlider.new()
		slider.name = "Slider_" + key
		slider.min_value = game.sim.TUNE_MIN
		slider.max_value = game.sim.TUNE_MAX
		slider.step = STEP
		slider.value = game.sim.tuned(key)
		slider.custom_minimum_size = Vector2(260, 40)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void: set_value(key, value))
		line.add_child(slider)
		_sliders[key] = slider
		var value := _label("", 20)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
		_values[key] = value
	column.add_child(_label("改动从下一杯、下一位客人开始生效；不影响存档。", 18))
	column.add_child(HSeparator.new())
	_log_info = _label("", 20)
	column.add_child(_log_info)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var mark := _button("标出此时")
	mark.name = "Mark"
	mark.tooltip_text = "不好玩时点一下，录制里会留一个标"
	mark.pressed.connect(_mark)
	actions.add_child(mark)
	var copy := _button("复制录制")
	copy.name = "Copy"
	copy.pressed.connect(_copy)
	actions.add_child(copy)
	var export := _button("导出文件")
	export.name = "Export"
	export.pressed.connect(_export)
	actions.add_child(export)
	var clear := _button("清空录制")
	clear.name = "Clear"
	clear.pressed.connect(_clear)
	actions.add_child(clear)
	refresh()


func _mark() -> void:
	if game.recorder == null: return
	game.recorder.write({"t": int(game.sim.elapsed), "mark": true, "stage": game.sim.stage_index, "gold": game.sim.gold, "queue": game.sim.orders.size()})
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
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 20)
	return button


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(FILE) != OK: return
	for row in ROWS:
		var value: Variant = config.get_value("tune", row[0], 1.0)
		if (value is float or value is int) and is_finite(float(value)):
			game.sim.tune[row[0]] = clampf(float(value), game.sim.TUNE_MIN, game.sim.TUNE_MAX)


func _save() -> void:
	var config := ConfigFile.new()
	for row in ROWS: config.set_value("tune", row[0], game.sim.tuned(row[0]))
	config.save(FILE)
