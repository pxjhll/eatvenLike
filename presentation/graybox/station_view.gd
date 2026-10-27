extends Node2D

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
const State := preload("res://presentation/graybox/view_state.gd")
var definition: StationDef
var row := {}
var selected := false
## 前厅位点的解锁价（价格牌）；-1 = 用 StationDef 上的价格
var unlock_price := -1
var sprite: Sprite2D
var _font: Font
var _counter := false
var _flash := 0.0
var _level := 0


func setup(def: StationDef) -> void:
	definition = def
	_counter = def.owner == StationDef.OwnerSystem.FRONT_HALL and def.mode == StationDef.Mode.MANUAL
	_font = load("res://art/ui/graybox_font.ttf")
	if _counter:
		return
	sprite = Sprite2D.new()
	sprite.texture = Assets.machine(def)
	sprite.centered = false
	sprite.scale = Vector2.ONE * Layout.MACHINE_SCALE
	var size := sprite.texture.get_size() * Layout.MACHINE_SCALE
	sprite.position = Vector2(-size.x / 2.0, -size.y)
	add_child(sprite)


func display(data: Dictionary) -> void:
	if _level > 0 and int(data.level) > _level:
		_flash = 1.0
	_level = int(data.level)
	row = data
	if sprite != null:
		sprite.modulate = Color(1, 1, 1, 0.3) if row.status != StationState.Status.ACTIVE else Color.WHITE
	queue_redraw()


func bounds() -> Rect2:
	if _counter:
		return Rect2(position + Vector2(-Layout.COUNTER_WIDTH / 2.0, -60), Vector2(Layout.COUNTER_WIDTH, 70))
	return Rect2(position + sprite.position, sprite.texture.get_size() * Layout.MACHINE_SCALE)


func hit(point: Vector2) -> bool:
	return bounds().grow(8).has_point(point)


func _process(delta: float) -> void:
	if _flash > 0:
		_flash = maxf(0.0, _flash - delta * 1.6)
		queue_redraw()


func _draw() -> void:
	if _counter:
		_draw_counter()
	if row.is_empty():
		return
	var state: Dictionary = State.station(row, definition)
	var box := bounds()
	box.position -= position
	if selected:
		draw_style_box(_outline(Color("e6bb60")), box.grow(6))
	if _flash > 0:
		draw_circle(box.get_center(), 30 + (1.0 - _flash) * 40, Color(1, 0.86, 0.45, _flash * 0.45))
	var top := box.position.y
	if row.status != StationState.Status.ACTIVE:
		draw_texture_rect(Assets.icon("lock"), Rect2(-14, top + 22, 28, 28), false)
		draw_style_box(_pill(Color("fff8e4")), Rect2(-30, top - 26, 60, 22))
		_text(Vector2(-26, top - 10), "%d" % _price(), 14, Color("8a7139"))
		draw_texture_rect(Assets.icon("coin"), Rect2(10, top - 24, 18, 18), false)
		return
	if not _counter:
		_draw_progress(state)
	if state.kind in ["blocked", "staff", "input"]:
		var width: float = 18.0 + String(state.text).length() * 13.0
		draw_style_box(_pill(Color(state.color, 0.95)), Rect2(-width / 2.0, top - 18, width, 24))
		_text(Vector2(-width / 2.0 + 9, top), state.text, 13, Color.WHITE)
	if not _counter:
		# Name sits below the operating worker's feet so it stays readable while they work.
		var level := "" if int(row.level) <= 1 else "  Lv%d" % row.level
		_text(Vector2(-box.size.x / 2.0, 70), definition.display_name + level, 13, Color("5d6f72"))


func _draw_counter() -> void:
	var w := Layout.COUNTER_WIDTH
	draw_rect(Rect2(-w / 2.0 + 6, 2, w - 4, 10), Color(0.27, 0.33, 0.35, 0.18))
	draw_style_box(_box(Color("9fbfb1"), Color("45545a"), 3), Rect2(-w / 2.0, -26, w, 34))
	draw_style_box(_box(Color("fff4dc"), Color("45545a"), 3), Rect2(-w / 2.0 - 6, -44, w + 12, 22))
	_text(Vector2(w / 2.0 - 84, 2), definition.display_name, 13, Color("3f5557"))


func _draw_progress(state: Dictionary) -> void:
	if state.kind != "working":
		return
	var amount: float = row.progress
	if row.get("staff_working", false):
		amount = row.get("manual_progress", 0.0)
	if definition.mode == StationDef.Mode.SUPPLY:
		amount = fmod(float(row.supply_timer) / maxf(definition.supply_interval, 0.01), 1.0)
	if definition.mode == StationDef.Mode.COOP and row.phase == StationState.Phase.PROCESSING:
		draw_rect(Rect2(-20, -58, 40, 20), Color(1, 0.68, 0.27, 0.22))
	draw_line(Vector2(-26, 50), Vector2(26, 50), Color("d4ded8"), 5, true)
	draw_line(Vector2(-26, 50), Vector2(-26 + 52 * clampf(amount, 0.0, 1.0), 50), Color("77a995"), 5, true)


func _price() -> int:
	if unlock_price >= 0:
		return unlock_price
	return definition.unlock_cost if row.status == StationState.Status.LOCKED else definition.parallel_cost


func _text(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _pill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(11)
	return style


func _outline(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = color
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	return style


func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	return style
