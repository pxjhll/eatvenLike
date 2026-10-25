extends "res://tests/render_toast.gd"
## Real portrait renderer/input QA. Helpers are shared with the existing bakery QA.

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
	_check(shop.controls._unlock.visible and shop.controls._unlock.disabled, "unlock is visible from front hall before revenue gate")
	_check(not shop.world._stations["pearl_pot"].visible, "closed kitchen stations hidden")
	await _click(_center_of(shop, "pearl_pot"))
	_check(shop.controls._selected != "pearl_pot", "hidden kitchen ignores actual clicks")
	await _advance(sim, 30.0)
	await _capture("res://docs/qa/pxj42-lemonade.png")
	await _advance(sim, 70.0)
	_check(not shop.controls._unlock.disabled, "front unlock button becomes purchasable")
	var gold := sim.economy.gold
	await _click(shop.controls._unlock.get_global_rect().get_center())
	sim.step()
	_check(sim.progress.kitchen_open(), "actual front button opens kitchen")
	_check(sim.economy.gold <= gold - 60, "actual purchase pays configured price")
	_check(shop.world._stations["pearl_pot"].visible, "physical kitchen appears after purchase")
	await _advance(sim, 2.0)
	var bear: Node2D = shop.world._staff["bear"]
	await _drag(bear.position + Vector2(0, -40), Vector2(300, 600), false)
	await _advance(sim, 50.0)
	for staff in sim.workforce.staff:
		if staff.staff_id == "bear":
			_check(staff.zone == "kitchen", "actual drag sends cook to kitchen")
	await _capture("res://docs/qa/pxj42-single-pot.png")
	await _click(_center_of(shop, "pearl_pot_b"))
	_check(shop.controls._selected == "pearl_pot_b", "parallel pot can be selected")
	await _click(_button_center(shop, 0))
	sim.step()
	_check(sim.production.validate_parallel("pearl_pot_b") != "", "actual card buys parallel pot")
	await _click(Vector2(50, 600))
	await _advance(sim, 180.0)
	_check(sim.progress.sold.get("pearl_milk_tea", 0) > 0, "milk tea sells in live scene")
	await _capture("res://docs/qa/pxj42-parallel-pots.png")
	var saved := sim.to_dict()
	var restored := GameSim.new()
	restored.setup(sim.config, app.roster_defs())
	restored.load_dict(saved)
	_check(restored.last_snapshot.kitchen_open, "saved kitchen restores")
	_check(restored.to_dict() == saved, "live scene state restores exactly")
	restored.free()
	root.size = Vector2i(540, 960)
	await create_timer(0.5).timeout
	await _capture("res://docs/qa/pxj42-small.png")
	print("TEA INPUT QA failures=", _failures)
	quit(1 if _failures > 0 else 0)
