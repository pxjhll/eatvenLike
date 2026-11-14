extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
## Real actor factory consumes action snapshots; no GUI callback owns business.
const Fixture := preload("res://tests/fixtures/movement_shop.gd")
const Adapter := preload("res://game/rules/serve_action_context.gd")
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
	var shop := Fixture.definition()
	shop.dispatch.action_version = 1
	var rules := LegacyRules.new(shop,42)
	rules.gold = 100000.0
	rules.unlock(shop.goals.opening_station)
	var scene: Node2D = load("res://presentation/shop/shop_play.gd").new()
	scene.rules = rules
	scene.shop = shop
	scene.view = ShopView.new(rules)
	scene._font = load("res://art/ui/graybox_font.ttf")
	scene.ui = Control.new()
	scene._sortables = Node2D.new()
	root.add_child(scene._sortables)
	var actors := {}
	var seen := {}
	var inserted_wait := false
	for tick in 1000:
		rules.step(0.1)
		var frame: Dictionary = scene.view.render_snapshot()
		var before := var_to_bytes(rules.to_dict())
		for worker: Dictionary in frame.workers:
			if not worker.has("action"): continue
			var summary: Dictionary = frame.actions[str(worker.id)]
			var kind := String(summary.kind)
			if not actors.has(worker.id):
				var created: Node2D = scene._actor(worker.kind)
				scene._sortables.add_child(created)
				actors[worker.id] = created
			var actor: Node2D = actors[worker.id]
			actor.display(worker,frame.clock)
			if not seen.has(kind):
				seen[kind] = true
				_check(actor.position.is_equal_approx(worker.pos),"actual position for "+kind)
				_check(actor.carried.visible==(worker.carry_count>0),"carried item for "+kind)
				_check(summary.status in ["running","blocked"],"readable lifecycle status")
				var position: Vector2 = actor.position
				actor.display(worker,frame.clock)
				_check(actor.position==position,"frozen snapshot never advances "+kind)
				_check(var_to_bytes(rules.to_dict())==before,"display does not submit "+kind)
			if kind=="pickup" and not inserted_wait:
				var live: Dictionary = rules.worker_by_id(int(worker.id))
				live.action.steps.insert(live.action.index+1,Adapter.step("wait","","等待",0.3))
				inserted_wait = true
		if seen.size()==6 and rules.sold>0: break
	for kind in ["move","pickup","operate","transport","drop","wait"]: _check(seen.has(kind),"actual action pose covered: "+kind)
	_check(rules.sold>0,"real composed actions complete a sale")
	_check(LegacyRules.new(shop).load_dict(rules.to_dict()).is_empty(),"rendered actions remain valid saved rules")
	scene._sortables.free()
	scene.ui.free()
	scene.free()
	await process_frame
	for error in errors.take(): _check(false,error)
	OS.remove_logger(errors)
	print("ACTOR ACTION GUI: %d checks, %d failures"%[checks,failed])
	quit(1 if failed else 0)
