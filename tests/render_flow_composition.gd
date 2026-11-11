extends SceneTree
## Data fixture, real character factory, no production art or save files changed.
const Fixture := preload("res://tests/fixtures/flow_shop.gd")
var checks := 0
var failed := 0
var errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		print("FAIL ",label)

func _run() -> void:
	root.get_node("ShopAudio")._can_play = false
	var rules := Fixture.opened()
	var scene: Node2D = load("res://presentation/shop/shop_play.gd").new()
	scene.shop = rules.shop
	scene.rules = rules
	scene.view = ShopView.new(rules)
	scene._font = load("res://art/ui/graybox_font.ttf")
	scene.ui = Control.new()
	scene._sortables = Node2D.new()
	root.add_child(scene._sortables)
	var actors := {}
	var seen := {}
	var sale_states: Array = []
	var on_sale := func(_sale: Dictionary) -> void: sale_states.append(rules.to_dict())
	rules.events.on("sale",on_sale)
	for tick in 1800:
		rules.step(0.1)
		var frame: Dictionary = scene.view.render_snapshot()
		var before := var_to_bytes(rules.to_dict())
		for worker: Dictionary in frame.workers:
			if not frame.flow.bundles.has(str(worker.id)): continue
			var summary: Dictionary = frame.flow.bundles[str(worker.id)]
			var key := "%s:%d"%[worker.action.steps[worker.action.index].kind,worker.carry_count]
			if seen.has(key): continue
			seen[key] = true
			if not actors.has(worker.id):
				var actor: Node2D = scene._actor(worker.kind)
				scene._sortables.add_child(actor)
				actors[worker.id] = actor
			var actor: Node2D = actors[worker.id]
			actor.display(worker,frame.clock)
			_check(actor.position.is_equal_approx(worker.pos),"rule position for "+key)
			_check(actor.carried.visible==(worker.carry_count>0),"physical carrying pose for "+key)
			_check(actor.amount.visible==(worker.carry_count>1),"bundle count badge for "+key)
			if worker.carry_count>1: _check(actor.amount.text=="×2","two distinct goods are displayed as two carried items")
			_check(summary.goods.size()==2 and summary.held==worker.carry_count,"detached lease summary matches carried count")
			var position: Vector2 = actor.position
			actor.display(worker,frame.clock)
			_check(actor.position==position,"rendering cannot advance the delivery")
			_check(var_to_bytes(rules.to_dict())==before,"rendering cannot commit stock or sale")
		if not sale_states.is_empty(): break
	rules.events.off("sale",on_sale)
	for key in ["move:0","pickup:0","transport:1","pickup:1","transport:2","drop:2"]: _check(seen.has(key),"actual multi-item pose covered: "+key)
	_check(sale_states.size()==1,"one complete order emits one sale")
	if not sale_states.is_empty():
		_check(sale_states[0].sold==2 and sale_states[0].serve.orders_done==1,"both lines visible as one completed transaction")
		_check(ShopRules.new(rules.shop).load_dict(sale_states[0]).is_empty(),"sale callback is independently resumable")
	scene._sortables.free()
	scene.ui.free()
	scene.free()
	await process_frame
	for error in errors.take(): _check(false,error)
	OS.remove_logger(errors)
	print("FLOW COMPOSITION GUI: %d checks, %d failures"%[checks,failed])
	quit(1 if failed else 0)
