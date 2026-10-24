extends Node2D

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
var stock := {}
var capacity := 1
var _font: Font


func _init() -> void:
	_font = load("res://art/ui/graybox_font.ttf")


func _draw() -> void:
	var texture := Assets.texture("res://art/machine/mach_rack.png")
	var size := texture.get_size() * Layout.RACK_SCALE
	draw_texture_rect(texture, Rect2(Vector2(-size.x / 2.0, -size.y), size), false)
	var count := SaveUtil.total(stock)
	var item_id: String = stock.keys()[0] if not stock.is_empty() else "bread"
	for i in mini(count, 9):
		draw_texture_rect(Assets.item(item_id), Rect2(-33 + (i % 3) * 22, -100 + (i / 3) * 26, 22, 22), false)
	var full := count >= capacity
	var color := Color("e53935") if count == 0 or full else Color("5d6f72")
	draw_string(_font, Vector2(-size.x / 2.0, 22), "备料架 %d/%d" % [count, capacity], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	if count == 0:
		draw_circle(Vector2(0, -64), 13, Color("f5ecd8"))
		draw_arc(Vector2(0, -63), 8, 0, PI, 16, color, 2, true)
		draw_line(Vector2(-8, -65), Vector2(8, -65), color, 2, true)
