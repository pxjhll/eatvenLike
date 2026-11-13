extends SceneTree
## Real shop scenes consume the public presentation protocol. Simulation stays
## explicitly owned by this test until the formal controller migrates in U06.
const TestSession := preload("res://tests/shop_test_session.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
var errors := preload("res://tests/error_counter.gd").new()
var failures := 0
var checks := 0
var paths: Array = []

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: "+label)

func _run() -> void:
	root.size = Vector2i(720,1280)
	root.get_node("ShopAudio")._can_play = false
	for id in ["tea","pancake","stirfry"]: await _shop(id)
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for error in errors.take(): failures += 1; print("RUNTIME: "+error)
	OS.remove_logger(errors)
	print("TEMPLATE SCENE FRAME: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _shop(id: String) -> void:
	var shop: SpecShop = load("res://content/shops/"+id+"/shop.tres").copy_for_editing()
	var owner := ShopRules.new(shop,42)
	owner.gold = 1000000.0
	if id=="tea":
		for machine in ["lemonade","boil","seal","mix","press","topping"]: _check(owner.unlock(machine).is_empty(),"prepare tea purchase")
		for box in ["tea_leaf","milk"]: _check(owner.unlock_box(box).is_empty(),"prepare tea box")
		_check(owner.hire().is_empty(),"hire tea kitchen employee")
		for worker in owner.roster:
			if not worker.deployed: _check(owner.deploy_worker(worker.id).is_empty(),"deploy actual employee")
	else:
		for stage in shop.stages.size(): _check(owner.unlock(shop.sold_at(stage)).is_empty(),"prepare actual stage "+id)
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(shop,"user://scene-frame-%s-%d"%[id,Time.get_ticks_usec()],owner)
	for path in [scene.session.profile.path,scene.session.store.path,scene.session.tuning_path,scene.session.recording_path]: paths.append(path)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	_check(not scene._startup_blocked,id+": actual scene starts")
	if scene._startup_blocked: scene.free(); return
	var template: Resource = load("res://content/shops/"+id+"/shared_production.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var front_id: String = {"tea":"lemonade","pancake":"soy","stirfry":"plum_juice"}[id]
	if template.service.selection.get("at")=="admission":
		for stage in template.service.selection.stages: stage.weights = {front_id:1.0}
	var dish: String = template.service.selection.order[0]
	var recipe: Dictionary = template.recipes[template.service.menu[dish]]
	var item: String = recipe.output.item
	var point: Vector2 = owner.nav.layout.points[owner.counter_id]
	template.places["view_wait"] = {"port":point,"initial":{item:2}}
	template.places["view_drop"] = {"port":point+Vector2(20,0)}
	for scope in ["roles","posts"]:
		for permissions in template.dispatch.get(scope,{}).values():
			permissions["transfer_from"] = permissions.get("transfer_from",[])+["view_wait"]
			permissions["transfer_to"] = permissions.get("transfer_to",[])+["view_drop"]
	var runtime := Runtime.new(owner,template)
	_check(runtime.last_error.is_empty(),id+": real runtime compiles: "+runtime.last_error)
	if not runtime.last_error.is_empty(): scene.free(); return
	if not scene.view.has_method("bind_runtime"):
		_check(false,"formal view cannot bind public runtime"); scene.free(); return
	var binding_error: String = scene.bind_runtime(runtime)
	_check(binding_error.is_empty(),id+": explicit view binding: "+binding_error)
	if not binding_error.is_empty(): scene.free(); return
	var before: Dictionary = runtime.snapshot()
	scene._refresh(0.0)
	_check(runtime.snapshot()==before,id+": refresh has no simulation side effects")
	_check(scene._cups.filter(func(sprite: Sprite2D) -> bool: return sprite.visible).is_empty(),id+": waiting stock does not scatter scene icons")
	_check(scene.bind_runtime(runtime,[{"capability":"stock_showcase","place":"view_wait","points":[point],"host":""}]).is_empty(),id+": explicit showcase")
	scene._refresh(0.0)
	var shown: Array = scene._cups.filter(func(sprite: Sprite2D) -> bool: return sprite.visible)
	_check(shown.size()==1,id+": one authored display port, not one sprite per inventory lot")
	if shown.size()==1: _check(shown[0].texture==scene.view.item_art(item).texture,id+": same shop food art")
	_check(scene.bind_runtime(runtime).is_empty(),id+": turn off showcase")
	var worker: Dictionary = owner.workers[0]
	# Only the fixture's two new containers are added to native permissions;
	# actual ownership, stats, authorization and public operations stay active.
	_check(runtime.runner.transfer(worker.id,"view_wait","view_drop",item,2,0.5,-1,-1).is_empty(),id+": real pickup fixture")
	for tick in 400:
		_check(runtime.runner.step(0.1).is_empty(),id+": real movement/pickup")
		if worker.carry_count>0: break
	scene._refresh(0.0)
	var actor: Node2D = scene._actors[worker.id]
	_check(actor.carried.visible,id+": real pickup displays food")
	var pose: Dictionary = scene.view.render_snapshot().workers[0]
	pose.steps = [{"into_machine":true,"put_down":true}]
	pose.step = 0
	pose.phase = "work"
	actor.display(pose,runtime.snapshot().clock)
	_check(actor.carried.visible,id+": stale legacy step cannot hide real public hand stock")
	for tick in 400:
		_check(runtime.runner.step(0.1).is_empty(),id+": actual drop")
		if runtime.runner.idle(worker.id): break
	scene._refresh(0.0)
	_check(not actor.carried.visible,id+": actual drop clears hand")
	_check(runtime.runner.inventory.quantity("view_drop",item)==2,id+": UI and actual drop agree")
	_check(scene._cups.filter(func(sprite: Sprite2D) -> bool: return sprite.visible).is_empty(),id+": completed goods stay inventory until explicitly displayed")
	var other_dishes: Array = shop.dishes.filter(func(entry: SpecDish) -> bool: return entry.item!=item)
	var other_item: String = other_dishes[0].item
	_check(runtime.runner.inventory.seed("view_wait",item,1).error.is_empty(),id+": seed mixed bundle first item")
	_check(runtime.runner.inventory.seed("view_wait",other_item,1).error.is_empty(),id+": seed mixed bundle second item")
	_check(runtime.runner.transfer_bundle(worker.id,[{"from":"view_wait","to":"view_drop","item":item,"count":1},{"from":"view_wait","to":"view_drop","item":other_item,"count":1}],0.5).is_empty(),id+": real mixed-item bundle")
	for tick in 400:
		_check(runtime.runner.step(0.1).is_empty(),id+": reach actual mixed pickup")
		if worker.carry_count==2: break
	scene._refresh(0.0)
	var hand_sprites: Array = actor.get_children().filter(func(node: Node) -> bool: return node is Sprite2D and node!=actor.body and node!=actor._order_cup and node.visible)
	_check(hand_sprites.size()==2,id+": both physically held item kinds have their own art")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_check(not image.is_empty(),id+": actual viewport capture")
		if not image.is_empty(): _check(image.save_png("res://_work/unified_shop_template_20261112/scene-frame-captures/"+id+".png")==OK,id+": save actual viewport")
	_check(runtime.runner.cancel(worker.id).is_empty(),id+": mixed bundle recall")
	scene._refresh(0.0)
	_check(actor.get_children().filter(func(node: Node) -> bool: return node is Sprite2D and node!=actor.body and node!=actor._order_cup and node.visible).is_empty(),id+": recall hides every hand sprite")
	for factor in [1.0,2.0,4.0]:
		var clock_before: float = runtime.snapshot().clock
		_check(runtime.step(0.1*factor).is_empty(),id+": explicit simulation speed")
		scene._refresh(20.0)
		_check(is_equal_approx(runtime.snapshot().clock-clock_before,0.1*factor),id+": GUI cannot apply speed a second time")
	var arrival: Dictionary = runtime.arrive([] if template.service.selection.get("at")=="admission" else [{"dish":front_id,"qty":1}])
	_check(arrival.error.is_empty(),id+": shared service visitor")
	var saw_customer := false
	var saw_order := false
	for tick in 1200:
		_check(runtime.step(0.25).is_empty(),id+": actual public service in real scene")
		if tick==5:
			var frozen: Dictionary = runtime.snapshot()
			owner.paused = true
			_check(runtime.step(5.0,true).is_empty(),id+": paused shared customer")
			scene._refresh(25.0)
			_check(runtime.snapshot()==frozen,id+": paused redraw cannot move actors or commit food")
			owner.paused = false
		scene._refresh(0.0)
		var frame: Dictionary = scene.view.render_snapshot()
		_check(scene._customers.size()==frame.movement.customers.size(),id+": exactly one visual per public customer")
		for key in frame.movement.customers:
			saw_customer = true
			var row: Dictionary = frame.movement.customers[key]
			_check(scene._customer_positions[key]==row.pos,id+": display uses actual customer movement")
			if scene._customers[key]._order_cup.visible:
				saw_order = true
				_check(scene._customers[key]._order_cup.texture==scene.view.item_icon(front_id),id+": actual shop order artwork")
		if runtime.service.orders.guest(arrival.id).state=="gone": break
	_check(saw_customer and saw_order,id+": actual visitor and order displayed")
	_check(runtime.service.orders.guest(arrival.id).state=="gone",id+": public service completes through real display")
	_check(owner.sold>=1,id+": public payment happened")
	scene.free()
