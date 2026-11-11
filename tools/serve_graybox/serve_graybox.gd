extends Node2D
## 送桌店（serve）灰盒观察器：直接画规则层状态，不走正式界面，只给原型验证看。
## 打开 tools/serve_graybox/serve_graybox.tscn 运行（或 godot --path . tools/serve_graybox/serve_graybox.tscn）。
## 按钮：招帮厨（招人并上岗流动）、倍速、重开。
## 店铺数据有 scene_path 时，把美术场景缩放进 720×1280 当底图，状态画在上面；没有就画纯灰盒。

const ServeFlow := preload("res://game/rules/serve_flow.gd")
const SHOP_PATH := "res://content/shops/stirfry/shop.tres"
const COLORS := {"queue": Color(0.55, 0.55, 0.6), "to_pickup": Color(0.6, 0.45, 0.85), "await": Color(0.85, 0.3, 0.6), "to_seat": Color(0.35, 0.55, 0.95), "seated": Color(0.95, 0.6, 0.2), "eating": Color(0.3, 0.75, 0.35)}

var rules: ShopRules
var speed := 1.0
var font: Font
var _hud: Label
var _art: Node2D
var _anchors: ShopAnchors


func _ready() -> void:
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Noto Sans CJK SC", "PingFang SC", "Microsoft YaHei", "WenQuanYi Zen Hei", "Source Han Sans SC", "sans-serif"])
	font = system
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 22
	# 按钮和文字放在 CanvasLayer 上，不跟底图一起缩放
	var ui := CanvasLayer.new()
	add_child(ui)
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 1210)
	bar.add_theme_constant_override("separation", 12)
	ui.add_child(bar)
	for row in [["招帮厨", _hire], ["倍速", _faster], ["重开", _restart]]:
		var b := Button.new()
		b.text = row[0]
		b.theme = theme
		b.custom_minimum_size = Vector2(150, 56)
		b.pressed.connect(row[1])
		bar.add_child(b)
	_hud = Label.new()
	_hud.theme = theme
	_hud.position = Vector2(12, 8)
	ui.add_child(_hud)
	var legend := Label.new()
	legend.theme = theme
	legend.add_theme_font_size_override("font_size", 16)
	legend.position = Vector2(12, 1170)
	legend.text = "圆点：灰=排队  紫=去取餐  粉=等取餐  蓝=去座位  橙=等餐  绿=用餐   红点=桌上的菜"
	ui.add_child(legend)
	_load_art(load(SHOP_PATH))
	_restart()


func _load_art(shop: SpecShop) -> void:
	if shop.scene_path.is_empty() or not ResourceLoader.exists(shop.scene_path): return
	_art = load(shop.scene_path).instantiate()
	_art.show_behind_parent = true
	add_child(_art)
	_anchors = ShopAnchors.new(_art.get_node_or_null("Anchors"))
	var world := Vector2(720, 1280)
	if _anchors.root != null: world = _anchors.root.get_meta("world_size", world)
	var k := minf(720.0 / world.x, 1280.0 / world.y)
	scale = Vector2(k, k)
	position = Vector2((720.0 - world.x * k) / 2.0, 0)


func _restart() -> void:
	rules = ShopRules.new(load(SHOP_PATH))
	rules.unlock(rules.shop.goals.opening_station)
	speed = 1.0


func _hire() -> void:
	rules.gold = maxf(rules.gold, float(rules.hire_cost()))
	if rules.hire().is_empty(): rules.deploy_worker(rules.roster[-1].id)


func _faster() -> void:
	speed = 1.0 if speed >= 8.0 else speed * 2.0


func _process(delta: float) -> void:
	rules.step(delta * speed)
	var s: Dictionary = rules.serve
	_hud.text = "%s 原型  %d:%02d  ×%d\n金币 %d   吃上 %d 人   卖出 %d 份   流失 %d 人   排队 %d" % [rules.shop.display_name,
		int(rules.clock) / 60, int(rules.clock) % 60, int(speed), int(rules.gold), int(s.served), int(s.items_sold), rules.lost, ServeFlow.queue_size(rules)]
	queue_redraw()


func _name(item: String) -> String:
	for it in rules.shop.items:
		if it.id == item: return it.display_name
	return item


