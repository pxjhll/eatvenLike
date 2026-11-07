extends Node2D
## 通用店铺场景（规格 §6）：哪家店都用这一个场景。店铺数据（SpecShop）决定规则，shop.scene_path 的美术场景
## 决定画面，美术场景里的 Anchors 决定位置；这里不写任何店名、机器名和坐标。
## 规则层 ShopRules 管全部状态和时间，界面只读 ShopView 快照、只发命令（§3.11）。
##
## 打开方式：
## - 正式游戏：读 App.profile.shop 那家店的数据和它的存档（ShopSave），放引导
## - 只塞 store：读这个存档，放引导（测试读档用）
## - 塞 rules：直接用这家店，不放引导（测试用；同时塞 store 才会存档）

const Actor := preload("res://presentation/shop/shop_actor.gd")
const Dining := preload("res://presentation/shop/shop_dining.gd")
const DragController := preload("res://presentation/shop/staff_drag.gd")
const Guide := preload("res://presentation/shop/guide_player.gd")
const UnlockFrame := preload("res://presentation/shop/unlock_frame.gd")
const UpgradeBadge := preload("res://presentation/shop/upgrade_badge.gd")
const TuningPanel := preload("res://presentation/shop/shop_tuning.gd")
const Recorder := preload("res://presentation/shop/shop_recorder.gd")
const DefaultHud := preload("res://presentation/shop/hud/default_hud.gd")
const ArtGroups := preload("res://presentation/shop/art_groups.gd")
const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const Characters := preload("res://presentation/characters/character_library.gd")
const CAMPAIGN: SpecCampaign = preload("res://content/campaign/campaign.tres")
## 竖屏铺满宽度；横屏最多少看 MIN_VISIBLE_WORLD 这么高的店面
const MIN_VISIBLE_WORLD := 1100.0
## 界面按这个宽度排版（竖屏铺满宽度）；店面比它宽的店，店面另外缩放
const UI_WIDTH := 720.0
const PAN_SLOP := 12.0
const WALK_SPEED := 170.0

var shop: SpecShop
var rules: ShopRules
var view: ShopView
var anchors: ShopAnchors
var store: ShopSave
## 跨店记录（Profile）：默认用 App 的；测试可以塞一份临时的
var profile: RefCounted
## 结店后自己换到下一家店的场景（测试关掉，只听 shop_left）
var change_scene_on_leave := true
signal shop_left(next_shop_id: String)
var save_status := "自动存档已开启"
var art: Node2D
var ui: Control
var guide: Control
var guide_enabled := false
var tuning: PanelContainer
var recorder: RefCounted
var selected_worker := 1
var _speed_factor := 1.0
var _autosave_elapsed := 0.0
var _font: Font
var _drag: Node2D
var _world_size := Vector2(720, 1500)
var _top_margin := 0.0
var _customer_height := 110.0
var _staff_height := 128.0
var _customer_speed := WALK_SPEED
## 员工、客人、杯子挂在哪个节点下排前后；z_by_y = 那个节点里没有 y 排序，按脚底 y 设 z（物件的 z 在美术场景里）
var _sortables: Node2D
var _z_by_y := false
## 店面缩放（世界单位 → 界面单位）
var _ui_factor := 1.0
var _actors := {}
var _customers := {}
var _customer_positions := {}
var _customer_orders := {}
var _customer_entering := {}
var _known_seats := {}
var _cups: Array[Sprite2D] = []
var _badges := {}
var _bars := {}
var _pops: Array[Dictionary] = []
var _staff_cards: Array[Button] = []
var _shelf: Label
var _seats: Label
var _post_labels := {}
var _toast: Label
var _toast_left := 0.0
var _last_sold := 0
var _last_revenue := 0
## 世界里能点的虚线框：机器 id / "connection:<id>" / "seat"
var _station_buttons := {}
var _upgrade_marks := {}
var _staff_mark: Control
var _hint_ring: Control
var _staff_ring: Control
var _hint_text := ""
var _dining: Node2D
var _scroll := 0.0
var _scroll_min := 0.0
var _world_top := 0.0
var _world_factor := 1.0
var _pan_press := Vector2.INF
var _pan_last := Vector2.ZERO
var _panning := false


func _ready() -> void:
	var guides_seen: Array = []
	var app := get_node_or_null("/root/App")
	if profile == null and app != null: profile = app.profile
	if rules == null:
		guide_enabled = true
		if store == null: store = ShopSave.new(_profile_shop())
		rules = store.load_game()
		_speed_factor = store.loaded_speed
		guides_seen = store.loaded_guides
		if not store.last_error.is_empty(): save_status = store.last_error
		# 刚从上一家店结店过来：从空店开始（员工不带过来）
		if profile != null and profile.fresh_shop and profile.shop == store.shop.id:
			rules = ShopRules.new(store.shop)
			profile.fresh_shop = false
			profile.save()
			store.save_game(rules, _speed_factor, guides_seen)
	shop = rules.shop
	view = ShopView.new(rules)
	DisplayServer.window_set_title(shop.display_name)
	_font = load("res://art/ui/graybox_font.ttf")
	art = load(shop.scene_path).instantiate()
	art.name = "ShopArt"
	$Canvas.add_child(art)
	$Canvas.move_child(art, 0)
	anchors = ShopAnchors.new(art.get_node("Anchors"))
	_world_size = anchors.meta(".", "world_size", _world_size)
	_top_margin = float(anchors.meta(".", "top_margin", 0.0))
	_customer_height = float(anchors.meta(".", "customer_height", _customer_height))
	_staff_height = float(anchors.meta(".", "staff_height", _staff_height))
	_customer_speed = float(anchors.meta(".", "customer_speed", _customer_speed))
	_sortables = art.get_node(String(anchors.meta(".", "sortables", "Sortables")))
	_z_by_y = _sortables.get_meta("z_by_y", false)
	$Canvas/WorldLabels.z_index = int(anchors.meta(".", "labels_z", $Canvas/WorldLabels.z_index))
	for node in art.find_children("*", "Node2D", true, false):
		if node.get_meta("art_layer", "") in ["actors", "drinks"]: node.visible = false
	_dining = art.find_children("*", "Node2D", true, false).filter(func(n: Node) -> bool: return n.get_script() == Dining).front() \
		if art.find_children("*", "Node2D", true, false).any(func(n: Node) -> bool: return n.get_script() == Dining) else null
	if _dining != null and rules.dine_group() != null:
		_dining.setup(anchors, rules.dine_group().id, view.item_art, _customer_height)
	ui = $Overlay/UI/HUD
	ui.setup(self)
	_toast = ui.toast
	DefaultHud.install(self, ui)
	_build_tuning()
	guide = Guide.new()
	$Overlay/UI.add_child(guide)
	guide.setup(self, guides_seen)
	guide.enabled = guide_enabled
	ui.start()
	_build_world_labels()
	_drag = DragController.new()
	$Canvas.add_child(_drag)
	_drag.setup(self)
	_reset_visuals()
	_refresh(0.0)
	_fit()
	_show_toast(view.goal().text)
	if carrier_warning(): _show_toast(_t("no_carrier"))


