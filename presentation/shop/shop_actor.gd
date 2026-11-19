extends Node2D
## 员工和客人（通用）：参考图的动物，脚底是排序点。端着的杯子、头顶的字、干活朝向都从外面给（店铺数据）。

## The view is orthographic, so a cup is the same size on a belt, a shelf or in a paw.
const ItemArt := preload("res://game/rules/shop_item_art.gd")
const CUP_HEIGHT := 52.0
## Hand centers in frame_actor order: front, front-right, right, back-right, then back to front-left.
const HELD_CENTERS := [
	Vector2(0, -44), Vector2(46, -50), Vector2(46, -50), Vector2(40, -54),
	Vector2(0, -50), Vector2(-40, -54), Vector2(-46, -50), Vector2(-46, -50),
]
const Characters := preload("res://presentation/characters/character_library.gd")
const Presentation := preload("res://content/characters/actor_presentation.tres")
const BUBBLE := preload("res://art/ui/bubble.png")
const CUSTOMER_MOOD := preload("res://art/ui/customer_mood.png")
const MOOD_SIZE := Vector2(40.0, 40.0)
const PATIENCE_WIDTH := 42.0
const PATIENCE_GREEN := Color("6b8f4e")
const PATIENCE_AMBER := Color("d08a2e")
const PATIENCE_RED := Color("b4482f")
## 外面给的查表：物品 → {art, tint}；任务 → 头顶的字；机器 → 干活时朝哪个方向（8 方向）
var item_art: Callable = func(_item: String) -> Dictionary: return {}
var task_text: Callable = func(worker: Dictionary) -> String: return String(worker.get("task_label", ""))
var work_direction: Callable = func(_station: String) -> int: return -1
## 正在“接”现成饮品（从展示柜接）的员工也算在干活：{src: 机器 id, items: [...]} 由外面判断
var pouring_station: Callable = func(_worker: Dictionary) -> String: return ""
## 订单气泡里的图：物品 → 贴图（默认 art/ui/drink_<id>.png）
var order_icon: Callable = func(item: String) -> Texture2D: return drink_icon(item)
## 手上这步活干了多少（0–1；-1 = 没在干、不画进度条）
var work_progress: Callable = func(_worker: Dictionary) -> float: return -1.0
## 头顶的进度条（外面给主题）
var progress_bar := ProgressBar.new()
var body := Sprite2D.new()
var carried := Sprite2D.new()
var _held_layer := Node2D.new()
var _held_sprites: Array[Sprite2D] = []
var amount := Label.new()
var task := Label.new()
var selected := false:
	set(value):
		if selected == value: return
		selected = value
		_visual.queue_redraw()
var _last_pos := Vector2.ZERO
var _base_scale := Vector2.ONE
var _font: Font
var _art := ""
var _height := 128.0
var frame_actor: Node2D
var _pose_initialized := false
var _last_clock := 0.0
## A customer's order bubble: the drink they want and how much patience is left (-1 = no limit).
var _order_item := ""
var _patience := -1.0
## 0 calm, 1 impatient, 2 angry; customers never leave, they show it on their face instead.
var _mood := 0
var _order_scale := 1.0
var _takeaway := false
var _order_cup := Sprite2D.new()
## All visible attachments share this offset; the actor root stays authoritative.
var _visual := Node2D.new()

func set_render_position(point: Vector2) -> void:
	_visual.position = (point-position)/scale

func render_position() -> Vector2:
	return position+_visual.position*scale


## Turns a single-image animal to look right (true) or left (false). Every animal image is drawn facing right.
func face(right: bool) -> void:
	body.flip_h = not right


