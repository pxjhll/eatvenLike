extends Node2D

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
var points := PackedVector2Array()
var data := {}
var length_cells := 1.0
var _clock := 0.0


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _draw() -> void:
	if points.size() < 2:
		return
	var connected: bool = data.get("connected", true)
	var color := Color("91a6a8") if connected else Color("bdc8c4")
	var shadow_points := points.duplicate()
	for i in shadow_points.size():
		shadow_points[i] += Vector2(0, 4)
	draw_polyline(shadow_points, Color("c1cec8"), 29, true)
	draw_polyline(points, color, 24, true)
	draw_polyline(points, Color("c8d6d3") if connected else Color("dce3db"), 16, true)
	for i in points.size() - 1:
		var direction := (points[i + 1] - points[i]).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var length := points[i].distance_to(points[i + 1])
		var offset := fmod(_clock * 20, 28) if connected else 0.0
		for j in int(length / 28):
			var at := points[i] + direction * (j * 28 + offset)
			if at.distance_to(points[i]) < length - 5:
				draw_polyline(PackedVector2Array([at - direction * 4 + normal * 4, at, at - direction * 4 - normal * 4]), Color("7f9797"), 2, true)
	for item in data.get("items", []):
		var at := Layout.along(points, float(item.pos) / maxf(length_cells, 0.01))
		draw_texture_rect(Assets.item(item.item), Rect2(at - Vector2(18, 30), Vector2(36, 36)), false)
