extends Node2D
## An employee's complete hand is drawn together on the tray, in actor-local units.
const ItemArt := preload("res://game/rules/shop_item_art.gd")
const WOOD := preload("res://art/stirfry/scene/wood_tray.png")
const SURFACE := Rect2(-46, -16, 92, 34)

var _items: Array = []
var _portions: Array[Dictionary] = []

func show_meal(items: Array, item_art: Callable) -> void:
	if items == _items: return
	_items = items.duplicate(true)
	_portions.clear()
	for item in items:
		var look: Dictionary = item_art.call(item.item)
		var portion := {"texture": ItemArt.texture_from_look(look), "tint": look.get("tint", Color.WHITE)}
		for copy in int(item.count):
			_portions.append(portion)
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(WOOD, SURFACE, false)
	var count := _portions.size()
	var columns := maxi(2, ceili(sqrt(count)))
	var rows := ceili(float(count) / columns)
	var column_spacing := 70.0 / columns
	var portion_size := minf(40.0, 84.0 / columns)
	for i in count:
		var row := floori(float(i) / columns)
		var row_size := mini(columns, count - row * columns)
		var x := (i % columns - (row_size - 1) * 0.5) * column_spacing
		var y := 5.0 if rows == 1 else lerpf(-6, 10, float(row) / (rows - 1))
		var look := _portions[i]
		var texture: Texture2D = look.texture
		var size := texture.get_size() * portion_size / maxf(texture.get_width(), texture.get_height())
		draw_texture_rect(texture, Rect2(Vector2(x - size.x * 0.5, y - size.y), size), false, look.tint)
