extends Button
## A locked machine spot: no machine art, only a dashed outline on the floor.
## Tapping it opens the unlock panel; a red up-arrow shows once the player can pay for it.

const LINE := Color(0.36, 0.25, 0.18, 0.8)
const TEXT := Color("5a4030")
const FILL := Color(1, 1, 1, 0.4)
const BADGE := Color("e5483b")
const BADGE_RADIUS := 17.0
var can_unlock := false:
	set(value):
		if value != can_unlock:
			can_unlock = value
			queue_redraw()


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	# The fill is a stylebox so the price text is drawn over it; _draw adds the dashes on top.
	var fill := StyleBoxFlat.new()
	fill.bg_color = FILL
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, fill)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, TEXT)


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size).grow(-2)
	var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], LINE, 3.0, 12.0)
	if not can_unlock:
		return
	var center := Vector2(box.end.x - 4, box.position.y + 4)
	draw_circle(center, BADGE_RADIUS + 2, Color.WHITE)
	draw_circle(center, BADGE_RADIUS, BADGE)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -11), center + Vector2(9, -1), center + Vector2(-9, -1)]), Color.WHITE)
	draw_rect(Rect2(center + Vector2(-4, -2), Vector2(8, 11)), Color.WHITE)
