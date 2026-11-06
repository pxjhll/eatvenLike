extends Node2D
## 煎饼果子摊可玩版：v04 原画 + PancakeSim。员工和顾客画在原画坐标里，HUD 盖在上面。
## 店内进度存在 user://pancake_shop.json（每 10 秒和切后台时存）；结店后切到奶茶店。

const Sim := preload("res://game/pancake/pancake_sim.gd")
const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
const UnlockFrame := preload("res://presentation/tea_playtest/unlock_frame.gd")
const UpgradeBadge := preload("res://presentation/tea_playtest/upgrade_badge.gd")
const Characters := preload("res://presentation/characters/character_library.gd")
const Store := preload("res://game/pancake/pancake_save.gd")
const Guide := preload("res://presentation/pancake/pancake_guide.gd")
const Profile := preload("res://game/app/profile.gd")
const FONT := preload("res://art/ui/graybox_font.ttf")
const COIN := preload("res://art/ui/coin.png")
const SOURCE_SIZE := Vector2(937, 1678)
const TEA_SCENE := "res://presentation/tea_playtest/tea_playtest.tscn"
## 订单气泡里的图：豆浆杯、纸袋煎饼（原画里的图块）。
const ICON_NODES := {"soy": 50, "food": 57}
## 量人物大小用的杯子（豆浆杯）。
const RULER_CUP := 50
const UPGRADE_TEXT := {"speed": "速度 +14%", "price": "售价 +8%"}

## 干活时面朝台子（0 正面 2 右 4 背面 6 左）：收钱面向客人，打豆浆面向豆浆机。
const WORK_FACING := {"register": 0, "soy": 7}

var sim: PancakeSim
var speed := 1.0
## 测试时可以换成临时路径，或设为 null 不存档。
var store: RefCounted = Store.new()
var profile: RefCounted
var guide: Control = Guide.new()
var _autosave := 0.0
var _summary := PanelContainer.new()
var _summary_text := Label.new()
var _summary_leave := Button.new()
var _leave_armed := false
var _finish := Button.new()
@onready var art: Node2D = $PancakeArt
var actors := Node2D.new()
## 员工站在柜台后面：放在柜台、豆浆机这些前排物件下面一层，客人仍在最上层。
var staff_layer := Node2D.new()
var _staff_height := 150.0
var _customer_height := 140.0
var _staff_actors := {}
var _customer_actors := {}
var _frames := {}
var _icons := {}
var _station_rects := {}
var _hud := CanvasLayer.new()
var _gold := Label.new()
var _hint := Label.new()
var _tasks := Label.new()
var _flyer := Button.new()
var _hire := Button.new()
var _upgrade_toggle := Button.new()
var _upgrade_panel := PanelContainer.new()
var _upgrade_list := VBoxContainer.new()
var _upgrade_buttons := {}
var _toast := Label.new()
var _toast_time := 0.0
var _done_shown := false
var _last_event := 0


func _ready() -> void:
	DisplayServer.window_set_title("煎饼果子摊")
	if profile == null:
		var app := get_node_or_null("/root/App")
		profile = app.profile if app != null else Profile.new("user://profile_test.json")
	# 已经开到奶茶店了：直接进奶茶店
	if profile.shop == "tea" and store != null:
		get_tree().change_scene_to_file.call_deferred(TEA_SCENE)
	sim = Sim.new(int(Time.get_unix_time_from_system()))
	var seen_guides: Array = []
	if store != null and store.load_into(sim): seen_guides = store.guides
	for key in ICON_NODES:
		var node: Sprite2D = art.source_node(ICON_NODES[key])
		if node != null: _icons[key] = node.texture
	_measure_stations()
	var cup: Sprite2D = art.source_node(RULER_CUP)
	if cup != null:
		var cup_height: float = (art.global_transform.affine_inverse() * cup.global_transform * cup.get_rect()).size.y
		_staff_height = cup_height * Characters.STAFF_PER_CUP
		_customer_height = cup_height * Characters.CUSTOMER_PER_CUP
	actors.y_sort_enabled = true
	art.add_child(actors)
	staff_layer.y_sort_enabled = true
	var counter: CanvasItem = art.source_node(46)
	counter.get_parent().add_child(staff_layer)
	counter.get_parent().move_child(staff_layer, counter.get_index())
	_build_frames()
	_build_hud()
	guide.setup(self, seen_guides, _style)
	_hud.get_child(0).add_child(guide)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_sync_art()
	_refresh_hud()
	if store != null and not store.last_error.is_empty(): _show_toast(store.last_error, 3.0)


