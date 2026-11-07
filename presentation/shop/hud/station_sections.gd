extends RefCounted
## 机器面板的各段（station_page 的默认组件）。每段：setup(page) 搭界面，refresh(card) 按 ShopView 快照刷新。

const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")


## 升级轨：当前 → 升级后两格、整句效果、升级键
class TrackSection extends VBoxContainer:
	var page: Node
	var upgrade_button: Button
	var before: Label
	var after: Label
	var effect: Label

	func setup(page_: Node) -> void:
		page = page_
		var hud: Control = page.hud()
		add_theme_constant_override("separation", 14)
		var comparison: HBoxContainer = hud._row(self, 12)
		for side in ["当前", "升级后"]:
			var cell: VBoxContainer = hud._card(comparison)
			cell.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var caption: Label = hud._text(cell, side, 19, true)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var header := ReferenceTheme.style("gold", 8)
			header.set("depth", 0.0)
			header.set_content_margin_all(3)
			caption.add_theme_stylebox_override("normal", header)
			var value: Label = hud._text(cell, "", 26)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if side == "当前":
				before = value
				page.image(comparison, "arrow_right", 32).size_flags_vertical = Control.SIZE_SHRINK_CENTER
			else:
				after = value
		effect = hud._text(self, "", 19, true)
		effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		upgrade_button = page.buy_button(self, func() -> void: page.view_node().station_action("upgrade", page.station_id))
		upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.skin(upgrade_button, "orange")

	func refresh(card: Dictionary) -> void:
		var row: Dictionary = card.track
		before.text = row.now
		after.text = row.next
		effect.text = row.effect
		if int(row.cost) < 0:
			upgrade_button.text = "满级"
			upgrade_button.disabled = true
		else:
			upgrade_button.text = ("升星" if row.star_next else "升级") + " · %d 金币" % int(row.cost)
			upgrade_button.disabled = not String(row.error).is_empty()


## 堂食座位
class SeatsSection extends PanelContainer:
	var page: Node
	var button: Button
	var title: Label
	var effect: Label

	func setup(page_: Node) -> void:
		page = page_
		var hud: Control = page.hud()
		add_theme_stylebox_override("panel", ReferenceTheme.style("card", 18))
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 10)
		add_child(column)
		var line: HBoxContainer = hud._row(column, 14)
		page.image(line, "seat", 60)
		var copy: VBoxContainer = page.copy(line)
		title = hud._text(copy, "", 23)
		effect = hud._text(copy, "", 18, true)
		button = page.buy_button(line, func() -> void: page.view_node().station_action("seat", page.station_id))

	func refresh(card: Dictionary) -> void:
		var seats: Dictionary = card.seats
		title.text = "堂食座位 %d / %d" % [seats.total, seats.max]
		if int(seats.cost) < 0:
			effect.text = "座位已加满 · 现在 %d 位客人在座" % seats.used
			button.text = "满级"
			button.disabled = true
			return
		effect.text = "加一张座位 · 现在 %d 位客人在座" % seats.used
		button.text = "%d 金币" % int(seats.cost)
		button.disabled = not String(seats.error).is_empty()


## 发传单 + 传单升级
class FlyerSection extends PanelContainer:
	var page: Node
	var button: Button
	var upgrade_button: Button
	var title: Label
	var effect: Label
	var upgrade_title: Label
	var upgrade_effect: Label
	var upgrade_line: HBoxContainer

	func setup(page_: Node) -> void:
		page = page_
		var hud: Control = page.hud()
		add_theme_stylebox_override("panel", ReferenceTheme.style("card", 18))
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 10)
		add_child(column)
		var line: HBoxContainer = hud._row(column, 14)
		page.image(line, "flyer", 60)
		var copy: VBoxContainer = page.copy(line)
		title = hud._text(copy, "", 23)
		effect = hud._text(copy, "", 18, true)
		button = page.buy_button(line, func() -> void: page.view_node().station_action("flyers", page.station_id))
		var up_line: HBoxContainer = hud._row(column, 14)
		upgrade_line = up_line
		page.image(up_line, "tag", 60)
		var up_copy: VBoxContainer = page.copy(up_line)
		upgrade_title = hud._text(up_copy, "", 21)
		upgrade_effect = hud._text(up_copy, "", 18, true)
		upgrade_button = page.buy_button(up_line, func() -> void: page.view_node().station_action("flyer_upgrade", page.station_id))

	func refresh(card: Dictionary) -> void:
		var f: Dictionary = card.flyer
		var wait := float(f.wait)
		title.text = "发传单 Lv%d" % int(f.level)
		var hint := " · 队伍已满，先升产能" if f.queue_full else ""
		var coming := int(f.pending)
		if coming > 0 and wait > 0.0:
			effect.text = "客人正在来，还有 %d 位%s" % [coming, " · 队伍满了，等有空位再来" if f.queue_full else ""]
			button.text = "%d 秒" % ceili(wait)
		elif wait > 0.0:
			effect.text = "%d 秒后可以再发%s" % [ceili(wait), hint]
			button.text = "%d 秒" % ceili(wait)
		else:
			if float(f.seconds) > 0.0:
				effect.text = "不花钱 · %d 秒内招来 %d 位客人，间隔 %d 秒%s" % [int(f.seconds), int(f.customers), int(f.cooldown), hint]
			else:
				effect.text = "不花钱 · 招来 %d 位客人，间隔 %d 秒%s" % [int(f.customers), int(f.cooldown), hint]
			if coming > 0: effect.text += " · 上一批还有 %d 位没到" % coming
			button.text = "发传单"
		button.disabled = not String(f.error).is_empty()
		# 没有升级轨的传单不显示升级那一行
		upgrade_line.visible = f.get("upgradable", true)
		if not upgrade_line.visible: return
		var cost := int(f.upgrade_cost)
		upgrade_title.text = "传单升级"
		if cost < 0:
			upgrade_effect.text = "已升满 · 一次 %d 位客人，间隔 %d 秒" % [int(f.customers), int(f.cooldown)]
			upgrade_button.text = "满级"
			upgrade_button.disabled = true
			return
		upgrade_effect.text = "一次 %d → %d 位客人，间隔 %d → %d 秒" % [int(f.customers), int(f.next_customers), int(f.cooldown), int(f.next_cooldown)]
		upgrade_button.text = "%d 金币" % cost
		upgrade_button.disabled = not String(f.upgrade_error).is_empty()