func setup(art_id: String, font: Font, height := -1.0) -> void:
	if height < 0.0: height = Presentation.staff_height
	_font = font
	_visual.draw.connect(_draw_visual)
	add_child(_visual)
	_art = art_id
	_height = height
	body.texture = Characters.portrait(art_id) if art_id in Characters.IDS else load("res://art/reference/" + art_id + ".png")
	_base_scale = Vector2.ONE * height / body.texture.get_height()
	body.scale = _base_scale
	body.centered = false
	body.position = Vector2(-body.texture.get_width() * _base_scale.x / 2.0, -height)
	_visual.add_child(body)
	if art_id in Characters.FRAME_SCENES:
		body.visible = false
		frame_actor = Characters.FRAME_SCENES[art_id].instantiate()
		frame_actor.scale = Vector2.ONE * height / Characters.frame_height(art_id)
		_visual.add_child(frame_actor)
	carried.centered = false
	carried.visible = false
	_visual.add_child(_held_layer)
	_held_layer.add_child(carried)
	amount.position = Vector2(38, -59)
	amount.add_theme_font_override("font", font)
	amount.add_theme_font_size_override("font_size", 17)
	amount.add_theme_color_override("font_color", Color("fff5d8"))
	amount.add_theme_color_override("font_outline_color", Color("573b2b"))
	amount.add_theme_constant_override("outline_size", 4)
	_visual.add_child(amount)
	task.position = Vector2(-78, -height - 28)
	task.size.x = 156
	task.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task.add_theme_font_override("font", font)
	task.add_theme_font_size_override("font_size", 16)
	task.add_theme_color_override("font_color", Color("4e3425"))
	task.add_theme_color_override("font_outline_color", Color("fff1d8"))
	task.add_theme_constant_override("outline_size", 5)
	_visual.add_child(task)
	_order_cup.centered = false
	_order_cup.visible = false
	_visual.add_child(_order_cup)
	progress_bar.max_value = 1.0
	progress_bar.show_percentage = false
	progress_bar.size = Vector2(84, 12)
	progress_bar.position = Vector2(-42, -height - 18)
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.visible = false
	_visual.add_child(progress_bar)


func show_order(item: String, patience: float, mood := 0, takeaway := false, compact := false) -> void:
	task.visible = false
	var item_changed := item != _order_item
	_order_item = item
	_order_cup.visible = not item.is_empty()
	if item.is_empty():
		if item_changed: _visual.queue_redraw()
		return
	var scale_factor := 0.72 if compact else 1.0
	var size_changed := scale_factor != _order_scale
	if item_changed:
		_order_cup.texture = order_icon.call(item)
	if item_changed or size_changed:
		_order_cup.scale = Vector2.ONE * 40.0 * scale_factor / _order_cup.texture.get_height()
		var icon_width := _order_cup.texture.get_width() * _order_cup.scale.x
		var inset := maxf(0.0, (40.0 * scale_factor - icon_width) / 2.0)
		_order_cup.position = Vector2(-46.0 * scale_factor + inset, -_height - 4.0 - 58.0 * scale_factor)
	patience = clampf(patience, 0.0, 1.0) if patience >= 0.0 else -1.0
	var redraw := item_changed or size_changed or mood != _mood or takeaway != _takeaway
	if not redraw and patience != _patience:
		# Retain the fill until its tip moves a screen pixel, with immediate
		# updates to colors and empty/full states.
		redraw = patience <= 0.0 or patience >= 1.0 or _patience < 0.0 \
			or _patience_color(patience) != _patience_color(_patience) \
			or absf(patience - _patience) * PATIENCE_WIDTH * scale_factor * get_screen_transform().x.length() >= 1.0
	if redraw:
		_patience = patience
		_mood = mood
		_takeaway = takeaway
		_order_scale = scale_factor
		_visual.queue_redraw()