func restart() -> void:
	sim.reset()
	for a in _staff_actors.values(): a.queue_free()
	for a in _customer_actors.values(): a.queue_free()
	_staff_actors.clear()
	_customer_actors.clear()
	_done_shown = false
	_last_event = 0
	_sync_art()
	_refresh_hud()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1) * speed
	if guide.freezes() or _summary.visible: dt = 0.0
	var steps := maxi(1, ceili(dt / 0.05))
	if dt > 0.0:
		for i in steps: sim.step(dt / steps)
	_sync_actors()
	_refresh_hud()
	guide.refresh(delta)
	_autosave += delta
	if _autosave >= 10.0:
		_autosave = 0.0
		save_now()
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.visible = _toast_time > 0.0


# ---------- art ----------

func _fit() -> void:
	var viewport := get_viewport_rect().size
	var ratio := minf(viewport.x / SOURCE_SIZE.x, viewport.y / SOURCE_SIZE.y)
	art.scale = Vector2.ONE * ratio
	art.position = (viewport - SOURCE_SIZE * ratio) * 0.5


## 每个功能台的外框（含隐藏的），用来放解锁虚线框。
func _measure_stations() -> void:
	for key in art.STATIONS:
		var group: Node = art.source_node(art.STATIONS[key])
		if group == null: continue
		var rect := Rect2()
		var first := true
		for s: Sprite2D in group.find_children("*", "Sprite2D", true, false):
			if s.texture == null: continue
			var size: Vector2 = s.texture.get_size() * s.global_scale.abs()
			var pos: Vector2 = art.to_local(s.global_position) - (size * 0.5 if s.centered else Vector2.ZERO)
			var r := Rect2(pos, size)
			rect = r if first else rect.merge(r)
			first = false
		_station_rects[key] = rect


func _build_frames() -> void:
	for key in Sim.STATION_ORDER:
		if not _station_rects.has(key): continue
		var frame: Button = UnlockFrame.new()
		var rect: Rect2 = _station_rects[key]
		if key == "topping":
			rect = Rect2(rect.position + Vector2(0, 140), Vector2(rect.size.x * 0.62, rect.size.y - 140))
		frame.position = rect.position
		frame.size = rect.size
		frame.add_theme_font_override("font", FONT)
		frame.add_theme_font_size_override("font_size", 26)
		frame.pressed.connect(_try_unlock.bind(key))
		frame.visible = false
		art.add_child(frame)
		_frames[key] = frame


func _sync_art() -> void:
	art.reset_layout()
	for key in sim.unlocked:
		if sim.unlocked[key]: art.set_station_unlocked(key, true)
	art.set_cushion_stage(sim.cushion_stage())
	var nxt := sim.next_unlock()
	for key in _frames:
		var frame: Button = _frames[key]
		frame.visible = key == nxt
		frame.text = "%s\n%d 金币" % [Sim.STATION_NAMES[key], sim.unlock_cost(key)]
		frame.can_unlock = sim.can_unlock(key)


func _try_unlock(key: String) -> void:
	if sim.unlock(key):
		_sync_art()
		_show_toast("开放了%s" % Sim.STATION_NAMES[key])
	else:
		_show_toast("还差 %d 金币" % (sim.unlock_cost(key) - int(sim.gold)))


# ---------- actors ----------

