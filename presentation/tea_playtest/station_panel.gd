extends VBoxContainer
## Action panel for a real physical station; every price/error comes from the sim.

var station_id := ""
var unlock_button: Button
var upgrade_button: Button
var material_buttons := {}
var _view: Node2D
var _hud: Control
var _upgrade_row: Control
var _upgrade_title: Label
var _upgrade_effect: Label
var _material_title: Label
var _materials: VBoxContainer
var _material_rows := {}
var _material_signature := ""
var _locked: VBoxContainer
var _locked_summary: Label
var _members: HBoxContainer
var _member_signature := ""
var _condition: Control
var _condition_text: Label
var _condition_value: Label
var _condition_bar: ProgressBar

func setup(view: Node2D, hud: Control) -> void:
	_view = view
	_hud = hud
	add_theme_constant_override("separation", 14)
	var upgrade: VBoxContainer = _hud._card(self, "f6ead3", "d7bd97")
	_upgrade_row = upgrade.get_parent()
	var line: HBoxContainer = _hud._row(upgrade, 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	line.add_child(copy)
	_upgrade_title = _hud._text(copy, "", 23)
	_upgrade_effect = _hud._text(copy, "", 19, true)
	upgrade_button = _buy_button(line, func() -> void: _view.station_action("upgrade", station_id))
	_material_title = _hud._text(self, "", 21)
	_materials = VBoxContainer.new()
	_materials.add_theme_constant_override("separation", 10)
	add_child(_materials)
	_locked = VBoxContainer.new()
	_locked.add_theme_constant_override("separation", 14)
	add_child(_locked)
	_locked_summary = _hud._text(_locked, "", 21, true)
	_members = _hud._row(_locked, 10)
	var condition: VBoxContainer = _hud._card(_locked)
	_condition = condition.get_parent()
	var condition_line: HBoxContainer = _hud._row(condition)
	_condition_text = _hud._text(condition_line, "", 21)
	_condition_value = _hud._nowrap(_hud._text(condition_line, "", 21))
	_condition_value.size_flags_horizontal = Control.SIZE_SHRINK_END
	_condition_bar = _hud._bar(condition, 16)
	unlock_button = _hud._action(_locked, "解锁", func() -> void: _view.station_action("unlock", station_id))

func _buy_button(parent: Node, action: Callable) -> Button:
	var button: Button = _hud._action(parent, "", action)
	button.custom_minimum_size = Vector2(150, 72)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button

func show_station(id: String) -> void:
	station_id = id
	_material_signature = ""
	_member_signature = ""
	refresh()

func refresh() -> void:
	if _view == null or _view.sim == null or station_id.is_empty():
		return
	var info: Dictionary = _view.sim.station_info(station_id)
	if info.is_empty():
		return
	var unlocked: bool = info.unlocked
	var in_line: bool = not unlocked and not info.get("line_members", []).is_empty()
	_hud.set_heading(info.line_name if in_line else info.name, "Lv%d" % info.level if unlocked else "未解锁", not unlocked, info.get("description", "") if unlocked else "")
	_upgrade_row.visible = unlocked
	_locked.visible = not unlocked
	if unlocked:
		_refresh_upgrade(info)
		_refresh_materials(info)
	else:
		_material_title.visible = false
		_materials.visible = false
		_refresh_locked(info)

func _refresh_upgrade(info: Dictionary) -> void:
	var level: int = info.level
	var cost := int(info.get("upgrade_cost", -1))
	var effect := String(info.get("effect", ""))
	upgrade_button.visible = not effect.is_empty()
	var price: Dictionary = info.get("price", {})
	if effect.is_empty():
		_upgrade_title.text = "自动设备"
		_upgrade_effect.text = "本体无需升级，升级下面的原料" if not info.get("materials", []).is_empty() else "不用人管，无需升级"
		return
	if cost < 0:
		_upgrade_title.text = "已满级 Lv%d" % level
		if not price.is_empty(): _upgrade_effect.text = "%s %d 金" % [price.sample, price.now]
		elif float(info.get("seconds", -1.0)) > 0: _upgrade_effect.text = "每批 %.1f 秒" % info.seconds
		else: _upgrade_effect.text = "%s ×%.2f" % [effect, info.speed]
		upgrade_button.text = "满级"
		upgrade_button.disabled = true
		return
	_upgrade_title.text = "设备升级 Lv%d → Lv%d" % [level, level + 1]
	if not price.is_empty():
		_upgrade_effect.text = "%s每杯 +%d%% · %s %d → %d 金" % [price.scope, price.step, price.sample, price.now, price.next]
	elif float(info.get("seconds", -1.0)) > 0:
		_upgrade_effect.text = "%s · 每批 %.1f → %.1f 秒" % [effect, info.seconds, info.next_seconds]
	else:
		_upgrade_effect.text = "%s ×%.2f → ×%.2f" % [effect, info.speed, info.next_speed]
	if not String(info.get("next_unlock", "")).is_empty():
		_upgrade_effect.text += " · 开放" + info.next_unlock
	upgrade_button.text = "%d 金币" % cost
	upgrade_button.disabled = not String(info.get("upgrade_error", "")).is_empty()

func _refresh_materials(info: Dictionary) -> void:
	var materials: Array = info.get("materials", [])
	var signature := station_id + str(materials.map(func(row: Dictionary) -> String: return row.id))
	if signature != _material_signature:
		for child in _materials.get_children():
			child.free()
		material_buttons.clear()
		_material_rows.clear()
		for row in materials:
			var card: VBoxContainer = _hud._card(_materials)
			var line: HBoxContainer = _hud._row(card, 12)
			var copy := VBoxContainer.new()
			copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			copy.add_theme_constant_override("separation", 4)
			line.add_child(copy)
			_material_rows[row.id] = {"card": card.get_parent(), "name": _hud._text(copy, "", 22), "effect": _hud._text(copy, "", 19, true)}
			material_buttons[row.id] = _buy_button(line, _view.station_action.bind("material", station_id, String(row.id)))
		_material_signature = signature
		_hud._sheet_height = -1.0
	var flavors := materials.any(func(row: Dictionary) -> bool: return int(row.get("base_price", 0)) > 0)
	_material_title.text = "配料 · 升级提高售价" if flavors else "原料 · 升级提高售价"
	_material_title.visible = not materials.is_empty()
	_materials.visible = not materials.is_empty()
	for row in materials:
		var nodes: Dictionary = _material_rows[row.id]
		var button: Button = material_buttons[row.id]
		var base := int(row.get("base_price", 0))
		var describe := func(bonus: float) -> String: return str(roundi(base * bonus)) if base > 0 else "×%.1f" % bonus
		var label := "售价 " if base > 0 else "效率 "
		var cost := int(row.get("upgrade_cost", -1))
		nodes.card.modulate.a = 1.0
		if int(info.level) < int(row.get("unlock_level", 1)):
			nodes.name.text = row.name
			nodes.effect.text = "%s Lv%d 开放" % [info.name, row.unlock_level]
			nodes.card.modulate.a = 0.6
			button.text = "未开放"
			button.disabled = true
			continue
		nodes.name.text = "%s Lv%d" % [row.name, row.level]
		if row.has("now"):
			nodes.effect.text = "%s每杯 +%d%% · %s %d 金" % [row.scope, row.step, row.sample, row.now] if cost < 0 else "%s每杯 +%d%% · %s %d → %d 金" % [row.scope, row.step, row.sample, row.now, row.next]
			button.text = "满级" if cost < 0 else "%d 金币" % cost
			button.disabled = cost < 0 or not String(row.get("upgrade_error", "")).is_empty()
			continue
		if cost < 0 or float(row.get("next_bonus", -1.0)) < 0:
			nodes.effect.text = label + describe.call(float(row.bonus))
			button.text = "满级"
			button.disabled = true
			continue
		nodes.effect.text = "%s%s → %s" % [label, describe.call(float(row.bonus)), describe.call(float(row.next_bonus))]
		button.text = "%d 金币" % cost
		button.disabled = not String(row.get("upgrade_error", "")).is_empty()

func _refresh_locked(info: Dictionary) -> void:
	var members: Array = info.get("line_members", [])
	var price := int(info.get("dish_price", 0))
	if members.is_empty():
		_locked_summary.text = String(info.get("description", ""))
	else:
		_locked_summary.text = "一次开放 %d 台机器，开始卖%s（售价 %d）" % [members.size(), info.dish_name, price]
	if str(members) != _member_signature:
		for child in _members.get_children():
			child.free()
		for member in members:
			var chip := Label.new()
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.add_theme_font_size_override("font_size", 19)
			_hud.pill(chip, member, "fffaf0", "583e2d")
			_members.add_child(chip)
		_member_signature = str(members)
		_hud._sheet_height = -1.0
	_members.visible = not members.is_empty()
	var gate := int(info.get("unlock_revenue", 0))
	var revenue := int(_view.sim.revenue)
	var error := String(info.get("unlock_error", ""))
	_condition.visible = gate > 0
	_condition_text.text = "条件：营业额达到 %d" % gate
	_condition_value.text = "%d / %d" % [mini(revenue, gate), gate]
	_condition_bar.value = clampf(float(revenue) / maxf(1.0, float(gate)), 0, 1)
	var cost := int(info.get("unlock_cost", 0))
	if error.is_empty():
		unlock_button.text = "解锁 · %d 金币" % cost
	elif gate > 0 and revenue < gate and error.begins_with("营业额"):
		unlock_button.text = "还差 %d 营业额 · %d 金币" % [gate - revenue, cost]
	elif error.begins_with("金币不足"):
		unlock_button.text = "金币不足 · %d 金币" % cost
	else:
		unlock_button.text = error
	unlock_button.disabled = not error.is_empty()