func display(worker: Dictionary, clock: float, displayed_position := Vector2.INF) -> void:
	position = worker.pos
	set_render_position(position if displayed_position == Vector2.INF else displayed_position)
	var movement: Vector2 = position - _last_pos
	var clock_step := maxf(0.0, clock - _last_clock) if _pose_initialized else 0.0
	if not _pose_initialized:
		movement = Vector2.ZERO
	_pose_initialized = true
	if absf(movement.x) > 0.1:
		face(movement.x > 0)
	var walking: bool = worker.get("walking", false)
	var bob := sin(clock * 15.0) * 2.5 if walking and frame_actor == null else 0.0
	if frame_actor != null:
		_display_frames(worker, movement, clock_step)
	var working: bool = worker.get("display_working",worker.get("phase", "idle") in ["work", "pickup", "dropoff"])
	body.position.y = -body.texture.get_height() * _base_scale.y + bob
	body.rotation = sin(clock * 10.0) * 0.025 if working else 0.0
	task.text = task_text.call(worker)
	var done: float = work_progress.call(worker)
	progress_bar.visible = done >= 0.0
	if progress_bar.visible: progress_bar.value = done
	var item: String = worker.get("carry_item", "")
	var count: int = worker.get("carry_count", 0)
	# 这一步把手上的东西放进机器里做了，手上就不画
	var steps: Array = worker.get("steps", [])
	var at: int = worker.get("step", 0)
	var in_machine: bool = worker.get("presentation_version")!=1 and worker.get("phase", "") == "work" and at < steps.size() and (bool(steps[at].get("into_machine", false)) or bool(steps[at].get("put_down", false)))
	carried.visible = not item.is_empty() and count > 0 and not in_machine
	amount.visible = carried.visible and count > 1
	amount.text = "×%d" % count
	if carried.visible:
		var art: Dictionary = item_art.call(item)
		var texture: Texture2D = ItemArt.texture_from_look(art)
		carried.texture = texture
		carried.modulate = art.get("tint", Color.WHITE)
		# 按长边量：杯子还是 52 高，横着的饼、袋子不会比杯子宽一大截挡住脸
		carried.scale = Vector2.ONE * CUP_HEIGHT / maxf(texture.get_height(), texture.get_width())
		carried.position = Vector2(22, -78 + bob)
		if frame_actor != null:
			var facing: int = frame_actor.direction
			var center: Vector2 = HELD_CENTERS[facing]
			if facing == 0:
				center.y += float(art.get("held_front_drop", 0.0))
			carried.position = center - texture.get_size() * carried.scale / 2.0
			amount.position = center + Vector2(10, 10)
			var behind: bool = facing in [3, 4, 5]
			if behind != (_held_layer.get_index() < frame_actor.get_index()):
				_visual.move_child(_held_layer, frame_actor.get_index())
	_display_held_items(worker)
	_last_pos = position
	_last_clock = clock

func _display_held_items(worker: Dictionary) -> void:
	var items: Array = worker.get("held_items",[]) if worker.get("presentation_version")==1 and carried.visible else []
	while _held_sprites.size()<maxi(0,items.size()-1):
		var sprite := Sprite2D.new()
		sprite.centered = false
		_held_layer.add_child(sprite)
		_held_sprites.append(sprite)
	for index in _held_sprites.size():
		var sprite := _held_sprites[index]
		sprite.visible = index+1<items.size()
		if not sprite.visible: continue
		var look: Dictionary = item_art.call(items[index+1].item)
		var texture: Texture2D = ItemArt.texture_from_look(look)
		sprite.texture = texture
		sprite.modulate = look.get("tint",Color.WHITE)
		sprite.scale = Vector2.ONE*CUP_HEIGHT/maxf(texture.get_width(),texture.get_height())
		var left_facing: bool = frame_actor.direction > 4 if frame_actor != null else body.flip_h
		var spacing := Vector2(-18 if left_facing else 18, -4)
		sprite.position = carried.position + spacing * (index + 1)