func _text(at: Vector2, text: String, size := 18, color := Color(0.15, 0.15, 0.18)) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw() -> void:
	if rules == null: return
	var shop := rules.shop
	if _art == null:
		draw_rect(Rect2(0, 0, 720, 1280), Color(0.97, 0.95, 0.9))
		draw_rect(Rect2(0, 90, 720, 400), Color(0.93, 0.88, 0.8))
		_text(Vector2(12, 120), "后厨", 20, Color(0.5, 0.4, 0.3))
		_text(Vector2(12, 760), "堂食", 20, Color(0.5, 0.4, 0.3))
	var alpha := 0.8 if _art != null else 1.0
	# 机器
	for st in shop.stations:
		var p := rules.nav.point(st.id)
		var box := Rect2(p + Vector2(-62, -78), Vector2(124, 58))
		var on := rules.station_unlocked(st.id)
		draw_rect(box, Color(0.82, 0.86, 0.95, alpha) if on else Color(0.85, 0.85, 0.85, alpha))
		draw_rect(box, Color(0.3, 0.3, 0.35), false, 2.0)
		_text(box.position + Vector2(6, 22), st.display_name, 18)
		var row: Dictionary = rules.stations[st.id]
		var sub := ""
		match st.block:
			"batch_pot":
				var stock := ServeFlow.stock(rules, st.id)
				sub = "可用%d 预留%d 在制%d" % [stock.available, stock.reserved, stock.cooking]
				if row.phase == "cook": draw_rect(Rect2(box.position + Vector2(0, 54), Vector2(124 * float(row.progress), 4)), Color(0.9, 0.5, 0.2))
			"hand", "combine":
				if int(row.user) != -1: sub = "有人在做"
		if not sub.is_empty(): _text(box.position + Vector2(6, 46), sub, 14, Color(0.3, 0.3, 0.4))
		# 放在这台的东西
		var chips: Array = ServeFlow.goods_at(rules, st.id, "", -1).filter(func(g: Dictionary) -> bool: return st.block != "batch_pot")
		for g in rules.serve.goods:
			if g.at == st.id and int(g.owner) != -1: chips.append(g)
		for i in chips.size():
			var c := box.position + Vector2(130, 6 + i * 20)
			draw_rect(Rect2(c, Vector2(84, 18)), Color(1, 1, 0.85))
			_text(c + Vector2(3, 15), _name(chips[i].item), 13)
	# 座位
	for n in rules.seat_total():
		var p := rules.nav.point(ServeFlow.seat_point(shop, n))
		if _art == null: draw_rect(Rect2(p - Vector2(22, 22), Vector2(44, 44)), Color(0.8, 0.7, 0.55))
		else: draw_arc(p, 26, 0, TAU, 24, Color(0.95, 0.85, 0.3), 3.0)
	for g in rules.serve.goods:
		if String(g.at).begins_with("seat:"):
			var p := rules.nav.point(ServeFlow.seat_point(shop, int(String(g.at).substr(5))))
			draw_circle(p + Vector2(0, -30), 9, Color(0.95, 0.35, 0.25))
	# 顾客
	var q := 0
	var counter := rules.nav.point(rules.counter_id)
	var queue_points: Array[Vector2] = []
	if _anchors != null: queue_points = _anchors.points("Queue")
	for g in rules.serve.guests:
		var pos: Vector2
		if g.state == "queue":
			pos = queue_points[mini(q, queue_points.size() - 1)] if not queue_points.is_empty() else counter + Vector2(-20, 70 + q * 46)
			q += 1
		else:
			var seat := rules.nav.point(ServeFlow.seat_point(shop, int(g.seat)))
			var window := rules.nav.point(ServeFlow.pickup_of(shop))
			# 自取店：接单后先走到出餐口等，端走以后才从出餐口走去座位
			var from := window if ServeFlow.self_pickup(shop) else counter
			pos = seat
			if g.state == "to_seat": pos = seat.lerp(from, float(g.walk_left) / maxf(0.001, float(g.walk_total)))
			elif g.state == "to_pickup": pos = window.lerp(counter, float(g.walk_left) / maxf(0.001, float(g.walk_total)))
			elif g.state == "await": pos = window + Vector2(0, 60)
		draw_circle(pos, 16, COLORS.get(g.state, Color.GRAY))
	# 员工
	for w in rules.workers:
		var p: Vector2 = w.pos
		draw_circle(p, 22, Color(0.25, 0.3, 0.45))
		_text(p + Vector2(-20, 7), String(w.name).substr(0, 2), 16, Color.WHITE)
		var job := ServeFlow.job_of(rules, w)
		var label: String = w.task_label if w.task_label != "idle" else "空闲"
		_text(p + Vector2(-30, -28), label, 15, Color(0.1, 0.1, 0.4))
		if not String(w.carry_item).is_empty():
			draw_rect(Rect2(p + Vector2(18, -10), Vector2(84, 18)), Color(1, 1, 0.85))
			_text(p + Vector2(21, 5), _name(w.carry_item), 13)
