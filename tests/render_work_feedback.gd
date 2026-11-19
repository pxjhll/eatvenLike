extends SceneTree
## Visual feedback follows explicit protocol facts, not task ownership.
const TestSession := preload("res://tests/shop_test_session.gd")

var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()
var order_icon_reads := 0

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ",label)

func _run() -> void:
	var actor: Node2D = load("res://presentation/shop/shop_actor.gd").new()
	actor.work_progress = func(row: Dictionary) -> float: return row.display_progress
	actor.work_direction = func(_station: String) -> int: return 3
	actor.setup("rabbit",load("res://art/ui/graybox_font.ttf"))
	root.add_child(actor)
	var row := {"pos":Vector2(200,300),"walking":false,"phase":"pickup","presentation_version":1,"work_station":"supply","display_working":true,"display_progress":-1.0,"carry_item":"","carry_count":0}
	actor.display(row,1.0)
	_check(actor.frame_actor.action=="work","pickup uses actual work animation")
	_check(actor.frame_actor.direction==3,"pickup faces the declared work station")
	_check(not actor.progress_bar.visible,"brief logistics do not flash a progress bar")
	actor.display(row,1.1)
	var phase: float = actor.frame_actor.get_phase()
	row.phase = "dropoff"
	actor.display(row,1.2)
	_check(actor.frame_actor.action=="work" and actor.frame_actor.get_phase()>phase,"consecutive pickup/dropoff preserve the work animation cycle")
	row.display_progress = 0.35
	actor.display(row,1.3)
	_check(actor.progress_bar.visible and is_equal_approx(actor.progress_bar.value,0.35),"real long work progress stays visible")
	row.display_working = false
	row.display_progress = -1.0
	actor.display(row,1.4)
	_check(actor.frame_actor.action=="idle","blocked handoff does not pretend to perform work")
	_check(is_zero_approx(actor.body.rotation),"blocked handoff has no work wobble")
	actor.set_render_position(row.pos+Vector2(8,5))
	var visual: Node2D = actor.frame_actor.get_parent()
	var carried_layer: Node2D = actor.carried.get_parent()
	_check(carried_layer.get_parent()==visual and actor.task.get_parent()==visual and actor.progress_bar.get_parent()==visual,"held items and overhead feedback follow the actor visual layer")
	actor.free()
	_check_first_shop_handoff()
	_check_tea_pot_feedback()
	_check_order_updates()
	await process_frame
	for error in errors.take(): _check(false,error)
	OS.remove_logger(errors)
	print("WORK FEEDBACK: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _check_order_updates() -> void:
	var actor: Node2D = load("res://presentation/shop/shop_actor.gd").new()
	actor.setup("rabbit",load("res://art/ui/graybox_font.ttf"))
	actor.order_icon = func(item: String) -> Texture2D:
		order_icon_reads += 1
		return actor.drink_icon(item)
	root.add_child(actor)
	actor.show_order("tea",0.75,1,true,true)
	var icon: Texture2D = actor._order_cup.texture
	actor.show_order("tea",0.749,1,true,true)
	_check(order_icon_reads==1 and actor._order_cup.texture==icon,"patience changes reuse the original order icon")
	_check(is_equal_approx(actor._patience,0.75),"less than a screen pixel of patience keeps the rendered fill")
	actor.show_order("tea",0.5,2,true,true)
	_check(is_equal_approx(actor._patience,0.5) and actor._mood==2,"a visible change updates the fill and emotion immediately")
	actor.show_order("tea",0.001,2,true,true)
	actor.show_order("tea",0.0,2,true,true)
	_check(is_zero_approx(actor._patience),"the patience bar empties fully")
	actor.show_order("",-1.0)
	_check(not actor._order_cup.visible,"clearing the order hides its icon immediately")
	actor.show_order("lemonade",1.0)
	_check(actor._order_cup.visible and order_icon_reads==2,"a new dish resolves its own icon immediately")
	actor.free()

func _check_first_shop_handoff() -> void:
	var shop: SpecShop = load("res://content/shops/pancake/shop.tres")
	var rules := ShopRules.new(shop,42)
	rules.gold = maxf(rules.gold,float(shop.stages[0].cost))
	_check(rules.unlock("soy_milk").is_empty(),"open the real first shop")
	var view := ShopView.new(rules)
	var actor: Node2D = load("res://presentation/shop/shop_actor.gd").new()
	actor.setup("rabbit",load("res://art/ui/graybox_font.ttf"))
	root.add_child(actor)
	var faced_before_sale := false
	for tick in 220:
		rules.step(0.1)
		var frame := view.render_snapshot()
		var worker: Dictionary = frame.workers[0]
		var previous_direction: int = actor.frame_actor.direction
		actor.display(worker,frame.clock)
		if frame.sold>0: break
		var task: Dictionary = rules.runtime.runner.tasks.get(worker.id,{})
		if task.get("to","")!="guest:1": continue
		if worker.walking and actor.carried.visible:
			_check(not worker.has("facing"),"approach still uses the walking direction")
		if worker.phase!="dropoff" or not worker.display_working: continue
		var guest: Dictionary = frame.movement.customers["guest:1"]
		_check(is_equal_approx(guest.pos.x,worker.pos.x) and guest.pos.y>worker.pos.y,"the actual guest is downscreen from the employee")
		if not faced_before_sale:
			_check(previous_direction!=0,"the employee approached with a different facing")
		_check(actor.frame_actor.direction==0,"employee turns downscreen when the handoff begins")
		_check(actor.carried.visible and guest.carry_count==0,"employee turns while still holding the order")
		faced_before_sale = true
	_check(faced_before_sale,"exercise the turn before the handoff")
	_check(rules.sold==1 and not actor.carried.visible,"the first handoff still settles and clears the employee's hands")
	actor.free()


func _check_tea_pot_feedback() -> void:
	var shop: SpecShop = load("res://content/shops/tea/shop.tres")
	var rules := ShopRules.new(shop, 42)
	rules.gold = 1000.0
	_check(rules.unlock("lemonade").is_empty(), "open the real tea shop")
	_check(rules.unlock("boil").is_empty(), "unlock the real tea pot")
	_check(rules.unlock_box("tea_leaf").is_empty() and rules.kitchen_staff() == 1, "stock tea leaves and staff the kitchen")
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(shop, "tea-pot-feedback-%d" % OS.get_process_id(), rules)
	root.add_child(scene)
	scene.set_process(false)
	var pot_bar: ProgressBar = scene._bars.boil
	var checkpoints: Array = shop.runtime_template.machines.boil.profile.stir_points
	var loaded := false
	var unloaded := false
	var has_cooked := false
	var stir_count := 0
	var first_stir_progress := -1.0
	var stir_advanced := false
	for tick in 800:
		rules.step(0.1)
		var status: Dictionary = scene.view.machine_status("boil")
		if (status.phase == "load" and not loaded) or status.phase == "unload":
			scene._refresh(0.0)
			var employee: Node2D = scene._actors[status.operator]
			unloaded = status.phase == "unload"
			_check(employee.progress_bar.visible and pot_bar.visible, "loading and unloading show separate employee and pot meters")
			_check(is_equal_approx(pot_bar.value, 1.0 if unloaded else 0.0), "the pot shows empty before cooking and full after cooking")
			if unloaded: break
			loaded = true
		elif status.phase == "await_stir":
			scene._refresh(0.0)
			var badge: Label = scene._badges.boil
			_check(pot_bar.visible and badge.visible and not pot_bar.get_rect().intersects(badge.get_rect()),
				"the paused pot meter and waiting label both remain readable")
		elif status.phase == "stir" and not stir_advanced:
			scene._refresh(0.0)
			var employee: Node2D = scene._actors[status.operator]
			var checkpoint: float = checkpoints[stir_count]
			_check(employee.progress_bar.visible, "stirring displays the employee's own progress bar")
			_check(pot_bar.visible and is_equal_approx(float(status.progress), checkpoint) and absf(pot_bar.value - checkpoint) <= 0.01,
				"the pot stays visible at its brewing checkpoint as the employee stirs")
			var employee_progress: float = employee.progress_bar.value
			if first_stir_progress < 0.0: first_stir_progress = employee_progress
			else: stir_advanced = employee_progress > first_stir_progress
		elif status.phase == "processing" and (first_stir_progress >= 0.0 or (not has_cooked and status.progress > 0.1)):
			scene._refresh(0.0)
			_check(pot_bar.visible and absf(pot_bar.value - status.progress) <= 0.01, "automatic brewing displays the machine's cooking progress")
			has_cooked = true
			if first_stir_progress >= 0.0:
				_check(stir_advanced and is_equal_approx(float(status.progress), float(checkpoints[stir_count])),
					"employee progress advances independently and brewing resumes at the same checkpoint")
				stir_count += 1
				first_stir_progress = -1.0
				stir_advanced = false
	_check(loaded and has_cooked and unloaded and stir_count == checkpoints.size(), "exercise the complete brewing cycle")
	scene.free()