func _profile_shop() -> SpecShop:
	var id: String = profile.shop if profile != null and not String(profile.shop).is_empty() else ""
	for city in CAMPAIGN.cities:
		for entry in city.shops:
			if not entry.shop_path.is_empty() and (id.is_empty() or entry.id == id): return load(entry.shop_path)
	return null


## 界面上的提示句：店铺数据 goals.texts 里有就用，没有用这里的默认句
const DEFAULT_TEXTS := {
	"no_carrier": "当前没有流动员工搬运，饮品可能无法送到下一站或货架。",
	"no_staff": "店内暂无员工，请从员工名册派遣伙伴。",
	"no_mobile": "缺少流动员工，搬运将等待；拖到空地可恢复流动。",
	"restarted": "店铺已重新开始。",
	"no_room": "店里没有空位了，解锁新设备后可以多派伙伴。",
	"hired_deployed": "新伙伴上岗了！拖动伙伴可以换岗位。",
	"hired_roster": "新伙伴已加入名册，可在员工界面派遣。",
	"recalled": "伙伴已回到名册。",
	"deployed": "伙伴已派到店内。",
	"staff_upgraded": "{side}升级：{name}",
	"side_front": "前台",
	"side_kitchen": "后厨",
	"done_unlock": "设备已解锁。",
	"done_box": "原料箱已解锁。",
	"done_seat": "加了两个座位。",
	"done_flyers": "传单发出去了。",
	"done_flyer_upgrade": "传单升级了。",
	"done_upgrade": "升级完成。",
	"connection_bought": "传送带装好了：{note}",
	"chip_shelf": "货架 {count}/{limit}",
	"chip_seats": "堂食 {used}/{total}",
	"chip_post_counter": "前台",
	"chip_post": "坐班",
	"frame_unlock": "{title}\n{cost} 金币",
	"frame_box": "{name}箱\n{cost} 金币",
	"frame_box_tip": "解锁后{machine}才有原料",
	"frame_seat": "加 {step} 个座位\n{cost} 金币",
	"frame_seat_tip": "有空座位的堂食客人先坐下再点单，坐着等更有耐心",
	"frame_connection": "传送带\n{cost} 金币",
	"summary_title": "结店总结 · {shop}",
	"summary_rating": "评分　{stars}",
	"summary_sold": "卖出 {sold} 份（走掉 {lost} 位客人）",
	"summary_top": "卖得最好　{dishes}",
	"summary_levels": "台子　{levels}",
	"summary_staff": "员工 {staff} 位，到{next}要重新招",
	"summary_stay": "继续营业",
	"summary_leave": "去{next}",
	"summary_confirm": "确定离开（金币、台子、员工都不保留）",
}


func _t(key: String, values := {}) -> String:
	return view.text(key, values, DEFAULT_TEXTS.get(key, key))


func restart() -> void:
	if is_instance_valid(_drag): _drag.cancel()
	rules.reset()
	_reset_visuals()
	_show_toast(_t("restarted"))
	_refresh(0.0)
	_fit()
	save_now(false)


func _reset_visuals() -> void:
	ui.show_selection = false
	var roster := all_staff()
	selected_worker = int(roster[0].id) if not roster.is_empty() else -1
	for actor in _actors.values(): actor.free()
	_actors.clear()
	for customer in _customers.values(): customer.free()
	_customers.clear()
	_customer_positions.clear()
	_customer_orders.clear()
	_customer_entering.clear()
	_known_seats.clear()
	_last_sold = rules.sold
	_last_revenue = int(rules.revenue)
	for pop in _pops: pop.label.free()
	_pops.clear()


## 这一帧店是不是停着：看角色的页面、压暗的引导、要人选的卡片
func frozen() -> bool:
	var page_node: Control = ui.page_node(ui.page)
	if page_node != null and page_node.get("freezes_shop") == true: return true
	return guide.freezes() or ui.popups.freezes()


func _process(delta: float) -> void:
	if rules == null: return
	if not frozen():
		var before := rules.clock
		rules.step(minf(delta, 0.25) * _speed_factor)
		if recorder != null: recorder.tick(rules.clock - before)
	_refresh(delta)
	guide.refresh(delta)
	_fit()
	_toast_left = maxf(0, _toast_left - delta)
	_toast.visible = _toast_left > 0 or not _staffing_warning().is_empty()
	_update_pops(delta)
	if store != null:
		_autosave_elapsed += delta
		if _autosave_elapsed >= 10.0:
			_autosave_elapsed = 0.0
			save_now(false)


