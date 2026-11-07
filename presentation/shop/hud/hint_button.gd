extends Button
## 瓶颈提示（HUD 槽位组件，§3.10）：顶栏下面一个小按钮，“红茶排队 · 升级煮茶机 ›”，点了去能解决的地方。

const Icons := preload("res://presentation/ui/reference_icons.gd")

var _view: Node2D
var _hud: Control


func setup(view: Node2D, hud: Control) -> void:
	_view = view
	_hud = hud
	name = "BottleneckHint"
	custom_minimum_size = Vector2(332, 48)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_theme_font_size_override("font_size", 21)
	add_theme_constant_override("icon_max_width", 29)
	expand_icon = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	hud._button_style(self, "cream", 18)
	hud.bind_action(self, _go)
	hide()


func _go() -> void:
	var target: String = _view.view.bottleneck().get("target", "")
	if target.begins_with("staff"): _hud.open_page("staff")
	elif not target.is_empty(): _hud.open_station(target)


func refresh() -> void:
	var hint: Dictionary = _view.view.bottleneck()
	visible = not hint.is_empty()
	if hint.is_empty(): return
	text = String(hint.short).replace("排长队", "排队") + " ›"
	var dish := ""
	for d in _view.rules.shop.dishes:
		if d.display_name == hint.drink: dish = d.id
	icon = Icons.texture("drink_" + dish if not dish.is_empty() else "goals")
