extends VBoxContainer
## Action panel for a real physical station; every price/error comes from the sim.

var station_id := ""
var unlock_button: Button
var upgrade_button: Button
var material_buttons := {}
var _view: Node2D
var _summary: Label
var _requirements: Label
var _materials: VBoxContainer
var _material_signature := ""

func setup(view: Node2D) -> void:
	_view = view
	add_theme_constant_override("separation", 18)
	_summary = _label("", 25)
	unlock_button = _button("解锁", func() -> void: _view.station_action("unlock", station_id))
	upgrade_button = _button("升级", func() -> void: _view.station_action("upgrade", station_id))
	_requirements = _label("", 22)
	_materials = VBoxContainer.new()
	_materials.add_theme_constant_override("separation", 14)
	add_child(_materials)

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _button(text: String, action: Callable, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 78
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	(parent if parent != null else self).add_child(button)
	return button

func show_station(id: String) -> void:
	station_id = id
	_material_signature = ""
	refresh()

func refresh() -> void:
	if _view == null or _view.sim == null or station_id.is_empty():
		return
	var info: Dictionary = _view.sim.station_info(station_id)
	if info.is_empty():
		return
	_summary.text = "%s · %s\n%s" % [info.name, "Lv%d" % info.level if info.unlocked else "未解锁", info.get("description", "")]
	if not info.unlocked and station_id in ["supply", "boil", "mix", "seal"]:
		_summary.text += "\n一次解锁原料柜、煮茶、调奶与封口整条产线。"
	unlock_button.visible = not info.unlocked
	unlock_button.text = "解锁  ·  %d 金币" % int(info.get("unlock_cost", 0))
	unlock_button.disabled = not String(info.get("unlock_error", "")).is_empty()
	upgrade_button.visible = info.unlocked and int(info.get("upgrade_cost", -1)) >= 0
	upgrade_button.text = "升级  ·  %d 金币" % int(info.get("upgrade_cost", 0))
	upgrade_button.disabled = not String(info.get("upgrade_error", "")).is_empty()
	_requirements.text = String(info.get("upgrade_error", "")) if info.unlocked else String(info.get("unlock_error", ""))
	_requirements.visible = not _requirements.text.is_empty()
	var materials: Array = info.get("materials", [])
	var signature := station_id + str(materials.map(func(row: Dictionary) -> String: return row.id))
	if signature != _material_signature:
		for child in _materials.get_children():
			child.free()
		material_buttons.clear()
		for row in materials:
			material_buttons[row.id] = _button("", _view.station_action.bind("material", station_id, String(row.id)), _materials)
		_material_signature = signature
	_materials.visible = info.unlocked and not materials.is_empty()
	for row in materials:
		var button: Button = material_buttons[row.id]
		var cost := int(row.get("upgrade_cost", -1))
		var reason := String(row.get("upgrade_error", ""))
		button.text = "%s Lv%d  ·  %s" % [row.name, row.level, "%d 金币" % cost if cost >= 0 else "已满级"]
		if not reason.is_empty() and cost >= 0:
			button.text += "\n" + reason
		button.disabled = cost < 0 or not reason.is_empty()
