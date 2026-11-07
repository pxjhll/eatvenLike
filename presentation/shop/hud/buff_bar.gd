extends HBoxContainer
## 进行中加成（HUD 槽位组件，§6.2.1）：加成栈里带到期时间的每一条显示一个小图标和剩余秒数。
## 图标：这条加成来自的奇遇的 icon（SpecEvent.icon），没有就按加成种类（texts["buff_icon_<种类>"]）。

const Icons := preload("res://presentation/ui/reference_icons.gd")
const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")

var _view: Node2D
var _hud: Control
var _chips: Array[PanelContainer] = []


func setup(view: Node2D, hud: Control) -> void:
	_view = view
	_hud = hud
	name = "Buffs"
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func refresh() -> void:
	var buffs: Array = _view.view.buffs()
	visible = not buffs.is_empty()
	while _chips.size() < buffs.size(): _chips.append(_chip())
	for i in _chips.size():
		var chip := _chips[i]
		chip.visible = i < buffs.size()
		if not chip.visible: continue
		var buff: Dictionary = buffs[i]
		var view: ShopView = _view.view
		var key := view.buff_icon(buff)
		chip.get_node("Row/Icon").texture = Icons.texture(key)
		chip.get_node("Row/Left").text = "%d 秒" % ceili(float(buff.left))
		chip.tooltip_text = view.buff_name(buff)
		chip.set_meta("buff", buff.id)


func _chip() -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", ReferenceTheme.style("pill", 12))
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(chip)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var left: Label = _hud._nowrap(_hud._text(row, "", 18))
	left.name = "Left"
	return chip
