extends VBoxContainer
## 员工页（HUD 组件）：招人、名册卡片、选中员工的属性、派遣 / 收回、各区升级。
## 也管店铺页底部的“选中员工”小条。数字和文案都来自 ShopView。

const Icons := preload("res://presentation/ui/reference_icons.gd")
const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const Characters := preload("res://presentation/characters/character_library.gd")
## 属性条按满培养能到的最大值来画
const STAT_MAX := {"walk": 220.0, "carry": 6.0, "work": 3.0}
const STATS := [["walk", "移速"], ["carry", "搬量"], ["work", "操作"]]

var always_refresh := true
var _view: Node2D
var _hud: Control
var hire_button: Button
var deploy_button: Button
## 每个分区一个升级按钮：zone → Button（不分区的店只有一个“培养”）
var upgrade_buttons := {}
var staff_preview_button: Button
var _recruit_label: Label
var _recruit_portrait: TextureRect
var _cards: GridContainer
var _titles: Array[Label] = []
var _tags: Array[Label] = []
var _levels: Array[Label] = []
var _portraits: Array[TextureRect] = []
var _signature := ""
var _styled := -1
var _selected_portrait: TextureRect
var _selected_name: Label
var _selected_role: Label
var _selected_doing: Label
var _bars := {}
var _numbers := {}


func setup(view: Node2D, hud: Control) -> void:
	_view = view
	_hud = hud
	add_theme_constant_override("separation", 16)
	var recruit: VBoxContainer = hud._card(self)
	var recruit_line: HBoxContainer = hud._row(recruit, 12)
	_recruit_portrait = hud._portrait(recruit_line, "raccoon", 96)
	_recruit_label = hud._text(recruit_line, "", 24)
	_recruit_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hire_button = hud._action(recruit_line, "招一位", view.hire_worker)
	hire_button.custom_minimum_size = Vector2(204, 54)
	hire_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hud._button_style(hire_button, "gold")
	_cards = GridContainer.new()
	_cards.columns = 3
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)
	var details: VBoxContainer = hud._card(self)
	var detail_row: HBoxContainer = hud._row(details, 18)
	_selected_portrait = hud._portrait(detail_row, "cat", 172)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 7)
	detail_row.add_child(body)
	var heading: HBoxContainer = hud._row(body, 10)
	_selected_name = hud._nowrap(hud._text(heading, "", 26))
	_selected_role = hud._nowrap(hud._text(heading, "", 17))
	_selected_role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_selected_doing = hud._text(body, "", 17, true)
	for stat in STATS:
		var line: HBoxContainer = hud._row(body, 10)
		var caption: Label = hud._nowrap(hud._text(line, stat[1], 22))
		caption.custom_minimum_size.x = 52
		_bars[stat[0]] = hud._bar(line, 18)
		_numbers[stat[0]] = hud._nowrap(hud._text(line, "", 17))
		_numbers[stat[0]].size_flags_horizontal = Control.SIZE_SHRINK_END
		_numbers[stat[0]].custom_minimum_size.x = 34
		_numbers[stat[0]].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var actions: HBoxContainer = hud._row(self, 9)
	deploy_button = hud._action(actions, "派到店内", view.toggle_deployment)
	var zones: Array = view.rules.shop.staff.zones
	for zone in (zones if not zones.is_empty() else [""]):
		var button: Button = hud._action(actions, "", view.buy_staff_upgrade.bind(zone))
		upgrade_buttons[zone] = button
		button.visible = view.rules.track_of("staff/" + zone) != null
	staff_preview_button = hud._action(actions, "查看角色动作", func() -> void:
		for worker in view.all_staff():
			if int(worker.id) == view.selected_worker:
				hud.page_node("characters").select(String(worker.kind))
				hud.open_page("characters")
				break)
	for button in [deploy_button, staff_preview_button] + upgrade_buttons.values():
		var gold: bool = button in upgrade_buttons.values()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 64
		button.add_theme_font_size_override("font_size", 18 if gold else 21)
		button.add_theme_constant_override("icon_max_width", 17)
		button.add_theme_constant_override("h_separation", 3)
		hud._button_style(button, "gold" if gold else "cream", 14)
	# 手机没有悬停，拖人的规则直接写在这里
	var hint: String = view.view.text("drag_hint")
	if not hint.is_empty():
		var label: Label = hud._text(self, hint, 19, true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _rebuild() -> void:
	for child in _cards.get_children(): child.free()
	_view._staff_cards.clear()
	_titles.clear()
	_tags.clear()
	_levels.clear()
	_portraits.clear()
	for worker in _view.all_staff():
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 170)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		card.set_meta("worker_id", int(worker.id))
		card.pressed.connect(func() -> void: _view.selected_worker = int(worker.id); _hud.refresh())
		_cards.add_child(card)
		var content := HBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 6
		content.offset_right = -6
		content.offset_top = 10
		content.offset_bottom = -10
		content.add_theme_constant_override("separation", 4)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(content)
		_portraits.append(_hud._portrait(content, String(worker.kind), 112))
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation", 8)
		content.add_child(body)
		var label: Label = _hud._text(body, "", 23)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_titles.append(label)
		var level := Label.new()
		level.add_theme_font_size_override("font_size", 17)
		level.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(level)
		_levels.append(level)
		var tag_row := HBoxContainer.new()
		tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(tag_row)
		var tag := Label.new()
		tag.add_theme_font_size_override("font_size", 17)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_row.add_child(tag)
		_tags.append(tag)
		var badge := TextureRect.new()
		badge.name = "SelectedBadge"
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.texture = Icons.texture("selected_check")
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -42
		badge.offset_top = -10
		badge.offset_right = 2
		badge.offset_bottom = 34
		_view._staff_cards.append(card)
	_signature = _roster_signature()
	_styled = -1
	_hud.relayout()


