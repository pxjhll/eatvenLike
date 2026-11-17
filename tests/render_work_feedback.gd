extends SceneTree
## Visual feedback follows explicit protocol facts, not task ownership.
var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()

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
	await process_frame
	for error in errors.take(): _check(false,error)
	OS.remove_logger(errors)
	print("WORK FEEDBACK: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

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
