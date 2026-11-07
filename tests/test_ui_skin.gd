extends "res://tests/test_case.gd"
## The reference UI keeps palettes in art/ui/reference_skin.tres and simple icons as
## SVG files in art/ui/icons/. These checks catch a broken file or a missing name.

const Theme_ := preload("res://presentation/ui/reference_theme.gd")
const Icons := preload("res://presentation/ui/reference_icons.gd")
const KINDS := ["cream", "paper", "header", "wood", "card", "pill", "gold", "orange", "fill", "danger", "danger_strong", "toast", "check_done", "check_todo", "track"]
const ICONS := ["goals", "hat", "pause", "pause_bars", "save", "glass", "trash", "selected_check", "check", "lock", "clock", "record", "export", "tag", "previous", "next", "play", "arrow_right", "arrow_left", "arrow_up", "arrow_down", "expand", "collapse", "close"]


func test_skin_has_a_palette_for_every_kind() -> void:
	for kind in KINDS:
		check(Theme_.SKIN.has_stylebox(kind, Theme_.SKIN_TYPE), "skin palette exists: " + kind)
		var box = Theme_.style(kind, 18, "hover")
		check(box is StyleBox and box.get_script() != null, "style() returns the native skin: " + kind)
		check_eq(box.radius, 18.0, "style() applies the radius: " + kind)
		check_eq(box.state, "hover", "style() applies the state: " + kind)
	# A styled copy must never write back into the shared palette.
	check_eq(Theme_.SKIN.get_stylebox("cream", Theme_.SKIN_TYPE).get("state"), "normal", "palette stays in its normal state")
	check(Theme_.ui_font() is Font, "skin carries the UI font")


func test_paper_palette_matches_reference() -> void:
	var paper = Theme_.style("paper", 28)
	check(paper.bg_color.is_equal_approx(Color("fff7e8")), "paper face color")
	check_eq(paper.depth, 5.0, "paper depth")
	check_eq(paper.content_margin_left, 18.0, "paper margin")


func test_every_icon_file_loads() -> void:
	for key in ICONS:
		var texture := Icons.texture(key)
		check(texture != null, "icon loads: " + key)
		if texture != null:
			check(texture.get_width() >= 128, "icon imported at high resolution: " + key)
