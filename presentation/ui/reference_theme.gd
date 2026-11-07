extends RefCounted
## Palette and control defaults sampled from the thirteen approved UI references.

const INK := Color("562d17")
const MUTED := Color("a27d58")

## Palettes per kind (paper, wood, gold, ...) are data in this Theme resource; open it
## in the Godot editor to tune colors, rims and depth. Code only derives the button
## states (hover / pressed / disabled / selected) from a palette.
const SKIN: Theme = preload("res://art/ui/reference_skin.tres")
const SKIN_TYPE := "ReferenceSkin"

static func style(kind: String, radius: float = 16.0, state: String = "normal") -> StyleBox:
	var palette := kind if SKIN.has_stylebox(kind, SKIN_TYPE) else "cream"
	var box = SKIN.get_stylebox(palette, SKIN_TYPE).duplicate()
	box.kind = kind
	box.state = state
	box.radius = radius
	if state == "hover":
		box.bg_color = box.bg_color.lightened(0.09)
		box.face_bottom = box.face_bottom.lightened(0.07)
	elif state == "pressed":
		box.bg_color = box.bg_color.darkened(0.11)
		box.face_bottom = box.face_bottom.darkened(0.09)
		box.highlight.a = 0.45
	elif state == "disabled":
		box.bg_color = Color("e9dfcd")
		box.face_bottom = Color("ddd0b9")
		box.contour = Color("b7a38a")
		box.rim = Color("f4ecdd")
		box.depth_color = Color("beaa8d")
		box.highlight.a = 0.45
	elif state == "selected":
		box.contour = Color("dc930a")
		box.rim = Color("ffcf59")
		box.rim_width = 2.3
		box.bg_color = Color("fff4d5")
		box.face_bottom = Color("ffe8b4")
	return box

static func ui_font() -> Font:
	return SKIN.default_font

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = ui_font()
	theme.default_font_size = 23
	for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox"]:
		theme.set_color("font_color", type, INK)
		theme.set_color("font_shadow_color", type, Color(1.0, 0.97, 0.88, 0.3))
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type, style("cream", 16, state))
		for state in ["font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(state, type, INK)
		theme.set_color("font_disabled_color", type, Color("a18e77"))
		theme.set_color("icon_normal_color", type, Color.WHITE)
		theme.set_color("icon_hover_color", type, Color.WHITE)
		theme.set_color("icon_pressed_color", type, Color.WHITE)
		theme.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.5))
		theme.set_constant("h_separation", type, 9)
	theme.set_stylebox("panel", "PanelContainer", style("paper", 24))
	theme.set_stylebox("background", "ProgressBar", style("track", 10))
	theme.set_stylebox("fill", "ProgressBar", style("fill", 10))
	theme.set_color("font_color", "ProgressBar", INK)
	var slider := style("track", 7)
	slider.content_margin_top = 5.0
	slider.content_margin_bottom = 5.0
	theme.set_stylebox("slider", "HSlider", slider)
	var grabber_area := style("fill", 7)
	grabber_area.content_margin_top = 5.0
	grabber_area.content_margin_bottom = 5.0
	theme.set_stylebox("grabber_area", "HSlider", grabber_area)
	var grabber_highlight := style("fill", 7, "hover")
	grabber_highlight.content_margin_top = 5.0
	grabber_highlight.content_margin_bottom = 5.0
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_highlight)
	theme.set_icon("grabber", "HSlider", _slider_knob())
	theme.set_icon("grabber_highlight", "HSlider", _slider_knob(true))
	theme.set_icon("grabber_disabled", "HSlider", _slider_knob(false, true))
	theme.set_constant("grabber_offset", "HSlider", 0)
	theme.set_constant("center_grabber", "HSlider", 0)
	theme.set_constant("outline_size", "Label", 0)
	return theme

static func _slider_knob(hover := false, disabled := false) -> GradientTexture2D:
	# A radial native gradient supplies the round slider handle without an asset.
	var colors := PackedColorArray([Color("fff9e9"), Color("ffebc9"), Color("dfaf76"), Color("8c572d"), Color("8c572d00")])
	if hover:
		colors[1] = Color("ffe0a1")
	if disabled:
		colors[0] = Color("e5ded0")
		colors[1] = Color("d4c5af")
		colors[3] = Color("a99883")
		colors[4] = Color("a9988300")
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.70, 0.78, 0.88, 0.98])
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 30
	texture.height = 30
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
