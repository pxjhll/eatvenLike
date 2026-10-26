extends "res://tests/render_toast.gd"
## Real portrait renderer/input QA. Helpers are shared with the existing bakery QA.
## PXJ-46: empty shop, price plates, hiring, dragging a card onto the counter, then the kitchen gate.

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
	_check(not shop.world._stations["pearl_pot"].visible, "closed kitchen stations hidden")
	await _click(_center_of(shop, "pearl_pot"))
	_check(shop.controls._selected != "pearl_pot", "hidden kitchen ignores actual clicks")
	await _advance(sim, 10.0)
	await _capture("res://docs/qa/pxj46-empty-shop.png")

	# 价格牌：点一下柠檬水台，卡片上是它的价格，再点按钮就摆上
	await _click(_center_of(shop, "lemonade_stand"))
	_check(shop.controls._selected == "lemonade_stand", "the locked stand can actually be tapped")
	_check(not shop.controls._card_buttons[0].disabled, "50 starting gold affords the stand")
	await _click(_button_center(shop, 0))
	sim.step()
	_check(sim.front_hall.is_active("lemonade_stand"), "the card button really opens the stand")
	await _click(_center_of(shop, "counter"))
	await _click(_button_center(shop, 0))
	sim.step()
	_check(sim.front_hall.is_active("counter"), "and the counter after it")
	_check(sim.economy.gold == 20, "both price plates charged their configured price")
	await _click(Vector2(60, 600))

	# 员工栏：招一个人，把卡片拖到柜台上岗
	var hire: Button = shop.controls._hire
	_check(not hire.disabled, "20 gold affords the first hire")
	await _click(hire.get_global_rect().get_center())
	sim.step()
	_check(sim.workforce.staff.size() == 1, "the hire button hires one")
	await process_frame
	_check(shop.controls._staff_cards.size() == 1, "the new hire shows up in the staff bar")
	await _capture("res://docs/qa/pxj46-staff-bar.png")
	var card: Button = shop.controls._staff_cards[0]
	await _drag(card.get_global_rect().get_center(), _center_of(shop, "counter"), false)
	sim.step()
	_check(sim.workforce.staff[0].post == "counter", "dragging the card onto the counter puts them on post")
	await _advance(sim, 40.0)
	_check(int(sim.progress.sold.get("lemonade", 0)) > 0, "the server pours and sells lemonade in the live scene")
	await _capture("res://docs/qa/pxj46-lemonade.png")

	# 营业额到门槛后，前厅按钮买下煮珍珠锅，后厨出现
	while sim.economy.revenue < 300 or sim.economy.gold < 60:
		sim.step()
	await _advance(sim, 1.0)
	_check(not shop.controls._unlock.disabled, "front unlock button becomes purchasable")
	var gold := sim.economy.gold
	await _click(shop.controls._unlock.get_global_rect().get_center())
	sim.step()
	_check(sim.progress.kitchen_open(), "actual front button opens kitchen")
	_check(sim.economy.gold <= gold - 60, "actual purchase pays configured price")
	_check(shop.world._stations["pearl_pot"].visible, "physical kitchen appears after purchase")

	# 再招一个人，从员工栏直接拖到后厨（后厨这一段还是按工作区，布局模式见 PXJ-47）
	while sim.economy.gold < sim.workforce.hire_cost():
		sim.step()
	await _click(hire.get_global_rect().get_center())
	sim.step()
	await process_frame
	await _drag(shop.controls._staff_cards[0].get_global_rect().get_center(), Vector2(300, 600), false)
	sim.step()
	var cook: String = sim.workforce.staff[1].staff_id
	await _advance(sim, 2.0)
	for actor in shop.world._staff.values():
		actor._process(0.1)
	var dragged: Node2D = shop.world._staff.get(cook)
	_check(dragged != null, "the second hire has an actor in the world")
	await _advance(sim, 50.0)
	for staff in sim.workforce.staff:
		if staff.staff_id == cook:
			_check(staff.zone == "kitchen", "the second hire works the kitchen")
	await _capture("res://docs/qa/pxj46-single-pot.png")
	await _click(_center_of(shop, "pearl_pot_b"))
	_check(shop.controls._selected == "pearl_pot_b", "parallel pot can be selected")
	while sim.economy.gold < 100:
		sim.step()
	await _click(_center_of(shop, "pearl_pot_b"))
	await _click(_button_center(shop, 0))
	sim.step()
	_check(sim.production.validate_parallel("pearl_pot_b") != "", "actual card buys parallel pot")
	await _click(Vector2(50, 600))
	await _advance(sim, 240.0)
	_check(int(sim.progress.sold.get("pearl_milk_tea", 0)) > 0, "milk tea sells in live scene")
	await _capture("res://docs/qa/pxj46-parallel-pots.png")
	var saved := sim.to_dict()
	var restored := GameSim.new()
	restored.setup(sim.config, app.roster_defs())
	restored.load_dict(saved)
	_check(restored.last_snapshot.kitchen_open, "saved kitchen restores")
	_check(restored.to_dict() == saved, "live scene state restores exactly")
	restored.free()
	root.size = Vector2i(540, 960)
	await create_timer(0.5).timeout
	await _capture("res://docs/qa/pxj46-small.png")
	print("TEA INPUT QA failures=", _failures)
	quit(1 if _failures > 0 else 0)
