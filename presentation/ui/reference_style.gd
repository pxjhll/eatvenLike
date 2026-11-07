extends StyleBox
## Shared native skin. StyleBoxFlat overrides draw() in native code and bypasses
## the script virtual, so this uses StyleBox directly and native flat sublayers.
## Each kind's palette lives in art/ui/reference_skin.tres (editable in the inspector).

@export var kind := "cream"
@export var state := "normal"
@export var bg_color := Color("fff0d6")
@export var radius := 16.0
@export var face_bottom := Color("f9dfb8")
@export var contour := Color("714425")
@export var rim := Color("d5a16e")
@export var depth_color := Color("bb8354")
@export var depth := 4.0
@export var rim_width := 1.7
@export var highlight := Color("fffbed")

func _draw(canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var round_radius := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	if state == "focus":
		# Focus is an overlay: its center must never cover the normal button.
		_layer(canvas_item, rect.grow(-1.0), round_radius - 1.0, Color.TRANSPARENT, Color("dc9e37"), 2.0)
		return
	var scale_factor := minf(1.0, rect.size.y / 44.0)
	var actual_depth := depth * scale_factor
	var stroke := minf(1.6, maxf(1.0, rect.size.y / 32.0))
	if state == "pressed":
		actual_depth = minf(1.2, actual_depth)
	# Native StyleBoxFlat layers provide antialiased silhouettes at every size.
	if actual_depth > 0.0:
		_layer(canvas_item, Rect2(rect.position + Vector2(0, 1.4 * scale_factor), rect.size), round_radius, Color(0.22, 0.10, 0.04, 0.16))
	_layer(canvas_item, rect, round_radius, depth_color, contour, stroke)
	var face := rect.grow(-stroke)
	face.size.y -= actual_depth
	if state == "pressed":
		face.position.y += minf(2.0, rect.size.y * 0.04)
		face.size.y -= minf(2.0, rect.size.y * 0.04)
	var face_radius := maxf(0.0, round_radius - stroke)
	_layer(canvas_item, face, face_radius, rim)
	var interior := face.grow(-rim_width * scale_factor)
	var interior_radius := maxf(0.0, face_radius - rim_width * scale_factor)
	_layer(canvas_item, interior, interior_radius, bg_color)
	# Vertex colors interpolate vertically inside a rounded convex polygon.
	# All vertices lie inside the native AA silhouette so corners stay smooth.
	_gradient(canvas_item, interior.grow(-0.45), maxf(0.0, interior_radius - 0.45), bg_color, face_bottom)
	# A narrow inner light catches the upper lip; the low edge stays warm.
	if interior.size.y > 6.0 and highlight.a > 0.0:
		_top_light(canvas_item, interior, interior_radius, highlight, 1.1 * scale_factor)

func _layer(canvas: RID, rect: Rect2, radius: float, color: Color, border := Color.TRANSPARENT, width := 0.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var layer := StyleBoxFlat.new()
	layer.bg_color = color
	layer.draw_center = color.a > 0.0
	layer.border_color = border
	layer.set_border_width_all(int(ceilf(width)))
	layer.set_corner_radius_all(int(maxf(0.0, radius)))
	layer.corner_detail = 12
	layer.anti_aliasing = true
	layer.anti_aliasing_size = 0.65
	layer.draw(canvas, rect)

func _gradient(canvas: RID, rect: Rect2, radius: float, top: Color, bottom: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var points := _outline(rect, radius)
	var colors := PackedColorArray()
	for point in points:
		colors.append(top.lerp(bottom, clampf((point.y - rect.position.y) / rect.size.y, 0.0, 1.0)))
	RenderingServer.canvas_item_add_polygon(canvas, points, colors)

func _outline(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	if r < 0.001:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var centers := [rect.position + Vector2(r, r), Vector2(rect.end.x - r, rect.position.y + r), rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r)]
	for corner in 4:
		for step in 13:
			var angle := PI + float(corner) * PI * 0.5 + float(step) * PI / 24.0
			var point: Vector2 = centers[corner] + Vector2(cos(angle), sin(angle)) * r
			if points.is_empty() or point.distance_squared_to(points[-1]) > 0.0001:
				points.append(point)
	if points.size() > 1 and points[0].distance_squared_to(points[-1]) <= 0.0001:
		points.remove_at(points.size() - 1)
	return points

func _top_light(canvas: RID, rect: Rect2, radius: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var left := rect.position + Vector2(r, r)
	var right := Vector2(rect.end.x - r, rect.position.y + r)
	for step in 13:
		var angle := PI + float(step) * PI / 24.0
		points.append(left + Vector2(cos(angle), sin(angle)) * r)
	for step in 13:
		var angle := PI * 1.5 + float(step) * PI / 24.0
		points.append(right + Vector2(cos(angle), sin(angle)) * r)
	RenderingServer.canvas_item_add_polyline(canvas, points, PackedColorArray([color]), width, true)
