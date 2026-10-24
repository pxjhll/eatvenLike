extends Node2D

const Assets := preload("res://presentation/graybox/assets.gd")
const State := preload("res://presentation/graybox/view_state.gd")
var definition: StationDef
var row := {}
var selected := false
var sprite: Sprite2D
var _font: Font


func setup(def: StationDef) -> void:
	definition = def
	sprite = Sprite2D.new()
	sprite.texture = Assets.machine(def)
	sprite.centered = false
	sprite.position = Vector2(-sprite.texture.get_width() / 2.0, -sprite.texture.get_height())
	add_child(sprite)
	_font = load("res://art/ui/graybox_font.ttf")


func display(data: Dictionary) -> void:
	row = data
	sprite.modulate = Color(1, 1, 1, 0.3) if row.status != StationState.Status.ACTIVE else Color.WHITE
	queue_redraw()


func hit(point: Vector2) -> bool:
	return Rect2(position + sprite.position, sprite.texture.get_size()).has_point(point)


func _draw() -> void:
	if row.is_empty():
		return
	var state: Dictionary = State.station(row, definition)
	if selected:
		draw_arc(Vector2(0, -6), 64, 0, TAU, 40, Color("e6bb60"), 3, true)
	var top := -float(sprite.texture.get_height()) - 10.0
	if row.status != StationState.Status.ACTIVE:
		draw_texture_rect(Assets.icon("lock"), Rect2(-17, -94, 34, 34), false)
		draw_string(_font, Vector2(-32, -31), "%d 金币" % definition.parallel_cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("65777c"))
	else:
		if state.kind == "working":
			if definition.mode == StationDef.Mode.COOP and row.phase == StationState.Phase.PROCESSING:
				draw_rect(Rect2(-32, -76, 63, 33), Color(1, 0.68, 0.27, 0.22))
			var amount: float = row.progress
			if row.get("staff_working", false):
				amount = row.get("manual_progress", 0.0)
			if definition.mode == StationDef.Mode.SUPPLY:
				amount = fmod(float(row.supply_timer) / maxf(definition.supply_interval, 0.01), 1.0)
			draw_line(Vector2(-32, 5), Vector2(32, 5), Color("d4ded8"), 6, true)
			draw_line(Vector2(-32, 5), Vector2(-32 + 64 * amount, 5), Color("77a995"), 6, true)
		var indices := {"input": 0, "output": 0}
		for stack in State.buffers(row):
			for i in mini(stack.count, 3):
				var index: int = indices[stack.side]
				if index >= 3:
					break
				var x: float = (-66 if stack.side == "input" else 18) + index * 13
				draw_texture_rect(Assets.item(stack.item), Rect2(x, -16 - (index % 2) * 4, 28, 28), false)
				indices[stack.side] = index + 1
		draw_circle(Vector2(44, top + 5), 5, state.color)
		draw_string(_font, Vector2(-44, top + 10), state.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, state.color)
	draw_string(_font, Vector2(-56, 32), definition.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("42565c"))
	if row.status == StationState.Status.ACTIVE:
		draw_string(_font, Vector2(-56, 51), State.mode_label(definition) + " · Lv" + str(row.level), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("819292"))
