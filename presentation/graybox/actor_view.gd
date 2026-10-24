extends Node2D
## Animation follows the snapshot. Render travel never delays business progress.

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
var target := Vector2.ZERO
var working := false
var work_progress := 0.0
var idle := true
var wait_ratio := 0.0
var order_item := ""
var leaving := false
var carry_item := ""
## Held by the player's finger: snapshot targets are ignored until release.
var dragging := false
var sprite: Sprite2D
var _clock := 0.0
var _is_staff := true
var _font: Font


func setup(id: String, staff: bool = true) -> void:
	_is_staff = staff
	sprite = Sprite2D.new()
	var art_id := (id if id in ["rabbit", "bear", "cat"] else "bear") if staff else "customer"
	sprite.texture = Assets.character(art_id)
	sprite.hframes = 10 if staff else 6
	sprite.vframes = 3
	sprite.position = Vector2(0, -48)
	sprite.scale = Vector2.ONE * Layout.CHAR_SCALE
	add_child(sprite)
	_font = load("res://art/ui/graybox_font.ttf")
	if not staff:
		sprite.modulate = [Color("e2efdf"), Color("efe5d0"), Color("d6e2ed")][absi(id.hash()) % 3]


func _process(delta: float) -> void:
	if sprite == null:
		return
	_clock += delta
	var distance := position.distance_to(target)
	var direction := target - position
	if dragging:
		distance = 0.0
	else:
		position = position.move_toward(target, delta * 320.0)
	sprite.scale = Vector2.ONE * Layout.CHAR_SCALE * (1.12 if dragging else 1.0)
	var frame := 0
	var row_index := 0
	if distance > 3:
		frame = 2 + int(_clock * 8) % 4
		row_index = 2 if absf(direction.x) > absf(direction.y) else (1 if direction.y < 0 else 0)
		sprite.flip_h = direction.x < 0 and row_index == 2
	elif working and _is_staff:
		frame = 6 + int(_clock * 8) % 4
	else:
		frame = int(_clock * 2) % 2
	sprite.frame = row_index * sprite.hframes + frame
	queue_redraw()
	if leaving and distance < 5:
		queue_free()


func _draw() -> void:
	if sprite == null:
		return
	if not order_item.is_empty() and not leaving:
		draw_style_box(_bubble(), Rect2(-23, -131, 46, 38))
		draw_texture_rect(Assets.item(order_item), Rect2(-15, -128, 30, 30), false)
		if wait_ratio > 0.5:
			draw_arc(Vector2(0, -113), 24, -PI/2, -PI/2 + TAU * minf(wait_ratio, 1.0), 28, Color("c8815a"), 3, true)
	elif _is_staff and idle and position.distance_to(target) < 4:
		draw_string(_font, Vector2(15, -93), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("91a4a7"))
	if _is_staff and not carry_item.is_empty():
		draw_texture_rect(Assets.item(carry_item), Rect2(-12, -52, 24, 24), false)
	if _is_staff and working and not dragging:
		draw_arc(Vector2(0, -5), 15, -PI/2, -PI/2 + TAU * clampf(work_progress, 0.0, 1.0), 24, Color("7fae98"), 3, true)


func hit(at: Vector2) -> bool:
	return Rect2(position + Vector2(-30, -100), Vector2(60, 100)).has_point(at)


func _bubble() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff8e8")
	style.border_color = Color("c9d3cd")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	return style
