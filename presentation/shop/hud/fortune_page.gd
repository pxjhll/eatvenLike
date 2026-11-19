extends Control

const Fortunes := preload("res://game/rules/shop_fortunes.gd")
const ART := {
	"frame":preload("res://art/ui/fortunes/frame.png"), "plaque":preload("res://art/ui/fortunes/plaque.png"),
	"box":preload("res://art/ui/fortunes/box.png"), "pocket":preload("res://art/ui/fortunes/pocket.png"),
	"ticket":preload("res://art/ui/fortunes/ticket.png"), "button":preload("res://art/ui/fortunes/button.png"),
	"close":preload("res://art/ui/fortunes/close.png"), "paw":preload("res://art/ui/fortunes/paw.png"),
	"stamp":preload("res://art/ui/fortunes/stamp.png"), "flower":preload("res://art/ui/fortunes/flower.png"),
	"postcard":preload("res://art/ui/fortunes/postcard.png"), "cash":preload("res://art/ui/coin.png")
}
const SIZE := Vector2(610, 684)
var view: Node2D
var hud: Control
var board := Control.new()
var structure := ""
var timer: Label
var replacing := false
var freezes_shop: bool:
	get: return view != null and view.rules.lucky.pending != ""

func setup(scene: Node2D, ui: Control) -> void:
	view = scene
	hud = ui
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(board)
	board.size = SIZE
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var fit := minf(1.0, minf((size.x - 24) / SIZE.x, (size.y - 32) / SIZE.y))
	board.scale = Vector2.ONE * maxf(fit, 0.01)
	board.position = (size - SIZE * board.scale) * 0.5

func on_open() -> void:
	replacing = false
	structure = ""

func refresh() -> void:
	var state: RefCounted = view.rules.lucky
	var key := str([state.held, state.pending, state.amount, state.progress, state.charges, state.opened, replacing])
	if structure != key:
		structure = key
		for child in board.get_children():
			board.remove_child(child)
			child.queue_free()
		timer = null
		_art("frame", Rect2(Vector2.ZERO, SIZE))
		_art("plaque", Rect2(118, 32, 374, 80))
		_label("幸运签盒", Rect2(125, 35, 360, 64), 43)
		_art("close", Rect2(530, 9, 64, 64))
		_hit("关闭", Rect2(528, 7, 68, 68), dismiss)
		if state.pending == "": _home(state)
		else: _reveal(state)
	if is_instance_valid(timer):
		var seconds := maxi(0, ceili(state.next_at - view.rules.clock - 0.00001))
		timer.text = "下次恢复 %02d:%02d" % [seconds / 60, seconds % 60] if state.opened and state.charges < 2 else ("次数已满" if state.opened else "完成首单后可抽签")

func _home(state: RefCounted) -> void:
	_art("box", Rect2(205, 125, 200, 146))
	if state.held.size() == 2:
		_art("ticket", Rect2(72, 280, 466, 114))
		_label(Fortunes.TITLES[state.held[1]], Rect2(114, 285, 382, 42), 24)
		_hit("切换留签", Rect2(72, 280, 466, 49), _act.bind("swap"))
	var front_y := 324 if state.held.size() == 2 else 310
	_art("ticket", Rect2(59, front_y, 492, 105))
	if state.held.is_empty():
		_label("可留一张签" if state.slots() == 1 else "可留两张签", Rect2(80, front_y + 10, 450, 58), 29)
	else:
		var id: String = state.held[0]
		_label("已留签", Rect2(73, front_y + 16, 93, 52), 20)
		_label(Fortunes.TITLES[id], Rect2(165, front_y + 8, 215, 40), 29)
		_label(Fortunes.DETAILS[id], Rect2(154, front_y + 48, 240, 30), 17)
		_button("使用", Rect2(410, front_y + 14, 109, 58), _act.bind("held"), 24)
	_art("pocket", Rect2(40, 389, 530, 74))
	if state.held.size() == 2:
		_label("点后排签可切换", Rect2(75, 457, 460, 32), 19)
	elif state.progress < 5:
		_label("第二槽 · 连抽 %d/5 次解锁" % state.progress, Rect2(75, 458, 460, 32), 19)
	_label("可抽 %d/2 次" % state.charges, Rect2(115, 492, 380, 46), 29)
	_button("免费抽一签", Rect2(129, 544, 352, 86), _act.bind("draw"), 38, state.charges == 0)
	timer = _label("", Rect2(85, 622, 440, 38), 21)