## 物料（原料箱、口味、水果）：每行一个升级 / 解锁键
class MaterialsSection extends VBoxContainer:
	var page: Node
	var title: Label
	var list: VBoxContainer
	var buttons := {}
	var _rows := {}
	var _signature := ""
	var _box_rows := {}

	func setup(page_: Node) -> void:
		page = page_
		var hud: Control = page.hud()
		add_theme_constant_override("separation", 12)
		title = hud._text(self, "", 20)
		title.add_theme_stylebox_override("normal", ReferenceTheme.style("pill", 12))
		list = VBoxContainer.new()
		list.add_theme_constant_override("separation", 12)
		add_child(list)

	func reset() -> void:
		_signature = ""

	func refresh(card: Dictionary) -> void:
		var hud: Control = page.hud()
		var rows: Array = card.materials
		var signature: String = String(card.id) + str(rows.map(func(row: Dictionary) -> String: return row.id))
		if signature != _signature:
			for child in list.get_children(): child.free()
			buttons.clear()
			_rows.clear()
			for row in rows:
				var box: VBoxContainer = hud._card(list)
				var line: HBoxContainer = hud._row(box, 12)
				page.image(line, String(row.icon), 58)
				var copy := VBoxContainer.new()
				copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				copy.add_theme_constant_override("separation", 4)
				line.add_child(copy)
				_rows[row.id] = {"card": box.get_parent(), "name": hud._text(copy, "", 22), "effect": hud._text(copy, "", 19, true)}
				buttons[row.id] = page.buy_button(line, _pressed.bind(String(row.id)))
			_signature = signature
			hud.relayout()
		var st: SpecStation = page.view_node().rules.shop.station(String(card.id))
		title.text = String(st.params.get("materials_label", "原料")) + " · 升级提高售价"
		_box_rows.clear()
		for row in rows:
			var nodes: Dictionary = _rows[row.id]
			var button: Button = buttons[row.id]
			nodes.card.modulate.a = 1.0
			match String(row.state):
				"box", "box_closed":
					nodes.name.text = row.name + "箱"
					nodes.effect.text = row.effect
					button.disabled = not String(row.error).is_empty()
					if row.state == "box_closed":
						nodes.card.modulate.a = 0.6
						button.text = "未开放"
					else:
						button.text = "解锁 · %d 金币" % int(row.cost)
						_box_rows[row.id] = true
				"closed":
					nodes.name.text = row.name
					nodes.effect.text = row.effect
					nodes.card.modulate.a = 0.6
					button.text = "未开放"
					button.disabled = true
				_:
					nodes.name.text = "%s Lv%d" % [row.name, int(row.level)]
					nodes.effect.text = row.effect
					button.text = "满级" if int(row.cost) < 0 else "升级 · %d 金币" % int(row.cost)
					button.disabled = int(row.cost) < 0 or not String(row.error).is_empty()

	func _pressed(material: String) -> void:
		page.view_node().station_action("box" if _box_rows.has(material) else "material", page.station_id, material)


## 没解锁：这一阶段开哪些机器、卖什么、解锁键
class UnlockSection extends VBoxContainer:
	var page: Node
	var unlock_button: Button
	var icon: TextureRect
	var summary: Label
	var members: HBoxContainer
	var _members := ""

	func setup(page_: Node) -> void:
		page = page_
		var hud: Control = page.hud()
		add_theme_constant_override("separation", 14)
		var box: VBoxContainer = hud._card(self)
		var line: HBoxContainer = hud._row(box, 22)
		icon = page.image(line, "boil", 112)
		summary = hud._text(line, "", 22)
		summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		members = hud._row(self, 10)
		unlock_button = hud._action(self, "解锁", func() -> void: page.view_node().station_action("unlock", page.station_id))
		page.skin(unlock_button, "orange")

	func refresh(card: Dictionary) -> void:
		var hud: Control = page.hud()
		var info: Dictionary = card.unlock
		var line: Array = info.members if int(card.stage) > 0 else []
		icon.texture = page.Icons.texture(String(card.icon))
		if not String(info.note).is_empty(): summary.text = String(info.note)
		elif line.is_empty(): summary.text = String(info.description)
		else: summary.text = "一次开放 %d 台机器，开始卖%s（售价 %d）" % [line.size(), info.dish, int(info.dish_price)]
		if str(line) != _members:
			for child in members.get_children(): child.free()
			for member in line:
				var chip := Label.new()
				chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				chip.add_theme_font_size_override("font_size", 19)
				hud.pill(chip, member, "fffaf0", "583e2d")
				members.add_child(chip)
			_members = str(line)
			hud.relayout()
		members.visible = line.size() > 1
		var error := String(info.error)
		var cost := int(info.cost)
		if error.is_empty(): unlock_button.text = "解锁 · %d 金币" % cost
		elif error.begins_with("金币不足"): unlock_button.text = "金币不足 · %d 金币" % cost
		else: unlock_button.text = error
		unlock_button.disabled = not error.is_empty()