func _refresh(delta: float) -> void:
	_refresh_events()
	ui.refresh()
	var deployed := {}
	for worker in rules.workers: deployed[int(worker.id)] = true
	for id in _actors.keys():
		if not deployed.has(int(id)):
			_actors[id].free()
			_actors.erase(id)
	for id in anchors.children("Connections"):
		var art_name := String(anchors.meta("Connections/" + id, "art", ""))
		var belt := art.find_child(art_name, true, false) if not art_name.is_empty() else null
		if belt != null and belt.get_meta("art_layer", "") == "belts": belt.visible = rules.belts.has(id)
	for worker in rules.workers:
		if not _actors.has(worker.id):
			var actor := _actor(String(worker.kind), _staff_height)
			_sortables.add_child(actor)
			_actors[worker.id] = actor
		var actor: Node2D = _actors[worker.id]
		actor.selected = ui.show_selection and int(worker.id) == selected_worker
		actor.display(worker, rules.clock)
		if _z_by_y: actor.z_index = int(actor.position.y)
		actor.task.visible = ui.show_selection and int(worker.id) == selected_worker and ui.page == "shop"
	for id in _badges:
		var status := view.machine_status(id)
		var open := rules.station_unlocked(id)
		var working: bool = status.get("working", false)
		var need: String = status.get("need", "")
		_bars[id].visible = open and working
		_bars[id].value = float(status.get("progress", 0.0))
		_badges[id].text = need
		_badges[id].visible = open and not working and not need.is_empty()
		_badges[id].tooltip_text = "%s · 输入 %d · 加工 %d · 输出 %d" % [view.station_name(id), status.get("input", 0), status.get("processing", 0), status.get("output", 0)]
	if _shelf != null:
		_shelf.text = _t("chip_shelf", {"count": rules.shelf_count, "limit": rules.shelf_capacity()})
	if _seats != null and rules.dine_group() != null:
		var seats := view.seats()
		_seats.text = _t("chip_seats", {"used": seats.used, "total": seats.total})
		_seats.visible = rules.is_open()
	_refresh_station_signs()
	for post in _post_labels:
		var owner := -1
		for worker in rules.workers:
			if worker.get("post", "") == post:
				owner = int(worker.id)
				_post_labels[post].text = _t("chip_post_counter") if post == rules.counter_id else _t("chip_post")
		_post_labels[post].visible = owner != -1
	var staffing_warning := _staffing_warning()
	if not staffing_warning.is_empty() and _toast_left <= 0: _toast.text = staffing_warning
	var moving := 0.0 if rules.paused or frozen() else delta
	_update_cups()
	_update_customers(moving)
	if _dining != null:
		_dining.refresh(rules.seat_total(), rules.diners, _font, rules.clock, moving)
	if rules.sold > _last_sold: _pop_income(int(rules.revenue) - _last_revenue)
	_last_sold = rules.sold
	_last_revenue = int(rules.revenue)


func _actor(kind: String, height := 128.0) -> Node2D:
	var actor := Actor.new()
	actor.item_art = view.item_art
	actor.task_text = view.task_text
	actor.work_direction = view.work_direction
	actor.pouring_station = view.pouring_station
	actor.order_icon = _order_icon
	actor.work_progress = view.work_progress
	actor.setup(kind, _font, height)
	actor.progress_bar.theme = ui.theme
	return actor


# ---------- 奇遇卡（§3.13）：规则层等玩家选的卡片排进弹卡队列 ----------

func _refresh_events() -> void:
	var card := view.event_card()
	if card.is_empty() or ui.popups.has_card("event:" + String(card.id)): return
	var buttons: Array = []
	for index in card.choices.size():
		buttons.append({"label": card.choices[index], "primary": index == 0, "action": answer_event.bind(index, String(card.id))})
	ui.popups.push({"id": "event:" + String(card.id), "title": card.title, "art": card.icon if not String(card.icon).is_empty() else String(card.speaker),
		"note": card.text, "buttons": buttons, "speaker": card.speaker})


func answer_event(choice: int, id: String) -> void:
	var error := rules.answer_event(choice)
	if not error.is_empty():
		_show_toast(error)
		return
	ui.popups.remove("event:" + id)
	save_now(false)
	_refresh(0.0)


# ---------- 世界里的字、框、标记 ----------

func _build_world_labels() -> void:
	var parent: Node = $Canvas/WorldLabels
	for id in anchors.children("Stations"):
		if not anchors.has("Stations/%s/Badge" % id) or not rules.stations.has(id): continue
		var point := anchors.point("Stations/%s/Badge" % id)
		var bar := ProgressBar.new()
		bar.position = point
		bar.size = Vector2(110, 14)
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.theme = ui.theme
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(bar)
		_bars[id] = bar
		var label := _chip(parent, point + Vector2(10, -6))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		_badges[id] = label
	if anchors.has("Chips/Shelf"): _shelf = _chip(parent, anchors.point("Chips/Shelf"))
	if anchors.has("Chips/Seats") and rules.dine_group() != null:
		_seats = _chip(parent, anchors.point("Chips/Seats"))
		_seats.mouse_filter = Control.MOUSE_FILTER_STOP
		_seats.gui_input.connect(_on_seats_input)
		_seats.visible = false
	for id in anchors.children("Stations"):
		if not anchors.has("Stations/%s/PostPoint" % id): continue
		var label := _chip(parent, anchors.point("Stations/%s/PostPoint" % id) + Vector2(-26, 14))
		label.visible = false
		_post_labels[id] = label
	# 没解锁的机器：虚线框
	for id in anchors.children("Stations"):
		var rect := anchors.rect("Stations/%s/Frame" % id)
		if not rect.has_area(): continue
		_station_buttons[id] = _frame(rect, ui.open_station.bind(id))
	for id in anchors.children("Connections"):
		var rect := anchors.rect("Connections/%s/Frame" % id)
		if rect.has_area(): _station_buttons["connection:" + id] = _frame(rect, buy_connection.bind(id))
	if rules.dine_group() != null and anchors.has("Tables/" + rules.dine_group().id):
		_station_buttons["seat"] = _frame(Rect2(), station_action.bind("seat", rules.counter_id))
	for id in anchors.station_rects():
		var region: Rect2 = anchors.station_rects()[id]
		var mark := UpgradeBadge.new()
		var spot := Vector2(region.end.x - 14, region.position.y + 14)
		mark.center_on(anchors.point("Stations/%s/Mark" % id, spot))
		parent.add_child(mark)
		_upgrade_marks[id] = mark
	if _seats != null:
		_upgrade_marks[rules.counter_id] = UpgradeBadge.new()
		_seats.add_child(_upgrade_marks[rules.counter_id])
	_hint_ring = HintRing.new()
	parent.add_child(_hint_ring)
	var staff_tab: Button = ui.tab("staff")
	if staff_tab != null:
		_staff_mark = UpgradeBadge.new()
		staff_tab.add_child(_staff_mark)
		_staff_ring = HintRing.new()
		staff_tab.add_child(_staff_ring)