func _display_frames(worker: Dictionary, movement: Vector2, clock_step: float) -> void:
	var vector := movement
	var path: PackedVector2Array = worker.get("path", PackedVector2Array())
	var path_index: int = worker.get("path_index", 0)
	if worker.get("walking", false) and path_index < path.size():
		var to_next: Vector2 = path[path_index] - position
		if to_next.length_squared() > 0.01:
			vector = to_next
	if vector.length_squared() > 0.01:
		var direction := posmod(roundi(atan2(vector.x, vector.y) / (PI / 4.0)), 8)
		if direction != frame_actor.direction:
			frame_actor.set_direction(direction)
	if worker.has("facing") and frame_actor.direction != int(worker.facing):
		frame_actor.set_direction(int(worker.facing))
	var walking: bool = worker.get("walking", false)
	var desired := "walk" if walking else "sit" if worker.get("seated", false) else "idle"
	var job: Dictionary = worker.get("job", {})
	var poured: String = pouring_station.call(worker)
	var working: bool = worker.get("display_working",worker.get("phase", "idle") in ["work","pickup","dropoff"]) if worker.get("presentation_version")==1 else (worker.get("phase", "idle") == "work" or not poured.is_empty())
	if not walking and not worker.get("seated", false) and frame_actor.has_action("work") and working:
		desired = "work"
		# 一人跟单的店没有 job：在哪个点干活就按哪台机器的朝向
		var station: String = String(worker.work_station) if worker.get("presentation_version")==1 else (poured if not poured.is_empty() else String(job.get("src", worker.get("target", ""))))
		var direction: int = work_direction.call(station)
		if not worker.has("facing") and direction >= 0:
			frame_actor.set_direction(direction)
	if not frame_actor.has_action(desired): desired = "walk"
	if frame_actor.action != desired:
		frame_actor.set_action(desired)
		frame_actor.seek_phase(0.0)
	if frame_actor.sprite.is_playing(): frame_actor.pause()
	if walking or desired != "walk":
		if clock_step > 0.0:
			var factor := float(worker.get("speed", Characters.walk_speed(_art))) / Characters.walk_speed(_art) if walking else 1.0
			frame_actor.seek_phase(fposmod(frame_actor.get_phase() + clock_step * factor / frame_actor.get_cycle_seconds(), 1.0))
	elif frame_actor.sprite.frame != 0 or frame_actor.sprite.frame_progress != 0.0:
		frame_actor.seek_phase(0.0)


## Standalone actors use existing legacy icons or a neutral placeholder.
static func drink_icon(item: String) -> Texture2D:
	return ItemArt.legacy_icon(item)


func _draw_visual() -> void:
	_visual.draw_set_transform(Vector2(0, 1), 0, Vector2(1, 0.3))
	_visual.draw_circle(Vector2.ZERO, 25, Color(0.24, 0.14, 0.07, 0.18))
	if selected:
		_visual.draw_arc(Vector2.ZERO, 31, 0, TAU, 40, Color("e6b94f"), 6, true)
	if _order_item.is_empty():
		return
	var anchor := Vector2(0.0,-_height-4.0)
	_visual.draw_set_transform(anchor*(1.0-_order_scale),0.0,Vector2.ONE*_order_scale)
	var top := -_height - 64.0
	_visual.draw_texture_rect(BUBBLE, Rect2(-48, top, 96, 60), false)
	if _patience >= 0:
		_visual.draw_rect(Rect2(-4, top + 19, PATIENCE_WIDTH, 10), Color("efe3cc"))
		_visual.draw_rect(Rect2(-4, top + 19, PATIENCE_WIDTH * _patience, 10), _patience_color(_patience))
	if _takeaway and _font != null:
		_visual.draw_string(_font, Vector2(-2, top + 30), "外带", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("8a5a35"))
	if _mood > 0:
		_draw_mood(Vector2(40, top + 8))

static func _patience_color(fill: float) -> Color:
	return PATIENCE_GREEN if fill > 0.6 else PATIENCE_AMBER if fill > 0.3 else PATIENCE_RED


## Both faces share one atlas. Keep the original center and bubble draw order.
func _draw_mood(center: Vector2) -> void:
	var tile := Vector2(CUSTOMER_MOOD.get_width() * 0.5, CUSTOMER_MOOD.get_height())
	var source := Vector2(tile.x if _mood >= 2 else 0.0, 0.0)
	_visual.draw_texture_rect_region(CUSTOMER_MOOD, Rect2(center - MOOD_SIZE * 0.5, MOOD_SIZE), Rect2(source, tile))
