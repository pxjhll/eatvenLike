extends SceneTree
## Real actor factory/display, driven only by detached rule positions. No player saves.
const Fixture := preload("res://tests/fixtures/movement_shop.gd")
var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL ",label)

func _run() -> void:
	root.get_node("ShopAudio")._can_play = false
	for mode in ["serve","single","handoff"]:
		var rules := Fixture.opened(mode)
		rules._next_customer = 0.1
		rules.run(1.0)
		var scene: Node2D = load("res://presentation/shop/shop_play.gd").new()
		_check(scene.has_method("_update_customers_motion"),"authoritative renderer exists")
		if not scene.has_method("_update_customers_motion"):
			scene.free()
			continue
		var art: Node2D = load(rules.shop.scene_path).instantiate()
		scene.shop = rules.shop
		scene.rules = rules
		scene.view = ShopView.new(rules)
		scene.anchors = ShopAnchors.new(art.get_node("Anchors"))
		scene._font = load("res://art/ui/graybox_font.ttf")
		scene.ui = Control.new()
		scene._sortables = Node2D.new()
		root.add_child(scene._sortables)
		var seen_states := {}
		for time in [1.0,12.0,40.0,80.0]:
			rules.run(time-rules.clock)
			var frame: Dictionary = scene.view.render_snapshot()
			var before := var_to_bytes(rules.to_dict())
			var displayed := {}
			for delta in [0.0,0.016,0.5,10.0]:
				scene._update_customers(delta,frame)
				_check(scene._customers.size()==frame.movement.customers.size(),"all authoritative actors rendered "+mode)
				for key in frame.movement.customers:
					var row: Dictionary = frame.movement.customers[key]
					seen_states[row.state] = true
					_check(scene._customers.has(key),"stable authoritative identity")
					if not scene._customers.has(key): continue
					var actor: Node2D = scene._customers[key]
					if not row.seated: _check(actor.position.is_equal_approx(row.pos),"rule position is the actual walking position "+mode)
					if displayed.has(key): _check(actor.position==displayed[key],"GUI delta cannot move customer "+mode)
					displayed[key] = actor.position
				_check(var_to_bytes(rules.to_dict())==before,"rendering leaves all live rules unchanged")
		_check(seen_states.has("queue") if mode!="handoff" else seen_states.has("order"),"actual arriving actors rendered")
		# Actors absent from a later rule snapshot are removed immediately; exit
		# routes themselves remain rule records until the exit is reached.
		var empty: Dictionary = scene.view.render_snapshot()
		empty.movement.customers.clear()
		scene._update_customers(100.0,empty)
		_check(scene._customers.is_empty(),"renderer does not invent exit movement")
		if mode=="handoff":
			var dining: Node2D = load("res://presentation/shop/shop_dining.gd").new()
			root.add_child(dining)
			dining.setup(scene.anchors,"dine",scene.view.item_art,110.0,1.0)
			var served := {"seat":0,"seated":true,"target":"seat:dine/0","state":"diner","dish":"lemonade"}
			dining.refresh_authoritative(2,[served])
			_check(dining._cups.size()==1,"served diner has a table item")
			var waiting := served.duplicate(true)
			waiting.state = "seated"
			dining.refresh_authoritative(2,[waiting])
			_check(dining._cups.is_empty(),"next seated guest does not inherit prior diner's table item")
			_check(dining._diners.is_empty() and dining.walking_count()==0,"dining never duplicates authoritative actors")
			dining.free()
		scene._sortables.free()
		scene.ui.free()
		art.free()
		scene.free()
	await process_frame
	for error in errors.take(): _check(false,error)
	OS.remove_logger(errors)
	print("SHARED MOVEMENT GUI: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