func _sync_actors() -> void:
	for s in sim.staff:
		var actor: Node2D = _staff_actors.get(s.id)
		if actor == null:
			actor = Actor.new()
			actor.setup(s.art, FONT, _staff_height)
			staff_layer.add_child(actor)
			_staff_actors[s.id] = actor
		var shown: Dictionary = s
		if s.phase == "work" and WORK_FACING.has(s.target):
			shown = s.duplicate()
			shown.facing = WORK_FACING[s.target]
		actor.display(shown, sim.clock)
	var alive := {}
	for c in sim.customers:
		alive[c.id] = true
		var actor: Node2D = _customer_actors.get(c.id)
		if actor == null:
			actor = Actor.new()
			actor.setup(Characters.customer_art(c.art_index), FONT, _customer_height)
			actors.add_child(actor)
			_customer_actors[c.id] = actor
		var walking: bool = c.pos.distance_to(c.spot) > 1.0
		actor.display({"pos": c.pos, "walking": walking, "seated": c.seated and not walking, "phase": "idle",
			"task_label": ""}, sim.clock)
		actor.task.visible = false
		if c.state == "queue":
			var left: float = 1.0 - c.wait / float(sim.cfg.patience)
			actor.show_order(c.kind, left, 0 if left > 0.5 else 1 if left > 0.2 else 2)
			_set_order_icon(actor, c)
		elif c.state == "paid":
			actor.show_order(c.kind, -1.0)
			_set_order_icon(actor, c)
		else:
			actor.show_order("", -1.0)
			actor._order_cup.visible = false
	for id in _customer_actors.keys():
		if not alive.has(id):
			_customer_actors[id].queue_free()
			_customer_actors.erase(id)


func _set_order_icon(actor: Node2D, c: Dictionary) -> void:
	var tex: Texture2D = _icons.get("soy" if c.kind == "soy" else "food")
	if tex == null: return
	actor._order_cup.texture = tex
	actor._order_cup.scale = Vector2.ONE * 40.0 / tex.get_height()


# ---------- HUD ----------

func _build_hud() -> void:
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	_hud.add_child(root)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	root.add_child(top)
	var top_box := VBoxContainer.new()
	top.add_child(top_box)
	var row := HBoxContainer.new()
	top_box.add_child(row)
	var coin := TextureRect.new()
	coin.texture = COIN
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.custom_minimum_size = Vector2(34, 34)
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(coin)
	_gold.add_theme_font_size_override("font_size", 28)
	_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_gold)
	_finish.text = "结店"
	_finish.visible = false
	_finish.pressed.connect(open_summary)
	row.add_child(_finish)
	_hint.add_theme_font_size_override("font_size", 21)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_box.add_child(_hint)
	_tasks.add_theme_font_size_override("font_size", 18)
	_tasks.add_theme_color_override("font_color", Color("7a5a40"))
	_tasks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_box.add_child(_tasks)

	var bottom := HBoxContainer.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 12
	bottom.offset_right = -12
	bottom.offset_top = -92
	bottom.offset_bottom = -12
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	for b in [_flyer, _hire, _upgrade_toggle]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 76
		b.focus_mode = Control.FOCUS_NONE
		bottom.add_child(b)
	_flyer.pressed.connect(func() -> void:
		if sim.send_flyers(): _show_toast("发传单：来了一波客人")
	)
	_hire.pressed.connect(func() -> void:
		if sim.hire(): _show_toast("招到新员工")
	)
	_upgrade_toggle.text = "升级"
	_upgrade_toggle.pressed.connect(func() -> void: _upgrade_panel.visible = not _upgrade_panel.visible)

	_upgrade_panel.visible = false
	_upgrade_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_upgrade_panel.offset_bottom = -104
	_upgrade_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_upgrade_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_upgrade_panel)
	_upgrade_list.add_theme_constant_override("separation", 8)
	_upgrade_panel.add_child(_upgrade_list)
	for key in sim.cfg.upgrades:
		var b := Button.new()
		b.custom_minimum_size = Vector2(520, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			if sim.upgrade(key): _show_toast("%s 升到 %d 级" % [sim.cfg.upgrades[key].name, sim.levels[key]])
		)
		_upgrade_list.add_child(b)
		_upgrade_buttons[key] = b

	_toast.visible = false
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", Color("fff6e5"))
	var toast_style := _style("624831e6", "624831", 18)
	_toast.add_theme_stylebox_override("normal", toast_style)
	root.add_child(_toast)
	_build_summary(root)


