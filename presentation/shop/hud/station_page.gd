extends VBoxContainer
## 机器面板（HUD 组件，§6.2.1）：面板由“段”拼成。ShopView.station(id) 告诉这台机器有哪些段
## （unlock 解锁、track 升级轨、materials 物料、seats 座位、flyer 传单），每一段是一个注册进来的小组件。
## 新玩法加一种段：register_section(段 id, 脚本) —— 脚本是一个 Control，有 setup(page) 和 refresh(card)。

const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const Icons := preload("res://presentation/ui/reference_icons.gd")
const Sections := preload("res://presentation/shop/hud/station_sections.gd")

## 升级种类的默认说法（店铺数据 track_kind_<种类> 可以改）
const KIND_LABELS := {"capacity": "产能升级", "price": "售价升级", "both": "产能售价升级", "menu": "开新口味"}

var station_id := ""
var _view: Node2D
var _hud: Control
## 段 id → 脚本（按注册顺序排在面板里）
var _section_scripts := {}
var _sections := {}
var _order: Array[String] = []

## 引导和测试要点的按钮
var unlock_button: Button:
	get: return _sections.unlock.unlock_button if _sections.has("unlock") else null
var upgrade_button: Button:
	get: return _sections.track.upgrade_button if _sections.has("track") else null
var material_buttons: Dictionary:
	get: return _sections.materials.buttons if _sections.has("materials") else {}
var recipe_buttons: Dictionary:
	get: return _sections.recipes.buttons if _sections.has("recipes") else {}
var seat_button: Button:
	get: return _sections.seats.button if _sections.has("seats") else null
var flyer_button: Button:
	get: return _sections.flyer.button if _sections.has("flyer") else null
var flyer_upgrade_button: Button:
	get: return _sections.flyer.upgrade_button if _sections.has("flyer") else null


func setup(view: Node2D, hud: Control) -> void:
	_view = view
	_hud = hud
	add_theme_constant_override("separation", 12)
	for pair in [["track", Sections.TrackSection], ["seats", Sections.SeatsSection], ["flyer", Sections.FlyerSection],
			["materials", Sections.MaterialsSection], ["recipes", Sections.RecipesSection], ["unlock", Sections.UnlockSection]]:
		register_section(pair[0], pair[1])


func register_section(id: String, script: Variant) -> void:
	if _sections.has(id):
		_sections[id].free()
	else:
		_order.append(id)
	_section_scripts[id] = script
	var node: Control = script.new()
	node.name = id.capitalize()
	add_child(node)
	move_child(node, _order.find(id))
	node.setup(self)
	_sections[id] = node


func section(id: String) -> Control:
	return _sections.get(id)


func show_station(id: String) -> void:
	station_id = id
	for node in _sections.values():
		if node.has_method("reset"): node.reset()
	refresh()


func refresh() -> void:
	if _view == null or station_id.is_empty(): return
	var card: Dictionary = _view.view.station(station_id)
	if card.is_empty(): return
	var st: SpecStation = _view.rules.shop.station(station_id)
	var unlocked: bool = card.unlocked
	var level_tag: String = ("Lv%d" % card.level + " " + "★".repeat(int(card.stars))).strip_edges()
	var title: String = st.params.get("panel_title", card.name)
	if not unlocked: title = card.unlock.title
	var pill := "" if not card.sections.has("track") and unlocked else (level_tag if unlocked else "未解锁")
	_hud.set_heading(title, pill, not unlocked, "")
	for id in _sections:
		var node: Control = _sections[id]
		node.visible = id in card.sections
		if node.visible: node.refresh(card)
	# 有升级轨：标题旁边写“Lv.2 → Lv.3”，下面一行写这是哪种升级
	var track: Dictionary = card.get("track", {})
	if unlocked and not track.is_empty():
		_sections.track.visible = not String(track.effect).is_empty()
		if _sections.track.visible:
			var kind: String = _view.view.text("track_kind_" + String(track.heading_kind), {}, KIND_LABELS.get(String(track.heading_kind), "设备升级"))
			var next := "Lv.%d → Lv.%d" % [int(card.level), int(card.level) + 1] if int(track.cost) >= 0 else "满级"
			_hud.set_heading(title, next, false, kind)
	var icon: TextureRect = _hud.heading_icon()
	icon.texture = Icons.texture(String(card.icon) if unlocked else "lock")
	icon.visible = true
	icon.custom_minimum_size = Vector2(84, 70) if card.sections.has("track") else Vector2(42, 42)
	_hud.get_node("Shade").color.a = 0.0 if unlocked else 0.34


# ---------- 各段共用的小零件 ----------

func hud() -> Control:
	return _hud


func view_node() -> Node2D:
	return _view


func image(parent: Node, key: String, extent: float) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = Icons.texture(key)
	picture.custom_minimum_size = Vector2(extent, extent)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	return picture


func skin(button: Button, kind: String) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, ReferenceTheme.style(kind, 13, state))


func buy_button(parent: Node, action: Callable) -> Button:
	var button: Button = _hud._action(parent, "", action)
	button.custom_minimum_size = Vector2(170, 54)
	button.add_theme_font_size_override("font_size", 21)
	skin(button, "gold")
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button


func copy(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	return column
