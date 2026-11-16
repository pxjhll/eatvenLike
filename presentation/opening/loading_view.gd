extends Control
## Reference-aligned, live UI over the user's unmodified GIF frames.

const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const FRAMES := preload("res://art/opening/loading_frames.tres")
const SOURCE_SIZE := Vector2(327, 587)
const NUMBER_RECT := Rect2(76, 315, 180, 49)
const MESSAGE_RECT := Rect2(58, 365, 215, 26)
const CAPTION_RECT := Rect2(53, 511, 221, 38)
const INK := Color("603109")
var sprite: AnimatedSprite2D
var percent_label: Label
var message_label: Label
var caption_button: Button
var _content: Control


func _ready() -> void:
	_content = Control.new()
	_content.size = SOURCE_SIZE
	add_child(_content)
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = FRAMES
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_content.add_child(sprite)
	sprite.play()
	percent_label = _label(NUMBER_RECT, 44)
	percent_label.add_theme_constant_override("outline_size", 2)
	percent_label.add_theme_color_override("font_outline_color", INK)
	message_label = _label(MESSAGE_RECT, 14)
	caption_button = Button.new()
	caption_button.position = CAPTION_RECT.position
	caption_button.size = CAPTION_RECT.size
	caption_button.add_theme_font_size_override("font_size", 14)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		caption_button.add_theme_color_override(state, INK)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var skin = ReferenceTheme.style("gold", 19, "normal")
		skin.bg_color = Color("fff0cf")
		skin.face_bottom = Color("ffdb99")
		skin.contour = Color("8b4c1d")
		skin.rim = Color("fff8df")
		skin.depth_color = Color("cf8c3d")
		skin.depth = 2.5
		caption_button.add_theme_stylebox_override(state, skin)
	caption_button.add_theme_stylebox_override("focus", ReferenceTheme.style("gold", 19, "focus"))
	_content.add_child(caption_button)
	resized.connect(_layout)
	_layout()
	set_progress(-1)


func _label(rect: Rect2, font_size: int) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", font_size)
	_content.add_child(label)
	return label


func _layout() -> void:
	var factor := minf(size.x / SOURCE_SIZE.x, size.y / SOURCE_SIZE.y)
	var offset := (size - SOURCE_SIZE * factor) * 0.5
	_content.size = size
	sprite.scale = Vector2.ONE * factor
	sprite.position = offset
	# Rasterize glyphs at their final logical size; only the supplied bitmap is scaled.
	for entry in [[percent_label, NUMBER_RECT, 44], [message_label, MESSAGE_RECT, 14], [caption_button, CAPTION_RECT, 14]]:
		var control: Control = entry[0]
		var rect: Rect2 = entry[1]
		control.position = offset + rect.position * factor
		control.size = rect.size * factor
		control.add_theme_font_size_override("font_size", maxi(1, roundi(entry[2] * factor)))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var skin = caption_button.get_theme_stylebox(state)
		skin.radius = 19 * factor
		if state != "focus": skin.depth = 2.5 * factor


func set_progress(value: int, ready := false) -> void:
	percent_label.text = "%d%%" % clampi(value, 0, 100) if value >= 0 else "…"
	message_label.text = "加载完成" if ready else "美味正在准备中…"
	caption_button.text = "加载完成，点击播放片头" if ready else "小厨师们正在赶来，马上开饭！"
	caption_button.disabled = not ready
