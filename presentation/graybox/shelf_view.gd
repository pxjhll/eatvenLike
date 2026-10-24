extends Node2D

const Assets := preload("res://presentation/graybox/assets.gd")
var stock := {}
var capacity := 1
var _font: Font


func _init() -> void:
	_font = load("res://art/ui/graybox_font.ttf")


func _draw() -> void:
	draw_texture(Assets.texture("res://art/machine/mach_rack.png"), Vector2(-64, -160))
	var count := SaveUtil.total(stock)
	var item_id: String = stock.keys()[0] if not stock.is_empty() else "bread"
	for i in mini(count, 8):
		draw_texture_rect(Assets.item(item_id), Rect2(-43 + (i % 3) * 27, -126 + (i / 3) * 33, 28, 28), false)
	var color := Color("a78450") if count == 0 else Color("6e9988")
	draw_string(_font, Vector2(-47, 9), "备料架  %d/%d" % [count, capacity], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("42565c"))
	if count == 0:
		draw_circle(Vector2(0, -80), 15, Color("f5ecd8"))
		draw_arc(Vector2(0, -79), 10, 0, PI, 16, color, 2, true)
		draw_line(Vector2(-10, -81), Vector2(10, -81), color, 2, true)
