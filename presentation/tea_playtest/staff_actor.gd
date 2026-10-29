extends Node2D
## Existing reference poses animated as movable actors; feet remain the Y-sort anchor.

## The view is orthographic, so a cup is the same size on a belt, a shelf or in a paw.
const CUP_HEIGHT := 52.0

const TASKS := {
	"idle": "待命",
	"take_post": "前往坐班", "move_free": "恢复流动",
	"brew_start": "人工投料", "brew_take": "取出茶汤",
	"supply": "补原料", "load_boil": "投料煮茶", "unload_boil": "取茶汤",
	"transfer_to_topping": "送去加料", "topping": "手工加料",
	"load_seal_belt": "放上传送带", "carry_to_seal": "送去封口",
	"load_shelf_belt": "放上传送带", "carry_to_shelf": "成品上架", "serve": "取杯送餐",
}
var body := Sprite2D.new()
var carried := Sprite2D.new()
var amount := Label.new()
var task := Label.new()
var selected := false
var _last_pos := Vector2.ZERO
var _base_scale := Vector2.ONE
var _font: Font
var _art := ""
var _height := 128.0
## A customer's order bubble: the drink they want and how much patience is left (-1 = no limit).
var _order_item := ""
var _patience := -1.0
var _order_cup := Sprite2D.new()
var _bubble := StyleBoxFlat.new()


func setup(art_id: String, font: Font, height := 128.0) -> void:
	_font = font
	_art = art_id
	_height = height
	body.texture = load("res://art/reference/" + art_id + ".png")
	_base_scale = Vector2.ONE * height / body.texture.get_height()
	body.scale = _base_scale
	body.centered = false
	body.position = Vector2(-body.texture.get_width() * _base_scale.x / 2.0, -height)
	add_child(body)
	carried.centered = false
	carried.visible = false
	add_child(carried)
	amount.position = Vector2(38, -59)
	amount.add_theme_font_override("font", font)
	amount.add_theme_font_size_override("font_size", 17)
	amount.add_theme_color_override("font_color", Color("fff5d8"))
	amount.add_theme_color_override("font_outline_color", Color("573b2b"))
	amount.add_theme_constant_override("outline_size", 4)
	add_child(amount)
	task.position = Vector2(-78, -height - 28)
	task.size.x = 156
	task.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task.add_theme_font_override("font", font)
	task.add_theme_font_size_override("font_size", 16)
	task.add_theme_color_override("font_color", Color("4e3425"))
	task.add_theme_color_override("font_outline_color", Color("fff1d8"))
	task.add_theme_constant_override("outline_size", 5)
	add_child(task)
	_order_cup.centered = false
	_order_cup.visible = false
	add_child(_order_cup)
	_bubble.bg_color = Color("fff8ec")
	_bubble.border_color = Color("b38c62")
	_bubble.set_border_width_all(2)
	_bubble.set_corner_radius_all(14)


func show_order(item: String, patience: float) -> void:
	_order_item = item
	_patience = patience
	task.visible = false
	var texture: Texture2D = load("res://art/reference/" + item_asset(item) + ".png")
	_order_cup.texture = texture
	_order_cup.modulate = item_color(item)
	_order_cup.scale = Vector2.ONE * 36.0 / texture.get_height()
	_order_cup.position = Vector2(-40, -_height - 58)
	_order_cup.visible = true


func display(worker: Dictionary, clock: float) -> void:
	position = worker.pos
	var movement: Vector2 = position - _last_pos
	if absf(movement.x) > 0.1:
		body.flip_h = movement.x < 0
	var walking: bool = worker.get("walking", false)
	var bob := sin(clock * 15.0) * 2.5 if walking else 0.0
	var working: bool = worker.get("phase", "idle") in ["work", "pickup", "dropoff"]
	body.position.y = -body.texture.get_height() * _base_scale.y + bob
	body.rotation = sin(clock * 10.0) * 0.025 if working else 0.0
	var label: String = worker.get("task_label", "")
	task.text = TASKS.get(label, "待命" if label.is_empty() else label)
	var item: String = worker.get("carry_item", "")
	var count: int = worker.get("carry_count", 0)
	carried.visible = not item.is_empty() and count > 0
	amount.visible = carried.visible and count > 1
	amount.text = "×%d" % count
	if carried.visible:
		var asset := item_asset(item)
		var texture: Texture2D = load("res://art/reference/" + asset + ".png")
		carried.texture = texture
		carried.modulate = item_color(item)
		carried.scale = Vector2.ONE * CUP_HEIGHT / texture.get_height()
		carried.position = Vector2(22, -78 + bob)
	_last_pos = position
	queue_redraw()


static func item_asset(item: String) -> String:
	if item == "raw": return "tea_tin"
	if item == "lemonade": return "fruit_tea"
	if item in ["tea", "milk_tea", "plain_milk_tea", "coconut_milk_tea", "taro_milk_tea"]: return "cream_tea"
	return "pearl_tea"


static func item_color(item: String) -> Color:
	return {"coconut_milk_tea": Color("fff8df"), "redbean_milk_tea": Color("ffd8cf"), "taro_milk_tea": Color("e1d0ff")}.get(item, Color.WHITE)


func _draw() -> void:
	draw_set_transform(Vector2(0, 1), 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, 25, Color(0.24, 0.14, 0.07, 0.18))
	if selected:
		draw_arc(Vector2.ZERO, 31, 0, TAU, 40, Color("e6b94f"), 6, true)
	draw_set_transform(Vector2.ZERO)
	if _order_item.is_empty():
		return
	var top := -_height - 64.0
	draw_style_box(_bubble, Rect2(-48, top, 96, 48))
	draw_colored_polygon(PackedVector2Array([Vector2(-8, top + 46), Vector2(8, top + 46), Vector2(0, top + 58)]), _bubble.bg_color)
	if _patience >= 0:
		var fill := clampf(_patience, 0.0, 1.0)
		var color := Color("6b8f4e") if fill > 0.6 else Color("d08a2e") if fill > 0.3 else Color("b4482f")
		draw_rect(Rect2(-4, top + 19, 42, 10), Color("efe3cc"))
		draw_rect(Rect2(-4, top + 19, 42 * fill, 10), color)
