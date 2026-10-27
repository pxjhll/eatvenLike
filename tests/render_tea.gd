extends "res://tests/render_toast.gd"
## Real portrait renderer/input QA. Helpers are shared with the existing bakery QA.
## PXJ-49：柜台开局就在，买柠檬茶台、招人拖到柜台；营业额够了点价格牌整条奶茶线一次解锁；
## 加料机；点开机器看机器和各物料槽的升级。截图在 docs/qa/pxj49-*.png。

var _failures := 0


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("TEA INPUT: " + message)


func _run() -> void:
	await process_frame
	var app: Node = root.get_node("App")
	app.profile = Profile.create(app.catalog)
	app._pending_shop_state = {}
	change_scene_to_file("res://presentation/shop.tscn")
	await process_frame
	var shop := current_scene
	var sim: GameSim = shop.sim
	sim.paused = true
	_check(sim.config.id == "tea", "fresh scene opens tea")
	_check(sim.workforce.staff.is_empty(), "the shop opens empty, with nobody in it")
	_check(sim.front_hall.is_active("counter"), "the counter is there from the start")
	_check(not shop.world._stations["cabinet"].visible, "the empty kitchen shows no machines")
	await _click(_center_of(shop, "cabinet"))
	_check(shop.controls._selected != "cabinet", "hidden kitchen ignores actual clicks")
	await _advance(sim, 10.0)
	await _capture("res://docs/qa/pxj49-opening.png")

	# 价格牌：点柠檬茶台，卡片按钮买下
	await _click(_center_of(shop, "lemonade_stand"))
	_check(shop.controls._selected == "lemonade_stand", "the locked stand can actually be tapped")
	await _click(_button_center(shop, 0))
	sim.step()
	_check(sim.front_hall.is_active("lemonade_stand"), "the card button really opens the stand")
	_check(sim.economy.gold == 40, "the stand charged its price plate")
	await _click(Vector2(60, 600))

	# 员工栏：招一个人，拖到柜台
	var hire: Button = shop.controls._hire
	await _click(hire.get_global_rect().get_center())
	sim.step()
	await process_frame
	_check(shop.controls._staff_cards.size() == 1, "the new hire shows up in the staff bar")
	await _drag(shop.controls._staff_cards[0].get_global_rect().get_center(), _center_of(shop, "counter"), false)
	sim.step()
	_check(sim.workforce.staff[0].post == "counter", "dragging the card onto the counter puts them on post")
	await _advance(sim, 40.0)
	_check(int(sim.progress.sold.get("lemonade", 0)) > 0, "lemon tea sells in the live scene")

	# 营业额到门槛：奶茶线以虚影出现在固定机位上，点哪台都是同一张价格牌
	var line: ShopStageDef = sim.config.progression.stages[1]
	while sim.economy.revenue < line.revenue_threshold or sim.economy.gold < line.line_cost + sim.workforce.hire_cost():
		sim.step()
	await _advance(sim, 0.5)
	_check(shop.world._stations["brewer"].visible, "the line appears as ghosts once revenue is there")
	_check(not shop.world._stations["topping"].visible, "the later topping machine stays hidden")
	await _capture("res://docs/qa/pxj49-line-ghost.png")
	await _click(_center_of(shop, "brewer"))
	_check(shop.controls._card_title.text == line.line_name, "tapping any ghost shows the whole line")
	var gold := sim.economy.gold
	await _click(_button_center(shop, 0))
	sim.step()
	_check(sim.progress.kitchen_open(), "the card buys the line and opens the kitchen")
	_check(sim.economy.gold == gold - line.line_cost, "one price for the whole line")
	await _click(Vector2(60, 600))
	await _click(hire.get_global_rect().get_center())
	sim.step()
	await process_frame
	await _drag(shop.controls._staff_cards[0].get_global_rect().get_center(), Vector2(300, 600), false)
	sim.step()
	await _advance(sim, 90.0)
	_check(int(sim.progress.sold.get("plain_milk_tea", 0)) > 0, "plain milk tea sells in the live scene")
	await _capture("res://docs/qa/pxj49-milk-tea.png")

	# 加料机：底部按钮买下，升一级开椰果；点开机器看各配料槽
	var topping: ShopStageDef = sim.config.progression.stages[2]
	while sim.economy.revenue < topping.revenue_threshold or sim.economy.gold < topping.line_cost:
		sim.step()
	await _advance(sim, 0.5)
	await _click(shop.controls._unlock.get_global_rect().get_center())
	sim.step()
	_check(sim.progress.stage_index == 2, "the bottom button buys the topping machine")
	while sim.economy.gold < 400:
		sim.step()
	await _click(_center_of(shop, "topping"))
	_check(shop.controls._selected == "topping", "topping machine can be opened")
	await _click(_button_center(shop, 0))
	sim.step()
	await process_frame
	_check(sim.production.available_items().has("coconut_milk_tea"), "the card's machine upgrade opens coconut")
	var pearl: Button = shop.controls._mat_buttons[0]
	_check(pearl.visible and shop.controls._mat_buttons[3].visible, "the panel lists all four topping slots")
	_check(shop.controls._mat_buttons[3].disabled, "taro is shown but closed until machine Lv4")
	await _click(pearl.get_global_rect().get_center())
	sim.step()
	await process_frame
	_check(_mat_level(sim, "topping", "pearl") == 2, "the pearl row really upgrades the pearl slot")
	await _advance(sim, 0.3)
	await _capture("res://docs/qa/pxj49-topping-card.png")
	await _click(_center_of(shop, "cabinet"))
	await process_frame
	_check(shop.controls._mat_buttons[0].visible and shop.controls._mat_buttons[1].visible and not shop.controls._mat_buttons[2].visible, "the cabinet panel lists its two raw slots")
	await _advance(sim, 0.3)
	await _capture("res://docs/qa/pxj49-cabinet-card.png")
	await _click(Vector2(600, 250))
	await _advance(sim, 120.0)
	_check(int(sim.progress.sold.get("pearl_milk_tea", 0)) > 0, "pearl milk tea sells in the live scene")
	await _capture("res://docs/qa/pxj49-flavors.png")
	var saved := sim.to_dict()
	var restored := GameSim.new()
	restored.setup(sim.config, app.roster_defs())
	restored.load_dict(saved)
	_check(restored.to_dict() == saved, "live scene state restores exactly")
	restored.free()
	root.size = Vector2i(540, 960)
	await create_timer(0.5).timeout
	await _capture("res://docs/qa/pxj49-small.png")
	print("TEA INPUT QA failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _mat_level(sim: GameSim, slot_id: String, material_id: String) -> int:
	for st in sim.production.stations:
		if st.slot_id == slot_id:
			return st.mat_level(material_id)
	return -1
