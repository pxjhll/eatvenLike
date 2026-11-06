extends SceneTree
var view: Node2D
var hud: Control
var failures := 0
var errors := preload("res://tests/error_counter.gd").new()
var output := "res://output/native-ui/"
func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(720,1280)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	view.sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	hud = view.ui
	view.sim.gold = 100000
	view.sim.revenue = 100000
	for id in ["lemonade","boil","seal","mix","press","topping"]: view.sim.unlock_station(id)
	view.sim.unlock_box("tea_leaf")
	view.sim.unlock_box("milk")
	view.hire_worker()
	view.hire_worker()
	view.selected_worker = 1
	view.sim.assign_post(3,"boil")
	view.sim.gold = 186
	view.sim.elapsed = 1355
	view.sim.sold = 42
	view.sim.sold_by_dish["lemonade"] = 18
	view.sim.sold_by_dish["black_tea"] = 12
	view.sim.revenue = 1260
	view.sim._full_seconds = view.sim.HINT_AFTER + 1
	view.sim._boil_busy = 1.0
	view.sim.orders.append({"id":999,"dish":"black_tea","reserved":false,"wait":0.0,"takeaway":true,"seat":-1})
	view._refresh(0)
	hud.toast.hide()
	_check(not hud.theme.get_stylebox("normal","Button") is StyleBoxTexture,"buttons use native drawing")
	await _capture("01_home")
	hud.open_page("goals")
	await _capture("02_goals")
	hud.open_page("staff")
	await _settle()
	_check(hud._card_content.columns == 3,"three staff cards fit reference row")
	_check(view._staff_cards.size() == view.all_staff().size(),"all staff remain selectable")
	_check("金币" in hud.train_button.text and String(view.sim.staff_upgrade_info("front").name) in hud.train_button.text,"front price and effect visible without hover")
	_check("金币" in hud.kitchen_upgrade_button.text and String(view.sim.staff_upgrade_info("kitchen").name) in hud.kitchen_upgrade_button.text,"kitchen price and effect visible without hover")
	_check(hud.hire_button.icon == null,"centered price caption has no overlapping coin icon")
	_check(view._staff_cards[0].get_node("SelectedBadge").size.is_equal_approx(Vector2(44,44)),"selection badge keeps its compact bounds")
	await _capture("03_staff")
	hud.open_page("menu")
	await _capture("04_menu")
	hud.open_page("restart")
	_check(hud.confirm_restart_button.is_visible_in_tree() and hud.cancel_restart_button.is_visible_in_tree(),"both restart actions retained")
	await _capture("05_restart")
	hud.open_character_preview("rabbit")
	await _capture("06_characters")
	var previous_price: float = view.sim.tuned("price")
	view.sim.tune.price = 1.1
	hud.open_station("lemonade")
	var price_info: Dictionary = view.sim.station_info("lemonade")
	_check(hud.station_panel._upgrade_before.text == "%s 金币 / 杯" % view.sim.price_text(price_info.price.now),"comparison preserves current fractional prices")
	_check(hud.station_panel._upgrade_after.text == "%s 金币 / 杯" % view.sim.price_text(price_info.price.next),"comparison preserves next fractional prices")
	view.sim.tune.price = previous_price
	hud.open_station("boil")
	await _capture("07_upgrade")
	var unlocked_sim = view.sim
	view.sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	view.sim.gold = 186
	view.sim.unlock_station("lemonade")
	view._refresh(0)
	hud.open_station("boil")
	await _capture("08_unlock")
	view.sim = unlocked_sim
	view._refresh(0)
	hud.open_station("supply")
	await _capture("09_materials")
	hud.open_station("counter")
	await _capture("10_counter")
	hud.open_page("shop")
	view.guide.enabled = true
	view.sim.gold = 50
	hud.refresh()
	view.guide.active = "welcome"
	view.guide._show_card()
	view.guide.show()
	view.guide._place_bubble()
	await _capture("11_welcome")
	view.sim.gold = 186
	hud.refresh()
	view.guide.active = "shop_done"
	view.guide._show_card()
	view.guide._place_bubble()
	await _capture("12_complete")
	view.guide.enabled = false
	view.guide.hide()
	view.tuning.show()
	view.tuning.fit_to_size(hud.size)
	await _capture("13_tuning")
	var old_price:float = view.sim.tuned("price")
	view.tuning.set_value("price",1.2)
	_check(is_equal_approx(view.sim.tuned("price"),1.2),"styled slider changes actual sim")
	view.tuning.set_value("price",old_price)
	view.tuning.hide()
	for viewport in [Vector2i(360,640),Vector2i(1280,720)]:
		root.size = viewport
		view._fit()
		for page in ["staff","menu","goals","restart","characters"]:
			hud.open_page(page)
			await _settle()
			var bounds:Rect2 = hud.get_node("Sheet").get_global_rect()
			_check(bounds.position.y >= -1 and bounds.end.y <= view.get_viewport_rect().size.y+1,"sheet on screen %s/%s"%[viewport,page])
	for e in errors.take(): _check(false,"runtime: "+e)
	OS.remove_logger(errors)
	view.free()
	print("NATIVE UI: %d failures"%failures)
	quit(1 if failures else 0)
func _settle() -> void:
	for unused in 4:
		await process_frame
		hud._fit_sheet()
		if view.guide._card.visible: view.guide._place_bubble()
func _capture(caption:String) -> void:
	await _settle()
	# Capture the settled page after transient toasts and income pops expire.
	hud.toast.hide()
	view._update_pops(2.0)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output+caption+".png")==OK,"capture "+caption)
func _check(ok:bool,message:String) -> void:
	if not ok:
		failures += 1
		print("NATIVE UI FAILURE: "+message)
