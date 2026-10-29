extends Node2D
## Stage-one art composition. This scene never owns or advances business state.

signal closed

const LAYERS := ["floor", "walls", "furniture", "belts", "equipment", "actors", "drinks"]
var art: Node2D
var _canvas: Node2D
var _ui: Control
var _original: Sprite2D
var _panel: PanelContainer
var _probe: Node2D
var _probe_walk := false
var _clock := 0.0
var _closing := false
var _save_notice: Label


func _ready() -> void:
	_canvas = $Canvas
	art = $Canvas/ShopArt
	_ui = $Overlay/UI
	_original = $Canvas/Original
	_original.texture = load("res://art/reference/reference.png")
	_original.centered = false
	_original.scale = Vector2(720, 1280) / _original.texture.get_size()
	_original.visible = false
	_build_ui()
	_build_probe()
	_fit()


func _build_ui() -> void:
	var theme := Theme.new()
	theme.default_font = load("res://art/ui/graybox_font.ttf")
	theme.default_font_size = 14
	_ui.theme = theme
	var bar := HBoxContainer.new()
	bar.position = Vector2(18, 8)
	bar.add_theme_constant_override("separation", 8)
	_ui.add_child(bar)
	_save_notice = Label.new()
	_save_notice.position = Vector2(18, 1218)
	_save_notice.text = "保存失败，未离开当前游戏"
	_save_notice.visible = false
	_ui.add_child(_save_notice)
	_button(bar, "Back to game", close)
	_button(bar, "试玩", func() -> void:
		if is_instance_valid(App.sim):
			if App.save_now() != OK:
				_save_notice.visible = true
				return
			App._pending_shop_state = App.sim.to_dict()
			App.sim = null
		get_tree().change_scene_to_file("res://presentation/tea_playtest/tea_playtest.tscn"))
	_button(bar, "Layers", func() -> void: _panel.visible = not _panel.visible)
	var reference := CheckButton.new()
	reference.text = "Original"
	reference.toggled.connect(func(on: bool) -> void: _original.visible = on)
	bar.add_child(reference)
	_panel = PanelContainer.new()
	_panel.position = Vector2(18, 52)
	_panel.visible = false
	_ui.add_child(_panel)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 160
	_panel.add_child(list)
	for layer in LAYERS:
		var check := CheckButton.new()
		check.text = layer.capitalize()
		check.button_pressed = true
		check.toggled.connect(set_layer_visible.bind(layer))
		list.add_child(check)
	var probe := CheckButton.new()
	probe.text = "Walk / occlusion"
	probe.toggled.connect(set_occlusion_probe)
	list.add_child(probe)
	var caption := Label.new()
	caption.text = "STATIC ART PREVIEW - production paused"
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", Color("fff3db"))
	caption.add_theme_color_override("font_shadow_color", Color("4c2c1e"))
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	caption.position = Vector2(18, 1256)
	_ui.add_child(caption)


func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(102, 34)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f8e8cb")
	style.border_color = Color("6a4430")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_color_override("font_color", Color("583724"))
	button.pressed.connect(action)
	parent.add_child(button)


func _build_probe() -> void:
	_probe = Node2D.new()
	_probe.name = "OcclusionProbe"
	_probe.visible = false
	art.get_node("Sortables").add_child(_probe)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://art/reference/cat.png")
	sprite.centered = false
	sprite.scale = Vector2(104, 140) / sprite.texture.get_size()
	sprite.position = Vector2(-52, -140)
	_probe.add_child(sprite)


## Signal order is boolean, layer id, so CheckButton.toggled can bind a layer.
func set_layer_visible(on: bool, layer: String) -> void:
	for node in art.find_children("*", "Node2D", true, false):
		if node.get_meta("art_layer", "") == layer:
			node.visible = on


func set_occlusion_probe(on: bool) -> void:
	_probe.visible = on
	_probe_walk = on
	_clock = 0.0
	_probe.position = Vector2(160, 800)


func set_probe_position(point: Vector2) -> void:
	_probe_walk = false
	_probe.visible = true
	_probe.position = point


func _process(delta: float) -> void:
	_fit()
	if _probe_walk:
		_clock += delta
		# Alternate the solid wall and clear door paths, crossing the same depth threshold.
		var t := fmod(_clock, 8.0)
		_probe.position = Vector2(160 if t < 4.0 else 360, 790 + (1.0 - cos(fmod(t, 4.0) * PI / 2.0)) * 75)


func _fit() -> void:
	var size := get_viewport_rect().size
	var factor := minf(size.x / 720.0, size.y / 1280.0)
	var offset := (size - Vector2(720, 1280) * factor) / 2.0
	_canvas.position = offset
	_canvas.scale = Vector2.ONE * factor
	_ui.position = offset
	_ui.scale = Vector2.ONE * factor


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	if _closing:
		return
	_closing = true
	var standalone := closed.get_connections().is_empty()
	closed.emit()
	if standalone:
		get_tree().change_scene_to_file.call_deferred("res://presentation/shop.tscn")
	if not is_queued_for_deletion():
		queue_free()
