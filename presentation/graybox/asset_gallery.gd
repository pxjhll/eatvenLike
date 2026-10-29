extends Node2D
## Editor/QA preview only; does not create a simulation or imply owned content.

const Assets := preload("res://presentation/graybox/assets.gd")
var _font: Font


func _ready() -> void:
	_font = load("res://art/ui/graybox_font.ttf")
	queue_redraw()
	var kinds := ["rabbit", "bear", "cat", "customer"]
	for i in kinds.size():
		var actor := preload("res://presentation/graybox/actor_view.gd").new()
		actor.setup(kinds[i], kinds[i] != "customer")
		actor.position = Vector2(105 + i * 165, 645)
		actor.target = actor.position
		actor.working = true
		actor.idle = false
		add_child(actor)


func _draw() -> void:
	if _font == null:
		return
	draw_string(_font, Vector2(44, 65), "灰盒资源预览", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("42565c"))
	var names := ["面粉箱", "面团台", "烤炉", "切片机", "备料架", "销售台"]
	var paths := ["mach_flour_bin", "mach_dough_table", "mach_oven", "mach_slicer", "mach_rack", "mach_counter"]
	for i in paths.size():
		var point := Vector2(55 + (i % 3) * 220, 145 + (i / 3) * 220)
		var texture := Assets.texture("res://art/machine/" + paths[i] + ".png")
		var dimensions := texture.get_size() * minf(150.0 / texture.get_width(), 150.0 / texture.get_height())
		draw_texture_rect(texture, Rect2(point + Vector2((150 - dimensions.x) / 2, 150 - dimensions.y), dimensions), false)
		draw_string(_font, point + Vector2(20, 179), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("526b65"))
	var actor_names := ["兔子", "小熊", "小猫", "顾客"]
	for i in actor_names.size():
		draw_string(_font, Vector2(82 + i * 165, 689), actor_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("526b65"))
	for i in 4:
		draw_texture_rect(Assets.item(["flour", "dough", "bread", "toast"][i]), Rect2(75 + i * 165, 740, 72, 72), false)
	draw_texture_rect(Assets.texture("res://art/ui/ui_icons.png"), Rect2(230, 865, 256, 256), false)
