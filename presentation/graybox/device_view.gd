extends Node2D
## 后厨设备：按占地画成方格上的一块，接口画成小箭头，要员工的设备再画出工位格。
## 位置是设备左上角那一格的左上角。布局草稿里的设备也用它画（draft = true）。

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
const State := preload("res://presentation/graybox/view_state.gd")
const MODE_COLORS := [Color("b9d3c6"), Color("e3cfa6"), Color("f0d4b8"), Color("c9d6e8"), Color("d8e3c4")]
var definition: StationDef
var device_id := ""
var cell := Vector2i.ZERO
var row := {}
var selected := false
## 布局草稿里的样子：新放的带价签，放不下的标红
var draft := false
var is_new := false
var invalid := false
var _font: Font
var _flash := 0.0
var _level := 0


func setup(def: StationDef, id: String, at: Vector2i) -> void:
	definition = def
	device_id = id
	place(at)
	_font = load("res://art/ui/graybox_font.ttf")


func place(at: Vector2i) -> void:
	cell = at
	position = Layout.cell_rect(at).position
	queue_redraw()


func display(data: Dictionary) -> void:
	if _level > 0 and int(data.level) > _level:
		_flash = 1.0
	_level = int(data.level)
	row = data
	queue_redraw()


## 本体的屏幕矩形（不含工位格）
func bounds() -> Rect2:
	return Rect2(position, Vector2(definition.footprint) * Layout.CELL)


func hit(point: Vector2) -> bool:
	return bounds().grow(4).has_point(point)


func _process(delta: float) -> void:
	if _flash > 0:
		_flash = maxf(0.0, _flash - delta * 1.6)
		queue_redraw()


func _draw() -> void:
	var size := Vector2(definition.footprint) * Layout.CELL
	var box := Rect2(Vector2(6, 6), size - Vector2(12, 12))
	if definition.needs_staff():
		var work := Rect2(Vector2(definition.work_cell) * Layout.CELL + Vector2(10, 10), Vector2.ONE * (Layout.CELL - 20))
		draw_style_box(_dashed(Color("c39e5c"), Color(1, 0.93, 0.8, 0.5)), work)
		if row.is_empty() or draft:
			_text(work.get_center() + Vector2(-14, 6), "工位", 13, Color("a68b43"))
	var fill: Color = MODE_COLORS[definition.mode]
	if draft:
		fill = Color(fill, 0.8)
	var border := Color("e53935") if invalid else (Color("e6bb60") if selected else Color("6f8584"))
	draw_style_box(_box(fill, border, 4 if selected or invalid else 3), box)
	var texture := Assets.machine(definition)
	var icon := minf(box.size.y - 34, 64)
	draw_texture_rect(texture, Rect2(box.get_center() - Vector2(icon / 2.0, icon / 2.0 + 8), Vector2(icon, icon)), false)
	var level := "" if row.is_empty() or int(row.level) <= 1 else " Lv%d" % row.level
	_text(Vector2(box.position.x + 8, box.end.y - 8), definition.display_name + level, 14, Color("3f5557"))
	for port in definition.ports:
		_draw_port(port)
	if _flash > 0:
		draw_circle(box.get_center(), 30 + (1.0 - _flash) * 40, Color(1, 0.86, 0.45, _flash * 0.45))
	if draft:
		if is_new:
			draw_style_box(_pill(Color("fff8e4")), Rect2(box.end.x - 58, box.position.y - 10, 56, 22))
			_text(Vector2(box.end.x - 52, box.position.y + 7), "%d" % definition.price, 14, Color("8a7139"))
			draw_texture_rect(Assets.icon("coin"), Rect2(box.end.x - 22, box.position.y - 8, 18, 18), false)
		return
	if row.is_empty():
		return
	var state: Dictionary = State.station(row, definition)
	_draw_progress(state, box)
	if state.kind in ["blocked", "staff", "input"]:
		var width: float = 18.0 + String(state.text).length() * 13.0
		var at := Vector2(box.get_center().x - width / 2.0, box.position.y - 12)
		draw_style_box(_pill(Color(state.color, 0.95)), Rect2(at, Vector2(width, 24)))
		_text(at + Vector2(9, 18), state.text, 13, Color.WHITE)


## 接口：入口画朝里的箭头，出口画朝外的箭头，都画在占地的边上
func _draw_port(port: PortDef) -> void:
	var dir := Vector2(PortDef.direction(port.side))
	var center := (Vector2(port.cell) + Vector2(0.5, 0.5)) * Layout.CELL + dir * (Layout.CELL / 2.0 - 6)
	var normal := Vector2(-dir.y, dir.x)
	var tip := dir * 8 if port.kind == PortDef.Kind.OUT else -dir * 8
	var color := Color("4f8a6f") if port.kind == PortDef.Kind.OUT else Color("8a6f4f")
	draw_colored_polygon(PackedVector2Array([center + tip, center - tip + normal * 9, center - tip - normal * 9]), color)


func _draw_progress(state: Dictionary, box: Rect2) -> void:
	if state.kind != "working":
		return
	var amount: float = row.progress
	if row.get("staff_working", false):
		amount = row.get("manual_progress", 0.0)
	if definition.mode == StationDef.Mode.SUPPLY:
		amount = fmod(float(row.supply_timer) / maxf(definition.supply_interval, 0.01), 1.0)
	var y := box.end.y - 30
	draw_line(Vector2(box.position.x + 10, y), Vector2(box.end.x - 10, y), Color("d4ded8"), 5, true)
	draw_line(Vector2(box.position.x + 10, y), Vector2(box.position.x + 10 + (box.size.x - 20) * clampf(amount, 0.0, 1.0), y), Color("77a995"), 5, true)


func _text(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _pill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(11)
	return style


func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(12)
	return style


func _dashed(border: Color, fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
