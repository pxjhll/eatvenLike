extends SceneTree
## Real renderer regression: catches a missing StyleBox virtual dispatch, flat fills,
## square clipping, lost button states, and progress-bar palette regressions.

const OUTPUT := "res://output/native-ui-reference/style-smoke.png"
const BACKGROUND := Color("343e4d")
var failures := 0
var script_errors := preload("res://tests/error_counter.gd").new()

class Probe extends Control:
	var boxes: Array[StyleBox] = []
	func _draw() -> void:
		for i in boxes.size():
			boxes[i].draw(get_canvas_item(), Rect2(20 + (i % 4) * 210, 20 + (i / 4) * 120, 180, 90))

func _initialize() -> void:
	OS.add_logger(script_errors)
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This test requires a real renderer (use --rendering-method gl_compatibility).")
		quit(2)
		return
	var shape = load("res://presentation/ui/reference_style.gd").new()
	for extent in [Vector2(2, 12), Vector2(12, 12), Vector2(100, 10), Vector2(1, 1)]:
		for radius in [0.0, 5.0, 20.0]:
			var outline: PackedVector2Array = shape._outline(Rect2(Vector2.ZERO, extent), radius)
			_check(not Geometry2D.triangulate_polygon(outline).is_empty(), "tiny native fills triangulate at %s/r%s" % [extent,radius])
	var available := ResourceLoader.exists("res://presentation/ui/reference_theme.gd")
	_check(available, "shared reference skin exists")
	var skin = load("res://presentation/ui/reference_theme.gd") if available else null
	var viewport := SubViewport.new()
	viewport.size = Vector2i(860, 710)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.size = Vector2(860, 710)
	viewport.add_child(background)
	var probe := Probe.new()
	var kinds := ["cream", "gold", "orange", "danger", "paper", "header", "wood", "card", "track", "fill", "pill", "cream", "cream", "cream", "cream", "gold"]
	for i in kinds.size():
		var state := "normal"
		if i == 11: state = "pressed"
		if i == 12: state = "disabled"
		if i == 13: state = "hover"
		if i == 14: state = "focus"
		var box: StyleBox
		if skin:
			box = skin.style(kinds[i], 18, state)
		else:
			box = StyleBoxFlat.new()
			box.bg_color = Color("fff5e2")
			box.set_corner_radius_all(18)
		probe.boxes.append(box)
	viewport.add_child(probe)
	if skin:
		var controls := Control.new()
		controls.theme = skin.make_theme()
		viewport.add_child(controls)
		var panel := PanelContainer.new()
		panel.position = Vector2(20, 515)
		panel.size = Vector2(235, 160)
		controls.add_child(panel)
		var label := Label.new()
		label.text = "原生纸面\n按钮 · 滑条"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(label)
		var button := Button.new()
		button.position = Vector2(285, 520)
		button.size = Vector2(160, 64)
		button.text = "继续营业"
		button.focus_mode = Control.FOCUS_NONE
		controls.add_child(button)
		var progress := ProgressBar.new()
		progress.position = Vector2(485, 525)
		progress.size = Vector2(320, 20)
		progress.show_percentage = false
		progress.value = 60
		controls.add_child(progress)
		var slider := HSlider.new()
		slider.position = Vector2(485, 565)
		slider.size = Vector2(320, 44)
		slider.value = 60
		controls.add_child(slider)
		var small := Panel.new()
		small.position = Vector2(285, 630)
		small.size = Vector2(120, 30)
		small.add_theme_stylebox_override("panel", skin.style("gold", 18))
		controls.add_child(small)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/native-ui-reference"))
	image.save_png(ProjectSettings.globalize_path(OUTPUT))
	var top := image.get_pixel(110, 36)
	var bottom := image.get_pixel(110, 91)
	_check(top.get_luminance() > bottom.get_luminance() + 0.018, "native virtual drawing produces a visible gentle gradient")
	_check(image.get_pixel(21, 21).is_equal_approx(BACKGROUND), "rounded corners preserve the canvas")
	_check(image.get_pixel(21, 65).get_luminance() < bottom.get_luminance() * 0.7, "warm outer contour is distinct from the face")
	_check(image.get_pixel(110, 106).get_luminance() < bottom.get_luminance() - 0.13, "button has a darker bottom depth")
	_check(image.get_pixel(320, 65).b < image.get_pixel(110, 65).b - 0.12, "gold and cream remain visually distinct")
	_check(image.get_pixel(740, 65).r > image.get_pixel(740, 65).g * 1.2, "danger uses a restrained red face")
	_check(image.get_pixel(740, 305).get_luminance() < image.get_pixel(110, 65).get_luminance() - 0.035, "pressed button changes its rendered face")
	_check(image.get_pixel(110, 425).get_luminance() < image.get_pixel(110, 65).get_luminance() - 0.03, "disabled button changes its rendered face")
	_check(image.get_pixel(530, 425).is_equal_approx(BACKGROUND), "focus style preserves transparent center")
	if skin:
		_check(image.get_pixel(135, 535).r > 0.9, "PanelContainer invokes the native skin virtual")
		_check(image.get_pixel(350, 532).get_luminance() > image.get_pixel(350, 575).get_luminance() + 0.015, "Button theme invokes the gradient skin virtual")
		_check(image.get_pixel(540, 535).b < image.get_pixel(760, 535).b - 0.2, "ProgressBar renders a separate orange fill and tan track")
		_check(image.get_pixel(345, 638).get_luminance() > image.get_pixel(345, 652).get_luminance() + 0.015, "small rounded buttons keep their gradient")
		_check(image.get_pixel(286, 631).is_equal_approx(BACKGROUND), "small component corners remain round")
		var theme: Theme = skin.make_theme()
		for type in ["Button", "OptionButton"]:
			for state in ["normal", "hover", "pressed", "disabled", "focus"]:
				_check(theme.has_stylebox(state, type), "%s has %s skin" % [type, state])
		_check(theme.has_stylebox("panel", "PanelContainer"), "panel theme is shared")
		_check(theme.has_stylebox("fill", "ProgressBar"), "progress theme is shared")
		_check(theme.has_stylebox("slider", "HSlider"), "slider theme is shared")
	_check(script_errors.take().is_empty(), "renderer emits no script errors")
	OS.remove_logger(script_errors)
	print("REFERENCE_STYLE_RENDER: %s; failures=%d" % [ProjectSettings.globalize_path(OUTPUT), failures])
	viewport.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