func _reveal(state: RefCounted) -> void:
	var id: String = state.pending
	if replacing:
		_label("签袋已满", Rect2(65, 165, 480, 58), 38)
		_label("选一张现在使用，腾出位置留新签", Rect2(43, 238, 524, 55), 25)
		for i in state.held.size():
			_button("使用 · " + Fortunes.TITLES[state.held[i]], Rect2(106, 322 + 100*i, 398, 78), _act.bind("replace", i), 27)
		_button("返回", Rect2(218, 554, 174, 64), _choose_replace.bind(false), 25)
		return
	_label(Fortunes.TITLES[id], Rect2(40, 128, 530, 70), 38)
	if id == "postcard":
		_art("postcard", Rect2(39, 202, 532, 304))
		var letter: String = Fortunes.DETAILS[id].replace("，", "，\n").replace("。", "。\n")
		var writing := _label(letter, Rect2(316, 279, 215, 176), 21)
		writing.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	elif id == "stamp":
		_art("ticket", Rect2(117, 239, 376, 145))
		var seal := _art("stamp", Rect2(259, 250, 92, 92))
		var paw := _art("paw", Rect2(346, 175, 155, 130))
		seal.modulate.a = 0
		var tween := paw.create_tween()
		tween.tween_property(paw, "position", Vector2(280, 192), 0.24)
		tween.tween_property(seal, "modulate:a", 1.0, 0.09)
		tween.tween_property(paw, "modulate:a", 0.0, 0.32)
	elif id == "cash" or id == "flower":
		_art(id, Rect2(234, 236, 142, 146))
	else:
		_art("box", Rect2(210, 230, 190, 142))
	if id != "postcard":
		var message: String = "金币 +%d" % state.amount if id == "cash" else Fortunes.DETAILS[id]
		_label(message, Rect2(70, 430, 470, 95), 29)
	if id in Fortunes.STORABLE:
		_button("立即使用", Rect2(71, 548, 224, 73), _act.bind("use"), 28)
		_button("留签", Rect2(315, 548, 224, 73), _choose_replace.bind(true) if state.held.size() >= state.slots() else _act.bind("save"), 28)
	else:
		_button("读完了" if id == "postcard" else "知道了", Rect2(143, 548, 324, 73), _act.bind("done"), 30)

func dismiss() -> void:
	var pending: String = view.rules.lucky.pending
	if pending == "cash" or pending in Fortunes.FUN:
		_act("done")
	else:
		hud.open_page("shop")

func _choose_replace(value: bool) -> void:
	replacing = value
	refresh()

func _act(action: String, index := 0) -> void:
	var state: RefCounted = view.rules.lucky
	var previous: Dictionary = state.snapshot()
	var result: Error = view.session.fortune_action(action, index, view.guide.seen_list() if view.guide != null else [])
	if result != OK:
		view._show_toast(view.session.last_error)
		refresh()
		return
	replacing = false
	if action in ["held", "use", "replace", "done"]:
		hud.open_page("shop")
		if action == "done" and previous.pending == "flower": _give_flower(previous.amount)
		if action == "replace": view._show_toast("已使用旧签，新签已放入签袋")
	else:
		refresh()
		if action == "draw" and previous.progress == 4: view._show_toast("第二个留签槽已解锁")

func _give_flower(id: int) -> void:
	var actor: Node2D = view._actors.get(id)
	if not is_instance_valid(actor): return
	var flower := Sprite2D.new()
	flower.texture = ART.flower
	var height: float = view._staff_height
	flower.scale = Vector2.ONE * (height * 0.42 / flower.texture.get_height())
	flower.position = Vector2(0, -height * 1.06)
	flower.z_index = 8
	actor.add_child(flower)
	var tween := flower.create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(flower, "modulate:a", 0.0, 0.45)
	tween.tween_callback(flower.queue_free)

func _art(id: String, rect: Rect2) -> TextureRect:
	var part := TextureRect.new()
	part.texture = ART[id]
	part.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	part.stretch_mode = TextureRect.STRETCH_SCALE
	part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(part)
	part.position = rect.position
	part.size = rect.size
	return part

func _label(value: String, rect: Rect2, pixels: int) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", Color("58351e"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(label)
	label.position = rect.position
	label.size = rect.size
	return label

func _button(value: String, rect: Rect2, callback: Callable, pixels: int, disabled := false) -> void:
	var art := _art("button", rect)
	if disabled: art.modulate = Color("c8bcac")
	_label(value, rect.grow_individual(0, 0, 0, -6), pixels)
	var button := _hit(value, rect, callback)
	button.disabled = disabled
	button.button_down.connect(func() -> void: art.modulate = Color("e3c8a4"))
	button.button_up.connect(func() -> void: art.modulate = Color.WHITE)

func _hit(value: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.accessibility_name = value
	button.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for state in ["normal","pressed","hover","focus","disabled"]:
		button.add_theme_stylebox_override(state, empty)
	board.add_child(button)
	button.position = rect.position
	button.size = rect.size
	hud.bind_action(button, callback)
	return button
