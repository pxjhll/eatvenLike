extends SceneTree
var view
func _initialize(): call_deferred("_run")
func _run():
	root.size=Vector2i(720,1280)
	view=load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	var sim=load("res://game/tea_playtest/tea_shop_sim.gd").new()
	sim.unlock_station("lemonade")
	sim.gold=20000
	sim.revenue=2000
	for id in ["boil","mix","topping"]: sim.unlock_station(id)
	sim.upgrade_station("mix")
	sim.upgrade_material("supply","tea_leaf")
	view.sim=sim
	root.add_child(view)
	await process_frame
	view.set_process(false)
	view.ui.open_station("topping")
	await process_frame
	await process_frame
	var row: Dictionary=sim.station_info("topping").materials[0]
	print("PRICING_UI label=",view.ui.station_panel._material_rows.pearl.effect.text," actual_now=",sim._dish_price("pearl_milk_tea"))
	await _capture("price-mismatch")
	sim.upgrade_material("topping","pearl")
	view._refresh(0.0)
	print("PRICING_UI_AFTER actual_price=",sim._dish_price("pearl_milk_tea"))
	# Isolate a completed sale, using valid existing physical stock and dispatch.
	sim.shelf_stock.pearl_milk_tea=1
	sim.shelf_count=1
	sim._generated=1
	sim.orders=[{"id":1000,"wait":0.0,"reserved":false,"dish":"pearl_milk_tea"}]
	sim._next_order=1001
	var before: int=sim.gold
	for tick in 2000:
		sim.advance(0.1)
		if sim.sold_by_dish.pearl_milk_tea>0: break
	print("ACTUAL_SALE gold_delta=",sim.gold-before," sold_pearl=",sim.sold_by_dish.pearl_milk_tea," audit=",sim.audit().valid)
	# Show all six queued customers at their settled display positions.
	var queue_sim=load("res://game/tea_playtest/tea_shop_sim.gd").new()
	queue_sim.unlock_station("lemonade")
	queue_sim.recall_worker(1)
	queue_sim.advance(20.0)
	view.sim=queue_sim
	view._reset_visuals()
	view.ui.open_page("shop")
	view._refresh(0.0)
	view._update_customers(20.0)
	print("QUEUE_VISUAL orders=",queue_sim.orders.size()," positions=",view._customer_positions)
	await _capture("queue-six-customers")
	view.free()
	quit()
func _capture(name):
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/qa/2026-11-01-playthrough/"+name+".png")
