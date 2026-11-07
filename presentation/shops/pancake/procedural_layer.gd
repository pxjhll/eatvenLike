@tool
extends Node2D
## Scene labels and soft contact shadows are drawn, never imported as textures.

@export_enum("text", "shadow") var kind := "shadow"
@export var layer_size := Vector2.ZERO
@export var ink := Color.WHITE
@export var text := ""
@export var font: Font
@export var font_size := 20
@export var blur_radius := 3.0

func _draw() -> void:
	if kind == "text":
		if font == null or text.is_empty(): return
		var baseline := (layer_size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
		draw_string(font, Vector2(0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
		return
	# Concentric ellipses approximate a small Gaussian blur with no shadow bitmap.
	var steps := 20 if blur_radius > 0 else 1
	var center := layer_size * 0.5
	for step in steps:
		var t := float(step + 1) / steps
		var spread := blur_radius * lerpf(2.0, -1.0, t)
		var radii := (layer_size * 0.5 + Vector2.ONE * spread).max(Vector2.ONE * 0.25)
		var points := PackedVector2Array()
		for i in 64:
			var angle := TAU * i / 64.0
			points.append(center + Vector2(cos(angle), sin(angle)) * radii)
		# Per-pass alpha composes to the exact design center opacity.
		var pass_alpha := 1.0 - pow(1.0 - ink.a, 1.0 / steps)
		draw_colored_polygon(points, Color(ink, pass_alpha))