func _frame(rect: Rect2, action: Callable) -> Button:
	var frame := UnlockFrame.new()
	frame.position = rect.position
	frame.size = rect.size
	frame.theme = ui.theme
	frame.add_theme_font_size_override("font_size", 17)
	frame.pressed.connect(action)
	$Canvas/WorldLabels.add_child(frame)
	# 按脚底前后排序的店：虚线框画在地上那一层，站在框前面的员工不被挡住
	if _z_by_y and rect.has_area():
		frame.z_as_relative = false
		frame.z_index = int(rect.end.y)
	return frame


func _on_seats_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: ui.open_station(rules.counter_id)


func _refresh_station_signs() -> void:
	var next_stage := view.next_stage()
	var box := rules.pending_box()
	for id in _station_buttons:
		var frame: Button = _station_buttons[id]
		if id.begins_with("connection:"):
			var connection_id: String = id.trim_prefix("connection:")
			var row: Dictionary = {}
			for candidate in rules.connection_rows():
				if candidate.id == connection_id: row = candidate
			frame.visible = not row.is_empty() and row.available and not row.owned
			if not frame.visible: continue
			frame.can_unlock = String(row.error).is_empty()
			frame.text = _t("frame_connection", {"cost": row.cost})
			frame.tooltip_text = String(anchors.meta("Connections/" + connection_id, "note", row.name)) + "\n" + String(row.error)
			continue
		if id == "seat":
			# 下一张要买的桌子：桌子上方一个虚线框（开张以后）
			var group := rules.dine_group()
			var tables := anchors.points("Tables/" + group.id)
			var table_index: int = rules.seat_total() / maxi(1, int(anchors.meta("Tables/" + group.id, "per_table", 2)))
			frame.visible = rules.is_open() and rules.seat_cost() >= 0 and table_index < tables.size()
			if not frame.visible: continue
			frame.position = tables[table_index] + Vector2(-60, -78)
			frame.size = Vector2(120, 72)
			frame.can_unlock = rules.seat_error().is_empty()
			frame.text = _t("frame_seat", {"step": group.step, "cost": rules.seat_cost()})
			frame.tooltip_text = _t("frame_seat_tip") + "\n" + rules.seat_error()
			continue
		if id == rules.supply_id:
			# 原料柜的框：最新那台机器要用的原料箱
			frame.visible = not box.is_empty()
			if box.is_empty(): continue
			var m := shop.station(rules.supply_id).material(box)
			frame.can_unlock = rules.box_error(box).is_empty()
			frame.text = _t("frame_box", {"name": m.display_name, "cost": m.box_cost})
			frame.tooltip_text = _t("frame_box_tip", {"machine": view.station_name(m.box_station)})
			continue
		var card := view.station(id)
		if card.is_empty(): continue
		frame.visible = not card.unlocked and int(card.stage) == next_stage
		if not frame.visible: continue
		frame.can_unlock = String(card.unlock.error).is_empty()
		frame.tooltip_text = String(card.description) + "\n" + String(card.unlock.error)
		var st := shop.station(id)
		var title: String = card.unlock.title if st.params.get("frame_title", "") == "stage" else view.station_name(id)
		frame.text = _t("frame_unlock", {"title": title, "cost": card.unlock.cost})
	ArtGroups.refresh(art, rules)
	for id in _upgrade_marks:
		var frame: Button = _station_buttons.get(id)
		_upgrade_marks[id].visible = view.can_buy(id) and not (frame != null and frame.visible)
	if _seats != null and _upgrade_marks.has(rules.counter_id):
		# 在数字牌旁边，不挡座位数
		_upgrade_marks[rules.counter_id].center_on(Vector2(_seats.size.x + 16, _seats.size.y / 2.0))
	var staff_page: Control = ui.page_node("staff")
	var staff_tab: Button = ui.tab("staff")
	if _staff_mark != null: _staff_mark.visible = staff_page != null and staff_page.affordable()
	var hint := view.bottleneck()
	var target := String(hint.get("target", ""))
	# 刚堵上的时候弹一次完整原因，目标栏里留短句
	if not hint.is_empty() and _hint_text != String(hint.text): _show_toast(String(hint.text))
	_hint_text = String(hint.get("text", ""))
	var rects := anchors.station_rects()
	_hint_ring.visible = rects.has(target)
	if _hint_ring.visible:
		_hint_ring.position = rects[target].position - Vector2(6, 6)
		_hint_ring.size = rects[target].size + Vector2(12, 12)
	if _staff_ring != null:
		_staff_ring.visible = target.begins_with("staff")
		if _staff_ring.visible:
			_staff_ring.position = Vector2(-4, -4)
			_staff_ring.size = staff_tab.size + Vector2(8, 8)
		_staff_mark.center_on(Vector2(staff_tab.size.x - 14, 12))


func _chip(parent: Node, point: Vector2) -> Label:
	var label := _label(parent, point, 16)
	var box := ReferenceTheme.style("pill", 12)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	label.add_theme_stylebox_override("normal", box)
	label.add_theme_constant_override("outline_size", 0)
	return label


