extends Node2D

const Assets := preload("res://presentation/graybox/assets.gd")
const Layout := preload("res://presentation/graybox/layout.gd")
const JAM_SECONDS := 1.0
var points := PackedVector2Array()
var data := {}
var length_cells := 1.0
var selected := false
var _clock := 0.0
var _head_waiting := 0.0


func _process(delta: float) -> void:
	_clock += delta
	var items: Array = data.get("items", [])
	if not items.is_empty() and float(items[0].pos) >= length_cells - 0.01:
		_head_waiting += delta
	else:
		_head_waiting = 0.0
	queue_redraw()


## A head item that cannot leave for a while means downstream is full: show the belt as jammed.
func jammed() -> bool:
	return _head_waiting >= JAM_SECONDS


func hit(at: Vector2) -> bool:
	return Layout.distance_to_route(points, at) <= 16.0


func _draw() -> void:
	if points.size() < 2:
		return
	var connected: bool = data.get("connected", true)
	var jam := connected and jammed()
	var rim := Color("91a6a8")
	var top := Color("c8d6d3")
	if jam:
		rim = Color("e53935")
		top = Color("f2c4bd")
	elif not connected:
		rim = Color("cfd8d3")
		top = Color("e6ebe4")
	if selected:
		draw_polyline(points, Color("e6bb60"), 32, true)
	var shadow_points := points.duplicate()
	for i in shadow_points.size():
		shadow_points[i] += Vector2(0, 3)
	draw_polyline(shadow_points, Color("c1cec8"), 22, true)
	draw_polyline(points, rim, 18, true)
	draw_polyline(points, top, 12, true)
	for i in points.size() - 1:
		var direction := (points[i + 1] - points[i]).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var length := points[i].distance_to(points[i + 1])
		var offset := fmod(_clock * 20, 24) if connected and not jam else 0.0
		for j in int(length / 24):
			var at := points[i] + direction * (j * 24 + offset)
			if at.distance_to(points[i]) < length - 5:
				draw_polyline(PackedVector2Array([at - direction * 3 + normal * 3, at, at - direction * 3 - normal * 3]), Color("7f9797") if not jam else Color("c0463c"), 2, true)
	for item in data.get("items", []):
		var at := Layout.along(points, float(item.pos) / maxf(length_cells, 0.01))
		draw_texture_rect(Assets.item(item.item), Rect2(at - Vector2(13, 20), Vector2(26, 26)), false)