func _refresh_hud() -> void:
	_gold.text = "%d" % int(sim.gold)
	_hint.text = _hint_text()
	var lines := []
	for t in sim.cfg.tasks:
		if sim.task_done(t): continue
		var progress := "" if t.has("flavor") else " %d/%d" % [mini(int(sim.sold.get(t.dish, 0)), int(t.count)), int(t.count)]
		lines.append("%s%s" % [t.text, progress])
	_tasks.text = "任务 %d/%d：%s" % [sim.tasks_done(), sim.cfg.tasks.size(), "　".join(lines.slice(0, 2)) if not lines.is_empty() else "全部完成"]
	var cd := sim.flyer_cooldown_left()
	_flyer.text = "发传单" if cd <= 0.0 else "传单 %ds" % ceili(cd)
	_flyer.disabled = not sim.is_open() or cd > 0.0
	if sim.staff.size() >= sim.staff_slots():
		_hire.text = "员工 %d/%d" % [sim.staff.size(), sim.staff_slots()]
		_hire.disabled = true
	else:
		_hire.text = "招人 %d 金币" % sim.hire_cost()
		_hire.disabled = not sim.can_hire()
	var any_upgrade := false
	for key in _upgrade_buttons:
		var b: Button = _upgrade_buttons[key]
		var u: Dictionary = sim.cfg.upgrades[key]
		b.visible = sim.unlocked.get(key, false)
		if not sim.upgrade_available(key):
			b.text = "%s  已满级（%d 级）" % [u.name, sim.levels[key]]
			b.disabled = true
			continue
		b.text = "%s %d 级 → %d 级   %s   %d 金币" % [u.name, sim.levels[key], sim.levels[key] + 1, UPGRADE_TEXT[u.effect], sim.upgrade_cost(key)]
		if key == "topping":
			var next_flavor := _next_flavor()
			if not next_flavor.is_empty(): b.text += "\n开放 " + next_flavor
		b.disabled = not sim.can_upgrade(key)
		any_upgrade = any_upgrade or sim.can_upgrade(key)
	_upgrade_toggle.text = "升级 ↑" if any_upgrade else "升级"
	var nxt := sim.next_unlock()
	if _frames.has(nxt): _frames[nxt].can_unlock = sim.can_unlock(nxt)
	if sim.events.size() != _last_event:
		_last_event = sim.events.size()
		_sync_art()
	_finish.visible = sim.completed_at >= 0.0
	if sim.completed_at >= 0.0 and not _done_shown:
		_done_shown = true
		if sim.clock - sim.completed_at < 2.0:
			_show_toast("完店了！可以点“结店”去奶茶店，也可以接着营业", 4.0)


func _next_flavor() -> String:
	for dish in Sim.DISHES:
		var d: Dictionary = Sim.DISHES[dish]
		if d.has("lv") and int(d.lv) == sim.levels.topping + 1: return d.name
	return ""


func _hint_text() -> String:
	if not sim.is_open(): return "点亮豆浆机开张（10 金币）"
	var nxt := sim.next_unlock()
	var bottleneck := _bottleneck()
	if not bottleneck.is_empty(): return bottleneck
	if not nxt.is_empty(): return "攒 %d 金币开放%s" % [sim.unlock_cost(nxt), Sim.STATION_NAMES[nxt]]
	if sim.completed_at >= 0.0: return "完店了！点右上角“结店”去奶茶店，也可以接着营业"
	return "菜单已全开，完成任务就完店"


func _bottleneck() -> String:
	var waiting_griddle := 0
	var waiting_crisps := 0
	for s in sim.staff:
		if s.task_label == "等鏊子": waiting_griddle += 1
		if s.task_label == "等薄脆": waiting_crisps += 1
	if sim.queue.size() >= sim.queue_capacity() - 1:
		if sim.staff.size() < sim.staff_slots(): return "队伍满了：人手不够，招人"
		if waiting_griddle > 0 and sim.upgrade_available("rear_equipment"): return "队伍满了：都在等鏊子，升级鏊子"
	if waiting_crisps > 0 and sim.upgrade_available("fryer"): return "薄脆供不上：升级油锅"
	return ""