func _label(parent: Node, point: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = point
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("573c2a"))
	label.add_theme_color_override("font_outline_color", Color("fff3dd"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _sale_point() -> Vector2:
	return anchors.point("Counter/Sale", Vector2(_world_size.x / 2.0, _world_size.y / 2.0))


func _pop_income(amount: int) -> void:
	if amount <= 0: return
	var label := _label($Canvas/WorldLabels, _sale_point(), 30)
	label.text = "+%d" % amount
	label.add_theme_color_override("font_color", Color("8b6446"))
	var coin := TextureRect.new()
	coin.texture = preload("res://art/ui/coin_small.png")
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.size = Vector2(26, 26)
	coin.position = Vector2(-30, 6)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_child(coin)
	label.add_theme_constant_override("outline_size", 7)
	_pops.append({"label": label, "age": 0.0})


func _update_pops(delta: float) -> void:
	for pop in _pops.duplicate():
		pop.age += delta
		pop.label.position = _sale_point() - Vector2(0, pop.age * 50.0)
		pop.label.modulate.a = clampf(1.4 - pop.age, 0, 1)
		if pop.age >= 1.4:
			pop.label.free()
			_pops.erase(pop)


# ---------- 杯子、客人 ----------

func _update_cups() -> void:
	var draws := []
	var shelf_points := anchors.points("Shelf/shelf")
	var shelf_items: Array = []
	for dish in rules.shelf_stock:
		for unused in mini(int(rules.shelf_stock[dish]), shelf_points.size() - shelf_items.size()): shelf_items.append(dish)
	for i in shelf_items.size():
		draws.append({"pos": shelf_points[i], "item": shelf_items[i], "host": String(anchors.meta("Shelf/shelf", "host", ""))})
	# 封好口的外带杯在货架另一格等前台来取
	var rack_points := anchors.points("Shelf/rack")
	if rules.stations.has(rules.RACK) and not rack_points.is_empty():
		var sealed: Array = []
		for dish in rules.stations[rules.RACK].output:
			for unused in mini(int(rules.stations[rules.RACK].output[dish]), rack_points.size() - sealed.size()): sealed.append(dish)
		for i in sealed.size():
			draws.append({"pos": rack_points[i], "item": sealed[i], "host": String(anchors.meta("Shelf/rack", "host", ""))})
	for belt in rules.belt_items:
		var route := PackedVector2Array(anchors.points("Connections/%s/Path" % belt.route))
		if route.size() < 2: continue
		var point := _along(route, float(belt.progress))
		for i in int(belt.count):
			var offset := Vector2((i - (int(belt.count) - 1) / 2.0) * 14, -i * 2)
			draws.append({"pos": point + offset, "item": belt.item, "host": String(anchors.meta("Connections/" + belt.route, "art", ""))})
	# 做好等人取的：一只杯子摆在机器旁边（数量看机器上的牌）
	for id in anchors.children("Stations"):
		var path := "Stations/%s/Buffer" % id
		if not anchors.has(path) or not rules.stations.has(id): continue
		for item in rules.stations[id].output:
			if int(rules.stations[id].output[item]) > 0:
				draws.append({"pos": anchors.point(path), "item": item, "host": String(anchors.meta(path, "host", ""))})
				break
	while _cups.size() < draws.size():
		var sprite := Sprite2D.new()
		sprite.centered = false
		_sortables.add_child(sprite)
		_cups.append(sprite)
	for i in _cups.size():
		var sprite := _cups[i]
		sprite.visible = i < draws.size()
		if not sprite.visible: continue
		var row: Dictionary = draws[i]
		var look := view.item_art(String(row.item))
		var texture: Texture2D = look.texture
		sprite.texture = texture
		sprite.modulate = look.get("tint", Color.WHITE)
		sprite.scale = Vector2.ONE * Actor.CUP_HEIGHT / texture.get_height()
		# 放在家具上的杯子排在那件家具的落脚点前面一点：压得住家具，又在离镜头更近的员工后面
		var host: Node2D = _sortables.get_node_or_null(String(row.host)) if not String(row.host).is_empty() else null
		var sort_y: float = row.pos.y if host == null else maxf(row.pos.y, host.position.y + 1.0)
		sprite.position = Vector2(row.pos.x, sort_y)
		sprite.offset = Vector2(-texture.get_width() / 2.0, -texture.get_height() - (sort_y - row.pos.y) / sprite.scale.y)
		if _z_by_y: sprite.z_index = int(sort_y)


func _update_customers(delta: float) -> void:
	if shop.fulfillment.handoff == "single":
		_update_customers_single(delta)
		return
	var active := {}
	var queue := anchors.points("Queue")
	var entrance := anchors.point("Entrance", Vector2(_world_size.x / 2.0, _world_size.y))
	var lanes := anchors.points("Lanes")
	var waypoint := Vector2(anchors.point("Aisle", entrance).x, lanes[0].y if not lanes.is_empty() else entrance.y)
	var pickup := anchors.point("Counter/Pickup", queue[0] if not queue.is_empty() else entrance)
	# 客人从门口进来、走过道、在柜台前排队；有座位的先坐下，递杯时走到柜台一头取
	var standing := 0
	for order: Dictionary in rules.orders:
		var seat := int(order.get("seat", -1))
		var i := standing
		if seat < 0:
			standing += 1
			if i >= queue.size(): continue
		active[order.id] = true
		if not _customers.has(order.id):
			var actor := _actor(Characters.customer_art(int(order.id)), _customer_height)
			_sortables.add_child(actor)
			_customers[order.id] = actor
			_customer_positions[order.id] = entrance
			_customer_entering[order.id] = true
		_customer_orders[order.id] = order
		var goal: Vector2 = queue[i] if seat < 0 else (pickup if order.reserved else _dining.seat_point(seat))
		var point: Vector2 = _customer_positions[order.id]
		if _customer_entering.get(order.id, false):
			point = point.move_toward(waypoint, delta * WALK_SPEED)
			if point.distance_to(waypoint) < 1.0: _customer_entering.erase(order.id)
		else:
			point = point.move_toward(goal, delta * WALK_SPEED)
		_customer_positions[order.id] = point
		_customers[order.id].show_order(String(order.dish), -1.0, rules.order_mood(order), order.get("takeaway", false))
		var pose := {"pos": point, "walking": point.distance_to(goal) > 1, "phase": "idle", "task_label": ""}
		if seat >= 0 and not order.reserved and point.distance_to(goal) <= 1:
			pose.seated = true
			pose.facing = int(anchors.meta("Seats/%s/%d" % [rules.dine_group().id, seat], "facing", 2))
		_customers[order.id].display(pose, rules.clock)
		_customers[order.id].z_index = 1 if pose.get("seated", false) else 0
		if pose.get("seated", false): _customers[order.id].position.y -= 14.0
	# 拿到餐的客人离开队伍：堂食的走去分到的座位，其余的出门
	var seats_now := {}
	for diner in rules.diners: seats_now[int(diner.seat)] = true
	var new_seats: Array = seats_now.keys().filter(func(seat: int) -> bool: return not _known_seats.has(seat))
	new_seats.sort()
	_known_seats = seats_now
	var leaving: Array = _customers.keys().filter(func(id) -> bool: return not active.has(id))
	leaving.sort()
	for id in leaving:
		var order: Dictionary = _customer_orders.get(id, {})
		var art_id: String = Characters.customer_art(int(id))
		if _dining != null:
			var kept := int(order.get("seat", -1))
			if kept >= 0 and kept in new_seats:
				new_seats.erase(kept)
				_dining.queue_arrival(kept, _customer_positions[id], art_id)
			elif not order.get("takeaway", false) and not new_seats.is_empty():
				_dining.queue_arrival(new_seats.pop_front(), _customer_positions[id], art_id)
			else:
				_dining.queue_exit(_customer_positions[id], art_id, String(order.get("dish", "")))
		_customers[id].free()
		_customers.erase(id)
		_customer_positions.erase(id)
		_customer_orders.erase(id)
		_customer_entering.erase(id)


## 一人跟单的店（规格 §3.2）：排队的站在队伍位上，站不下的坐等位；付了钱的先坐等位等餐，没等位就站在一边；
## 拿到餐、等不及走掉的客人走回门口再消失。
func _update_customers_single(delta: float) -> void:
	var queue := anchors.points("Queue")
	var entrance := anchors.point("Entrance", Vector2(_world_size.x / 2.0, _world_size.y))
	var waiting := anchors.points("Waiting")
	var group := _wait_group()
	var seats := anchors.points("Seats/" + group) if not group.is_empty() else []
	var free_seats := mini(rules.wait_seats(), seats.size())
	var standing := rules.current_stage().queue_capacity
	var spots := {}
	var seat := 0
	var aside := 0
	for c: Dictionary in rules.customers:
		if c.state != "paid": continue
		if seat < free_seats:
			spots[c.id] = [seats[seat], true]
			seat += 1
		elif not waiting.is_empty():
			spots[c.id] = [waiting[mini(aside, waiting.size() - 1)], false]
			aside += 1
	for i in rules.queue.size():
		var id: int = rules.queue[i]
		if (i < standing or seat >= free_seats) and not queue.is_empty(): spots[id] = [queue[mini(i, queue.size() - 1)], false]
		elif seat < free_seats:
			spots[id] = [seats[seat], true]
			seat += 1
	var patience: float = shop.fulfillment.leave_after
	for c: Dictionary in rules.customers:
		if not spots.has(c.id): continue
		if not _customers.has(c.id):
			var actor := _actor(Characters.customer_art(int(c.id)), _customer_height)
			_sortables.add_child(actor)
			_customers[c.id] = actor
			_customer_positions[c.id] = entrance
		var goal: Vector2 = spots[c.id][0]
		var point: Vector2 = Vector2(_customer_positions[c.id]).move_toward(goal, delta * _customer_speed)
		_customer_positions[c.id] = point
		_customer_orders[c.id] = c
		var arrived := point.distance_to(goal) <= 1.0
		var actor: Node2D = _customers[c.id]
		if c.state == "queue" and patience > 0.0:
			var left: float = 1.0 - float(c.wait) / patience
			actor.show_order(String(c.kind), left, 0 if left > 0.5 else 1 if left > 0.2 else 2)
		else:
			actor.show_order(String(c.kind), -1.0)
		actor.display({"pos": point, "walking": not arrived, "seated": spots[c.id][1] and arrived, "phase": "idle", "task_label": ""}, rules.clock)
		if _z_by_y: actor.z_index = int(actor.position.y)
	# 不在规则层里的客人：走回门口再消失
	for id in _customers.keys():
		if spots.has(id): continue
		var actor: Node2D = _customers[id]
		actor.show_order("", -1.0)
		var point: Vector2 = Vector2(_customer_positions[id]).move_toward(entrance, delta * _customer_speed)
		_customer_positions[id] = point
		actor.display({"pos": point, "walking": true, "phase": "idle", "task_label": ""}, rules.clock)
		if _z_by_y: actor.z_index = int(actor.position.y)
		if point.distance_to(entrance) <= 4.0:
			actor.free()
			_customers.erase(id)
			_customer_positions.erase(id)
			_customer_orders.erase(id)


func _wait_group() -> String:
	for g in shop.seat_groups:
		if g.purpose == "wait": return g.id
	return ""


## 订单气泡里的图：店铺数据给了物品图标就用它，否则用 art/ui/drink_<id>.png
func _order_icon(item: String) -> Texture2D:
	var dish := shop.dish(item)
	var key: String = dish.item if dish != null and not dish.item.is_empty() else item
	for it in shop.items:
		if it.id == key and it.icon != null: return it.icon
	return Actor.drink_icon(item)


func _along(points: PackedVector2Array, progress: float) -> Vector2:
	var length := RuleNav.length(points)
	var remaining := clampf(progress, 0, 1) * length
	for i in points.size() - 1:
		var segment := points[i].distance_to(points[i + 1])
		if remaining <= segment: return points[i].lerp(points[i + 1], remaining / maxf(segment, 0.001))
		remaining -= segment
	return points[-1]


# ---------- 调参（开发用） ----------

func _build_tuning() -> void:
	recorder = Recorder.new()
	recorder.enabled = guide_enabled
	recorder.setup(rules)
	var shade := ColorRect.new()
	shade.name = "TuningShade"
	shade.color = Color(0.12, 0.09, 0.065, 0.34)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Overlay/UI.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.offset_top = 106
	shade.offset_bottom = -112
	shade.hide()
	tuning = TuningPanel.new()
	$Overlay/UI.add_child(tuning)
	tuning.setup(self, guide_enabled)
	tuning.visibility_changed.connect(func() -> void: shade.visible = tuning.visible)
	var button := Button.new()
	button.name = "Tuning"
	button.text = "调参"
	button.custom_minimum_size = Vector2(68, 34)
	button.theme = ui.theme
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(func() -> void:
		ui.open_page("shop")
		tuning.toggle())
	var menu: Control = ui.page_node("menu")
	if menu != null: menu.footer.add_child(button)


## 开着的调参面板压在后厨上面，点和拖都不落到店里
func tuning_covers(screen: Vector2) -> bool:
	return tuning != null and tuning.visible and tuning.get_global_rect().has_point(screen)


func _bought(what: String, gold_before: float) -> void:
	if recorder != null: recorder.log_buy(what, gold_before)


# ---------- 结店（§3.9）：完店后可以去关卡表里的下一家店，不强制 ----------

## 关卡表里的下一家店（已做好数据的）；没有就是 null
func next_shop() -> SpecShop:
	var id := CAMPAIGN.next_shop(shop.id)
	for city in CAMPAIGN.cities:
		for entry in city.shops:
			if entry.id == id and not entry.shop_path.is_empty(): return load(entry.shop_path)
	return null


func can_leave() -> bool:
	return rules.completed_at >= 0.0 and profile != null and next_shop() != null


## 结店总结卡：第一下“去下一家”只提醒什么都不保留，第二下才走
func open_summary(armed := false) -> void:
	if not can_leave(): return
	var d := view.summary()
	var nxt := next_shop().display_name
	var lines: Array = [_t("summary_rating", {"stars": "★".repeat(int(d.rating)) + "☆".repeat(3 - int(d.rating))}),
		_t("summary_sold", {"sold": d.sold, "lost": d.lost})]
	var top: Array = d.top.map(func(row: Array) -> String: return "%s ×%d" % [view.dish_name(String(row[1])), int(row[0])])
	if not top.is_empty(): lines.append(_t("summary_top", {"dishes": "、".join(top)}))
	var levels: Array = []
	for id in d.levels: levels.append("%s %d 级" % [view.station_name(id), int(d.levels[id])])
	if not levels.is_empty(): lines.append(_t("summary_levels", {"levels": "、".join(levels)}))
	lines.append(_t("summary_staff", {"staff": d.staff, "next": nxt}))
	var seconds := int(d.seconds)
	ui.popups.remove("summary")
	ui.popups.push({"id": "summary", "title": _t("summary_title", {"shop": shop.display_name}), "title_size": 34, "medal": "medal",
		"stats": [["clock", "完店用时", "%d 分 %02d 秒" % [seconds / 60, seconds % 60]], ["coin", "营业额", "%d 金" % int(d.earned)]],
		"note": "\n".join(lines), "buttons": [{"label": _t("summary_stay"), "primary": true},
			{"label": _t("summary_confirm") if armed else _t("summary_leave", {"next": nxt}),
				"action": leave_shop if armed else open_summary.bind(true)}]})


## 离开这家店：记一行结店纪录、清掉店内存档，换到下一家（从空店开始）
func leave_shop() -> void:
	if not can_leave(): return
	var record := view.summary()
	record.erase("levels")
	profile.finish_shop(record)
	if store != null: store.delete()
	store = null
	shop_left.emit(String(profile.shop))
	if not change_scene_on_leave: return
	rules = null
	get_tree().change_scene_to_file(scene_file_path if not scene_file_path.is_empty() else "res://presentation/shop/shop_play.tscn")


# ---------- 命令（界面组件调这些） ----------

## 招人直接上岗（先后厨再前台）；以后拖到别的岗位换活
func hire_worker() -> void:
	var staff_page: Control = ui.page_node("staff")
	if staff_page != null and not staff_page.has_staff_room():
		_show_toast(_t("no_room"))
		return
	var gold_before := rules.gold
	if rules.hire().is_empty():
		_bought("hire", gold_before)
		selected_worker = int(all_staff().back().id)
		var deployed := staff_is_deployed(selected_worker) or rules.deploy_worker(selected_worker).is_empty()
		_show_toast(_t("hired_deployed") if deployed else _t("hired_roster"))
		save_now(false)
	_refresh(0.0)


func buy_staff_upgrade(side: String) -> void:
	var info := view.staff_track(side)
	var gold_before := rules.gold
	var error := rules.upgrade("staff/" + side)
	if error.is_empty(): _bought("staff_%s/%s" % [side, info.name], gold_before)
	_show_toast(error if not error.is_empty() else _t("staff_upgraded", {"side": info.title, "name": info.name}))
	if error.is_empty(): save_now(false)
	_refresh(0.0)


func select_worker(id: int, from_card := false) -> void:
	selected_worker = id
	if not from_card: ui.show_selection = true
	_refresh(0)


func all_staff() -> Array:
	return rules.roster


func staff_is_deployed(id: int) -> bool:
	for worker in rules.workers:
		if int(worker.id) == id: return true
	return false


func toggle_deployment() -> void:
	var returning := staff_is_deployed(selected_worker)
	var error := rules.recall_worker(selected_worker) if returning else rules.deploy_worker(selected_worker)
	var message: String = error if not error.is_empty() else _t("recalled") if returning else _t("deployed")
	if error.is_empty() and returning and carrier_warning(): message = _t("no_carrier")
	_show_toast(message)
	if error.is_empty(): save_now(false)
	_refresh(0)


## 后厨有人、但都坐在机器上：没人在机器之间搬东西
func carrier_warning() -> bool:
	return rules.no_kitchen_carrier()


func station_action(action: String, station: String, material := "") -> void:
	var error := ""
	var gold_before := rules.gold
	match action:
		"unlock": error = rules.unlock(station)
		"upgrade": error = rules.upgrade(station)
		"material": error = rules.upgrade(station + "/" + material)
		"box": error = rules.unlock_box(material)
		"seat": error = rules.buy_seat()
		"flyers": error = rules.send_flyers()
		"flyer_upgrade": error = rules.upgrade("flyer")
	_show_toast(error if not error.is_empty() else _t("done_" + action) if DEFAULT_TEXTS.has("done_" + action) else _t("done_upgrade"))
	if error.is_empty():
		var key := station + ("/" + material if not material.is_empty() else "")
		_bought("%s %s Lv%d" % [action, key, rules.level(key) if rules.track_of(key) != null else 0], gold_before)
		save_now(false)
	_refresh(0)


func buy_connection(id: String) -> void:
	var before := rules.gold
	var error := rules.buy_connection(id)
	if not error.is_empty():
		_show_toast(error)
		return
	_bought("belt " + id, before)
	_show_toast(_t("connection_bought", {"note": String(anchors.meta("Connections/" + id, "note", "")).get_slice("，", 0)}))
	save_now(false)
	_refresh(0.0)


func save_now(notify := true) -> Error:
	if store == null: return OK
	var result := store.save_game(rules, _speed_factor, guide.seen_list() if guide != null else [])
	save_status = "进度已保存" if result == OK else store.last_error
	if notify: _show_toast(save_status)
	return result


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = 4.0
	_toast.visible = true


func _staffing_warning() -> String:
	if rules.workers.is_empty(): return _t("no_staff")
	if shop.staff.zones.is_empty(): return ""
	for worker in rules.workers:
		if String(worker.get("post", "")).is_empty(): return ""
	var kitchen_open := false
	for st in shop.stations:
		if st.block in ["counter", "supply", "pickup"] or st.id == shop.goals.opening_station: continue
		kitchen_open = kitchen_open or rules.station_unlocked(st.id)
	return _t("no_mobile") if kitchen_open else ""


# ---------- 画面大小、滚动 ----------

func _fit() -> void:
	var size := get_viewport_rect().size
	var fitted_size := _world_size + Vector2(0, _top_margin)
	# 店面比界面宽的店（世界单位更小）：店面照样铺满宽度，界面另按 UI_WIDTH 排
	var world_scale := fitted_size.x / UI_WIDTH
	var world_factor := minf(size.x / fitted_size.x, size.y / (MIN_VISIBLE_WORLD * world_scale))
	_world_factor = world_factor
	_ui_factor = world_factor * world_scale
	var world_height := fitted_size.y * world_factor
	_scroll_min = minf(0.0, size.y - world_height)
	_world_top = maxf(0.0, (size.y - world_height) / 2.0)
	$Canvas.position.x = (size.x - fitted_size.x * world_factor) / 2.0
	$Canvas.scale = Vector2.ONE * world_factor
	scroll_world_by(0.0)
	$Overlay/UI.position = Vector2($Canvas.position.x, 0)
	$Overlay/UI.scale = Vector2.ONE * _ui_factor
	$Overlay/UI.size = Vector2(UI_WIDTH, size.y / _ui_factor)
	ui.fit_to_size($Overlay/UI.size)
	if tuning != null: tuning.fit_to_size($Overlay/UI.size)


func scroll_world_by(delta: float) -> void:
	_scroll = clampf(_scroll + delta, _scroll_min, 0.0)
	$Canvas.position.y = _world_top + _top_margin * _world_factor + _scroll


## 滚到这块世界矩形落在顶栏和底栏之间
func reveal_world(rect: Rect2) -> void:
	var canvas: Transform2D = $Canvas.get_global_transform_with_canvas()
	var top: float = (canvas * rect.position).y
	var bottom: float = (canvas * rect.end).y
	var view_height: float = get_viewport_rect().size.y
	var header: float = 110.0 * _ui_factor
	var footer: float = view_height - 120.0 * _ui_factor
	if bottom > footer: scroll_world_by(footer - bottom)
	elif top < header: scroll_world_by(header - top)


func _unhandled_input(event: InputEvent) -> void:
	# 触屏只处理一次：它模拟出来的鼠标按下会先打开面板，再被新出现的遮罩关掉
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if not ui.blocks_world(event.position) and not tuning_covers(event.position):
			scroll_world_by(80.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -80.0)
			get_viewport().set_input_as_handled()
		return
	var pressed: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	pressed = pressed or (event is InputEventScreenTouch and event.pressed)
	var released: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	released = released or (event is InputEventScreenTouch and not event.pressed and not event.canceled)
	if pressed:
		_panning = false
		_pan_press = Vector2.INF
		if ui.blocks_world(event.position) or tuning_covers(event.position) or _drag.worker_id != -1: return
		_pan_press = event.position
		_pan_last = event.position
		return
	if _pan_press == Vector2.INF: return
	var moved: bool = event is InputEventScreenDrag or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT)
	if moved:
		if _drag.worker_id != -1:
			_pan_press = Vector2.INF
			return
		# 压暗的引导指着固定的地方，店面不动
		if not _panning and event.position.distance_to(_pan_press) > PAN_SLOP and not guide.freezes(): _panning = true
		if _panning:
			scroll_world_by(event.position.y - _pan_last.y)
			get_viewport().set_input_as_handled()
		_pan_last = event.position
		return
	if event is InputEventScreenTouch and event.canceled:
		_pan_press = Vector2.INF
		_panning = false
		return
	if not released: return
	var was_pan := _panning
	_pan_press = Vector2.INF
	_panning = false
	if was_pan or _drag.worker_id != -1: return
	# 点一下（没滚动）：打开点到的东西
	var point: Vector2 = $Canvas.get_global_transform_with_canvas().affine_inverse() * event.position
	var rects := anchors.station_rects()
	for id in rects:
		if rects[id].has_point(point):
			ui.open_station(id)
			get_viewport().set_input_as_handled()
			return
	if _opens_counter(point):
		ui.open_station(rules.counter_id)
		get_viewport().set_input_as_handled()


## 柜台面板（座位、传单）从堂食数字牌、它旁边的红 ↑、柜台本身或堂食区打开；柜台上的机器先判断
func _opens_counter(point: Vector2) -> bool:
	if _seats == null or not _seats.visible: return false
	var chip := Rect2(_seats.position, _seats.size).grow_individual(12, 14, 52, 14)
	return chip.has_point(point) or anchors.rect("Stations/%s/Post" % rules.counter_id).has_point(point) or anchors.rect("Counter/Dining").has_point(point)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST] and rules != null:
		save_now(false)


func _exit_tree() -> void:
	if rules != null: save_now(false)


## 瓶颈提示的黄框：一闪一闪，不挡点按
class HintRing extends Control:
	var _clock := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _process(delta: float) -> void:
		if not visible: return
		_clock += delta
		modulate.a = 0.55 + 0.45 * sin(_clock * 5.0)
		queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.border_color = Color("ffc928")
		box.set_border_width_all(5)
		box.set_corner_radius_all(14)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
