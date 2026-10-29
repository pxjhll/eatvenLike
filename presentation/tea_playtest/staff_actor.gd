extends Node2D
## Existing reference poses animated as movable actors; feet remain the Y-sort anchor.

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


func setup(art_id: String, font: Font, height := 128.0) -> void:
	_font = font
	_art = art_id
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
		var asset := "tea_tin" if item == "raw" else "cream_tea" if item in ["tea", "milk_tea"] else "pearl_tea"
		var texture: Texture2D = load("res://art/reference/" + asset + ".png")
		carried.texture = texture
		carried.scale = Vector2.ONE * 44.0 / texture.get_height()
		carried.position = Vector2(22, -78 + bob)
	_last_pos = position
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, 1), 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, 25, Color(0.24, 0.14, 0.07, 0.18))
	if selected:
		draw_arc(Vector2.ZERO, 31, 0, TAU, 40, Color("e6b94f"), 6, true)
	draw_set_transform(Vector2.ZERO)
