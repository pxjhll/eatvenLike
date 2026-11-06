extends RefCounted
## Palette and control defaults sampled from the thirteen approved UI references.

const ReferenceStyle := preload("res://presentation/ui/reference_style.gd")
const INK := Color("562d17")
const MUTED := Color("a27d58")

static func style(kind: String, radius: float = 16.0, state: String = "normal") -> StyleBox:
	var box := ReferenceStyle.new()
	box.kind = kind
	box.state = state
	box.bg_color = Color("fff0d6")
	box.face_bottom = Color("f9dfb8")
	box.radius = radius
	box.set_content_margin_all(12.0)
	box.content_margin_top = 8.0
	box.content_margin_bottom = 10.0
	match kind:
		"paper":
			box.bg_color = Color("fff7e8")
			box.face_bottom = Color("ffead3")
			box.rim = Color("efbf8f")
			box.rim_width = 3.0
			box.contour = Color("805032")
			box.depth_color = Color("b77950")
			box.depth = 5.0
			box.set_content_margin_all(18.0)
		"header":
			box.bg_color = Color("fff2dc")
			box.face_bottom = Color("ffe9cc")
			box.rim = Color("e7ad7f")
			box.rim_width = 4.0
			box.depth_color = Color("a9633e")
			box.depth = 5.0
		"wood":
			box.bg_color = Color("d99a68")
			box.face_bottom = Color("b96f48")
			box.rim = Color("edb07b")
			box.depth_color = Color("75402d")
			box.contour = Color("693924")
			box.depth = 7.0
			box.rim_width = 2.6
		"card", "pill":
			box.bg_color = Color("fff4e2")
			box.face_bottom = Color("fbe8d1")
			box.contour = Color("c39771")
			box.rim = Color("f3d5b4")
			box.depth_color = Color("dfbd98")
			box.depth = 1.0 if kind == "card" else 0.0
			box.rim_width = 0.8
		"gold":
			box.bg_color = Color("ffdb85")
			box.face_bottom = Color("ffca61")
			box.contour = Color("8c4f1d")
			box.rim = Color("fff0b4")
			box.depth_color = Color("ce8a2b")
			box.depth = 4.0
		"orange", "fill":
			box.bg_color = Color("f5a64d") if kind == "fill" else Color("e89b49")
			box.face_bottom = Color("e9892b") if kind == "fill" else Color("d47c30")
			box.contour = Color("a4652b") if kind == "fill" else Color("854416")
			box.rim = Color("f7be72")
			box.depth_color = Color("a65b24")
			box.depth = 0.0 if kind == "fill" else 4.0
			box.rim_width = 0.7 if kind == "fill" else 1.7
			if kind == "fill": box.set_content_margin_all(0.0)
		"danger":
			box.bg_color = Color("ffdfd0")
			box.face_bottom = Color("f7c2af")
			box.contour = Color("a96044")
			box.rim = Color("fff4e9")
			box.depth_color = Color("c5866b")
			box.depth = 2.0
		"track":
			box.bg_color = Color("e6c39c")
			box.face_bottom = Color("efd3ad")
			box.contour = Color("c99766")
			box.rim = Color("dcb487")
			box.highlight = Color(1.0, 0.96, 0.84, 0.25)
			box.depth_color = Color("d5aa7d")
			box.rim_width = 0.3
			box.depth = 0.0
			box.set_content_margin_all(0.0)
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

static var _font: FontVariation

static func ui_font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = load("res://art/ui/graybox_font.ttf")
		_font.variation_embolden = 0.42
	return _font

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
