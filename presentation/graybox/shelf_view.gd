extends Node2D

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
var stock := {}
## Finished goods on the menu; each has its own capacity on the rack.
var items := ["bread"]
## item_id -> display name, from the shop's ItemDefs
var item_names := {}
var capacity := 1
var _font: Font


func _init() -> void:
	_font = load("res://art/ui/graybox_font.ttf")


func _draw() -> void:
	var texture := Assets.texture("res://art/machine/mach_rack.png")
	var size := texture.get_size() * Layout.RACK_SCALE
	draw_texture_rect(texture, Rect2(Vector2(-size.x / 2.0, -size.y), size), false)
	var count := SaveUtil.total(stock)
	var shown := []
	for item_id in items:
		for i in int(stock.get(item_id, 0)):
			shown.append(item_id)
	for i in mini(shown.size(), 9):
		draw_texture_rect(Assets.item(shown[i]), Rect2(-33 + (i % 3) * 22, -100 + (i / 3) * 26, 22, 22), false)
	var empty := false
	var parts := []
	for item_id in items:
		var n := int(stock.get(item_id, 0))
		empty = empty or n == 0
		parts.append(str(n) if items.size() == 1 else "%s%d" % [item_names.get(item_id, item_id), n])
	var full := false
	for item_id in items:
		full = full or int(stock.get(item_id, 0)) >= capacity
	var color := Color("e53935") if empty or full else Color("5d6f72")
	var text := "备料架 %s/%d" % [parts[0], capacity] if items.size() == 1 else "备料架 " + " ".join(parts)
	var text_width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(_font, Vector2(-text_width / 2.0, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	if count == 0:
		draw_circle(Vector2(0, -64), 13, Color("f5ecd8"))
		draw_arc(Vector2(0, -63), 8, 0, PI, 16, color, 2, true)
		draw_line(Vector2(-8, -65), Vector2(8, -65), color, 2, true)