func _show_toast(text: String, seconds := 1.6) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.reset_size()
	_toast.position = (get_viewport_rect().size - _toast.size) * Vector2(0.5, 0.42)
	_toast_time = seconds


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 23
	for type in ["Label", "Button"]:
		t.set_color("font_color", type, Color("583e2d"))
	t.set_color("font_hover_color", "Button", Color("583e2d"))
	t.set_color("font_pressed_color", "Button", Color("fff8e9"))
	t.set_color("font_disabled_color", "Button", Color("978b7c"))
	t.set_stylebox("panel", "PanelContainer", _style("fff5e2f0", "b38c62", 22))
	t.set_stylebox("normal", "Button", _style("f3e5cb", "dec6a3", 15))
	t.set_stylebox("hover", "Button", _style("fff6df", "b58b5d", 15))
	t.set_stylebox("pressed", "Button", _style("8b6446", "8b6446", 15))
	t.set_stylebox("disabled", "Button", _style("e5dfd2", "d9cdbb", 15))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return t


func _style(background: String, border: String, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(background)
	box.border_color = Color(border)
	box.set_border_width_all(2)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


# ---------- 存档、引导定位 ----------

func save_now() -> void:
	if store != null and sim != null: store.save(sim, guide.seen_list())


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		save_now()


## 解锁虚线框在屏幕上的位置（引导挖洞用）。
func frame_screen_rect(key: String) -> Rect2:
	var frame: Control = _frames.get(key)
	if frame == null: return Rect2()
	return frame.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, frame.size)


func hire_screen_rect() -> Rect2:
	return _hire.get_global_rect()


# ---------- 结店 ----------

func _build_summary(root: Control) -> void:
	_summary.visible = false
	_summary.custom_minimum_size = Vector2(600, 0)
	_summary.add_theme_stylebox_override("panel", _style("fff5e2", "8b6446", 26))
	root.add_child(_summary)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_summary.add_child(column)
	var title := Label.new()
	title.text = "结店总结 · 煎饼果子摊"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_summary_text.add_theme_font_size_override("font_size", 23)
	_summary_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_text.custom_minimum_size.x = 560
	column.add_child(_summary_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var stay := Button.new()
	stay.text = "继续营业"
	stay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stay.custom_minimum_size.y = 72
	stay.pressed.connect(func() -> void: _summary.visible = false)
	buttons.add_child(stay)
	_summary_leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_leave.custom_minimum_size.y = 72
	_summary_leave.pressed.connect(_leave_pressed)
	buttons.add_child(_summary_leave)


func open_summary() -> void:
	var d: Dictionary = sim.summary()
	var lines := []
	lines.append("评分　%s" % ("★".repeat(int(d.rating)) + "☆".repeat(3 - int(d.rating))))
	lines.append("完店用时　%d 分 %02d 秒" % [int(d.seconds) / 60, int(d.seconds) % 60])
	lines.append("营业额　%d 金币" % int(d.earned))
	lines.append("卖出　%d 份（走掉 %d 位客人）" % [int(d.sold), int(d.lost)])
	var top := []
	for row in d.top: top.append("%s ×%d" % [Sim.DISHES[row[1]].name, int(row[0])])
	if not top.is_empty(): lines.append("卖得最好　" + "、".join(top))
	var lv := []
	for key in sim.cfg.upgrades: lv.append("%s %d 级" % [sim.cfg.upgrades[key].name, int(d.levels[key])])
	lines.append("台子　" + "、".join(lv))
	lines.append("员工　%d 位，到奶茶店要重新招" % int(d.staff))
	_summary_text.text = "\n".join(lines)
	_leave_armed = false
	_summary_leave.text = "去奶茶店"
	_summary.visible = true
	_summary.reset_size()
	_summary.position = (get_viewport_rect().size - _summary.size) * 0.5


## 第一下提示离开后不保留，第二下才真的走。
func _leave_pressed() -> void:
	if not _leave_armed:
		_leave_armed = true
		_summary_leave.text = "确定离开（金币、台子、员工都不保留）"
		return
	leave_shop()


func leave_shop() -> void:
	var record: Dictionary = sim.summary()
	record.erase("levels")
	profile.finish_shop(record)
	if store != null: store.clear()
	store = null
	get_tree().change_scene_to_file(TEA_SCENE)