func _roster_signature() -> String:
	return str(_view.all_staff().map(func(worker: Dictionary) -> int: return int(worker.id)))


func _status(worker: Dictionary) -> Array:
	if not _view.staff_is_deployed(int(worker.id)):
		return ["待派遣", "e5dfd2", "5d5548"]
	# 岗位叫什么：texts["post_<岗位>"]（流动 = post_）；坐班岗位用深一点的底色
	var post := String(worker.post)
	var name: String = _view.view.text("post_" + post, {}, _view.view.station_name(post) if not post.is_empty() else "流动")
	var seated: bool = not post.is_empty() and post != _view.rules.counter_id
	return [name, "f3dfb8" if seated else "f9e8cc", "6b4a1c" if seated else "784a29"]


## 同一种动物有两位：狐狸 1、狐狸 2
func staff_name(worker: Dictionary, roster: Array) -> String:
	var same: Array = roster.filter(func(other: Dictionary) -> bool: return other.kind == worker.kind)
	var name: String = Characters.NAMES.get(worker.kind, worker.name)
	if same.size() < 2: return name
	return "%s %d" % [name, same.find(worker) + 1]


func has_staff_room() -> bool:
	return _view.rules.workers.size() < _view.rules.staff_slots()


## 员工页有能买的（员工页签上的红 ↑）
func affordable() -> bool:
	var rules: ShopRules = _view.rules
	if rules.hire_cost() >= 0 and rules.gold >= rules.hire_cost() and has_staff_room(): return true
	for zone in upgrade_buttons:
		var info: Dictionary = _view.view.staff_track(zone)
		if not info.is_empty() and int(info.cost) >= 0 and rules.gold >= int(info.cost): return true
	return false


func refresh() -> void:
	var rules: ShopRules = _view.rules
	var view: ShopView = _view.view
	var roster: Array = _view.all_staff()
	if _signature != _roster_signature(): _rebuild()
	var selection: Control = _hud.get_node("%Selection")
	if roster.is_empty():
		selection.visible = false
		return
	var selected: Dictionary = roster[0]
	for i in roster.size():
		var worker: Dictionary = roster[i]
		var is_selected: bool = int(worker.id) == _view.selected_worker
		var status := _status(worker)
		_titles[i].text = staff_name(worker, roster)
		_levels[i].text = "Lv%d" % int(worker.get("level", 1))
		_hud.pill(_tags[i], status[0], status[1], status[2])
		_portraits[i].modulate = Color.WHITE if _view.staff_is_deployed(int(worker.id)) else Color(1, 1, 1, 0.55)
		if _styled != _view.selected_worker:
			for state in ["normal", "hover", "pressed", "disabled", "focus"]:
				var skin_state: String = "selected" if is_selected and state in ["normal", "hover"] else state
				_view._staff_cards[i].add_theme_stylebox_override(state, ReferenceTheme.style("card", 18, skin_state))
		_view._staff_cards[i].get_node("SelectedBadge").visible = is_selected
		if is_selected: selected = worker
	_styled = _view.selected_worker
	var card := view.worker_card(selected)
	_selected_name.text = staff_name(selected, roster)
	_selected_portrait.texture = _hud.portrait_texture(String(selected.kind))
	_hud.pill(_selected_role, card.role, "ead4b2", "583e2d")
	_selected_doing.text = "正在：" + card.task if card.deployed else "在名册中待派遣"
	for stat in _bars:
		_bars[stat].value = clampf(float(card.stats.get(stat, 0.0)) / STAT_MAX[stat], 0.04, 1.0)
	_numbers.walk.text = str(int(card.stats.get("walk", 0.0)))
	_numbers.carry.text = str(int(card.stats.get("carry", 0.0)))
	_numbers.work.text = "%.1f" % float(card.stats.get("work", 0.0))
	deploy_button.visible = rules.shop.staff.can_drag
	deploy_button.text = "收回到名册" if card.deployed else "派到店内"
	for zone in upgrade_buttons:
		var button: Button = upgrade_buttons[zone]
		var info: Dictionary = view.staff_track(zone)
		if info.is_empty(): continue
		button.text = ("%s升级已买完" % info.title) if int(info.cost) < 0 else "%s %d/%d · %d 金币\n%s" % [info.title, int(info.bought) + 1, int(info.total), int(info.cost), info.name]
		button.disabled = int(info.cost) < 0 or rules.gold < int(info.cost)
	var room := has_staff_room()
	hire_button.disabled = rules.hire_cost() < 0 or rules.gold < rules.hire_cost() or not room
	hire_button.text = "暂无空位" if not room else "招募 · %d 金币" % rules.hire_cost()
	var next_kind := rules.next_hire_kind()
	_recruit_portrait.texture = _hud.portrait_texture(next_kind)
	var kind := rules._kind(next_kind)
	_recruit_label.text = "%s · %s" % [Characters.NAMES.get(next_kind, kind.display_name), kind.role] + ("\n招来直接上岗" if room else "\n解锁新设备后有更多空位")
	selection.visible = _hud.show_selection and _hud.page == "shop"
	selection.get_node("Row/Avatar").texture = _hud.portrait_texture(String(selected.kind))
	selection.get_node("Row/Summary").text = "%s · Lv%d\n%s" % [staff_name(selected, roster), int(selected.get("level", 1)), card.task]
	if _hud.page == "staff":
		var slots := view.slots()
		_hud.set_subtitle(view.text("staff_slots" if slots.has("front") else "staff_slots_all", slots, "店内 %d / %d" % [slots.used, slots.all]))
