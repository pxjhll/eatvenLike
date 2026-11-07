extends Control
## 煎饼摊新手引导，流程照奶茶店：欢迎 → 点豆浆机开张 → 看第一单卖出去 → 招第二个人 → 完成。
## 每一步都从当前店铺状态判断，读档或关掉面板后会回到对的那一步；看过的步骤记在店内存档里。

const DIM := Color(0.16, 0.1, 0.06, 0.62)
const GLOW := Color("ffd98a")

var seen := {}
var active := ""
var _play: Node2D
var _hole := Rect2()
var _blocking := false
var _time := 0.0
var _bubble := PanelContainer.new()
var _bubble_text := Label.new()
var _card := PanelContainer.new()
var _card_title := Label.new()
var _card_body := Label.new()
var _card_button := Button.new()
var _show_card_now := false
var _show_bubble_now := false


func setup(play: Node2D, seen_ids: Array, style: Callable) -> void:
	_play = play
	for id in seen_ids: seen[String(id)] = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bubble.add_theme_stylebox_override("panel", style.call("fff5e2", "8b6446", 20))
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.custom_minimum_size.x = 460
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_text.add_theme_font_size_override("font_size", 24)
	_bubble.add_child(_bubble_text)
	add_child(_bubble)
	_card.add_theme_stylebox_override("panel", style.call("fff5e2", "8b6446", 26))
	_card.custom_minimum_size = Vector2(560, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_card.add_child(column)
	_card_title.add_theme_font_size_override("font_size", 32)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_card_title)
	_card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_body.add_theme_font_size_override("font_size", 23)
	column.add_child(_card_body)
	_card_button.custom_minimum_size.y = 72
	_card_button.pressed.connect(_confirm)
	column.add_child(_card_button)
	add_child(_card)
	refresh(0.0)


func seen_list() -> Array:
	return seen.keys()


## 卡片和要求点某处的步骤会暂停营业。
func freezes() -> bool:
	return _blocking


func refresh(delta: float) -> void:
	_time += delta
	_show_card_now = false
	_show_bubble_now = false
	_pick()
	# 只在状态真的变了时才改 visible：每帧先隐藏再显示会让按钮丢掉按下状态，点了没反应
	if _card.visible != _show_card_now: _card.visible = _show_card_now
	if _bubble.visible != _show_bubble_now: _bubble.visible = _show_bubble_now
	var want := not active.is_empty()
	if visible != want: visible = want
	queue_redraw()


func _pick() -> void:
	var sim: PancakeSim = _play.sim
	active = ""
	_blocking = false
	_hole = Rect2()
	if not seen.has("welcome"):
		_show_card("welcome", "欢迎来到煎饼果子摊", "早点摊刚支起来，先卖豆浆，攒钱再开鏊子、油锅和加料台。\n员工会自己接单，从收钱一直做到递餐。", "开始")
		return
	if not sim.is_open():
		active = "open"
		_blocking = true
		_hole = _play.frame_screen_rect("soy_milk").grow(10)
		_say("点豆浆机，花 10 金币开张")
		return
	if not seen.has("first_sale"):
		if sim.total_sold() == 0:
			active = "first_sale"
			_say("员工去前台收钱、打豆浆。\n看第一单卖出去")
			return
		seen["first_sale"] = true
	if not seen.has("hire") and sim.unlocked.get("rear_equipment", false) and sim.staff.size() < 2:
		if sim.can_hire():
			active = "hire"
			_blocking = true
			_hole = _play.hire_screen_rect().grow(8)
			_say("一个人又收钱又摊饼，忙不过来了。\n招第二个人")
		return
	if not seen.has("hire") and sim.staff.size() >= 2:
		seen["hire"] = true
	if seen.has("hire") and not seen.has("done"):
		_show_card("done", "开张完成", "之后每分钟回来看一眼就行：\n攒够钱开下一台；队伍排满了就招人；“升级 ↑”亮了就升级台子。", "知道了")


func _show_card(id: String, title: String, body: String, button: String) -> void:
	active = id
	_blocking = true
	_card_title.text = title
	_card_body.text = body
	_card_button.text = button
	_show_card_now = true
	_card.reset_size()
	_card.position = (size - _card.size) * 0.5


func _say(text: String) -> void:
	_bubble_text.text = text
	_show_bubble_now = true
	_bubble.reset_size()
	var x := (size.x - _bubble.size.x) * 0.5
	var y := size.y * 0.42
	if _hole.has_area():
		y = _hole.end.y + 24 if _hole.end.y + 24 + _bubble.size.y < size.y - 120 else _hole.position.y - _bubble.size.y - 24
	_bubble.position = Vector2(x, y)


func _confirm() -> void:
	ShopAudio.play_cue(&"tap")
	seen[active] = true
	_play.save_now()
	refresh(0.0)


func _draw() -> void:
	if not _blocking: return
	if not _hole.has_area():
		draw_rect(Rect2(Vector2.ZERO, size), DIM)
		return
	# 四块遮罩围出一个洞，洞里的按钮照常能点
	draw_rect(Rect2(0, 0, size.x, _hole.position.y), DIM)
	draw_rect(Rect2(0, _hole.end.y, size.x, size.y - _hole.end.y), DIM)
	draw_rect(Rect2(0, _hole.position.y, _hole.position.x, _hole.size.y), DIM)
	draw_rect(Rect2(_hole.end.x, _hole.position.y, size.x - _hole.end.x, _hole.size.y), DIM)
	var pulse := 3.0 + 2.0 * sin(_time * 5.0)
	draw_rect(_hole, GLOW, false, pulse)


func _has_point(point: Vector2) -> bool:
	if not visible: return false
	if not _blocking: return false
	if _show_card_now: return true
	return not _hole.has_point(point)
