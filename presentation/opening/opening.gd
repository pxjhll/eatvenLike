extends Control
## Welcome -> one intro -> permanent final frame -> the existing shop entry point.

const Video := preload("res://presentation/opening/opening_video.gd")
const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const LoadingView := preload("res://presentation/opening/loading_view.gd")
const BUTTON_FACE := preload("res://art/opening/start_button.svg")
const BASE := Vector2(720, 1280)
const SHOP := "res://presentation/shop/shop_play.tscn"

enum Phase { WELCOME, PLAYING, READY, ENTERING }
signal shop_requested

var phase := Phase.WELCOME
var video: Node
var change_scene_on_start := true
var frame: Control
var welcome: Control
var poster: TextureRect
var welcome_button: Button
var start_button: Button
var status: Label
var _pop: Tween


func _ready() -> void:
	theme = ReferenceTheme.make_theme()
	var backdrop := ColorRect.new()
	backdrop.color = Color("f4f0df")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	frame = Control.new()
	frame.name = "PortraitFrame"
	frame.size = BASE
	add_child(frame)
	welcome = LoadingView.new()
	welcome.name = "Welcome"
	welcome.size = BASE
	frame.add_child(welcome)
	welcome.set_progress(100, true)
	var final_path := "res://art/opening/final_web.png" if OS.has_feature("web") else "res://art/opening/final_native.png"
	poster = _picture(load(final_path), "FinalFrame")
	poster.hide()
	welcome_button = welcome.caption_button
	welcome_button.name = "WelcomeButton"
	welcome_button.tooltip_text = "播放片头"
	welcome_button.accessibility_name = "开始营业，播放片头"
	welcome_button.pressed.connect(begin_intro)
	start_button = Button.new()
	start_button.name = "StartBusiness"
	start_button.position = Vector2(145, 1150)
	start_button.size = Vector2(430, 110)
	start_button.pivot_offset = start_button.size * 0.5
	start_button.text = "开始营业"
	start_button.add_theme_font_size_override("font_size", 64)
	start_button.add_theme_color_override("font_color", Color("512800"))
	start_button.add_theme_color_override("font_outline_color", Color("512800"))
	start_button.add_theme_constant_override("outline_size", 2)
	start_button.add_theme_stylebox_override("focus", ReferenceTheme.style("gold", 55, "focus"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		start_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	start_button.pressed.connect(start_shop)
	frame.add_child(start_button)
	var face := TextureRect.new()
	face.texture = BUTTON_FACE
	face.position = Vector2(-45, -22)
	face.size = Vector2(520, 145)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.show_behind_parent = true
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_button.add_child(face)
	start_button.hide()
	status = Label.new()
	status.position = Vector2(100, 1085)
	status.size = Vector2(520, 50)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 21)
	status.add_theme_color_override("font_color", Color("613d25"))
	status.add_theme_color_override("font_outline_color", Color("fff5df"))
	status.add_theme_constant_override("outline_size", 6)
	frame.add_child(status)
	if video == null:
		video = Video.new()
	add_child(video)
	video.started.connect(_video_started)
	video.finished.connect(_finish_intro.bind(false), CONNECT_DEFERRED)
	video.failed.connect(_finish_intro.bind(true), CONNECT_DEFERRED)
	resized.connect(layout_frame)
	layout_frame()
	welcome_button.grab_focus()
	if OS.has_feature("web"):
		var loading := JavaScriptBridge.get_interface("EatventureLoading")
		if loading != null: loading.ready()


func _picture(texture: Texture2D, node_name: String) -> TextureRect:
	var picture := TextureRect.new()
	picture.name = node_name
	# Disable the texture's minimum-size constraint before assigning a smaller rect.
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.texture = texture
	picture.size = BASE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	return picture


func layout_frame() -> void:
	if frame == null: return
	var factor := minf(size.x / BASE.x, size.y / BASE.y)
	frame.scale = Vector2.ONE * factor
	frame.position = (size - BASE * factor) * 0.5


func begin_intro() -> void:
	if phase != Phase.WELCOME: return
	phase = Phase.PLAYING
	welcome.sprite.pause()
	welcome_button.disabled = true
	welcome_button.hide()
	video.play(frame, ShopAudio.music_enabled)


func _video_started() -> void:
	if phase == Phase.PLAYING:
		welcome.hide()


func _finish_intro(failed: bool) -> void:
	if phase != Phase.PLAYING: return
	phase = Phase.READY
	welcome.hide()
	poster.show()
	video.stop()
	if failed:
		status.text = "片头暂时无法播放，可以直接开始营业"
	start_button.disabled = true
	start_button.scale = Vector2.ONE * 0.08
	start_button.show()
	_pop = create_tween()
	_pop.tween_property(start_button, "scale", Vector2.ONE * 1.04, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop.tween_property(start_button, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pop.tween_callback(_enable_start)


func _enable_start() -> void:
	if phase != Phase.READY: return
	start_button.disabled = false
	start_button.grab_focus()


func start_shop() -> void:
	if phase != Phase.READY or start_button.disabled: return
	phase = Phase.ENTERING
	start_button.disabled = true
	shop_requested.emit()
	if change_scene_on_start:
		call_deferred("_enter_shop")


func _enter_shop() -> void:
	var error := get_tree().change_scene_to_file(SHOP)
	if error != OK:
		phase = Phase.READY
		start_button.disabled = false
		status.text = "进入店铺失败，请再试一次"


func _exit_tree() -> void:
	if is_instance_valid(video): video.stop()
