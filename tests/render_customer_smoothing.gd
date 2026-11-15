extends SceneTree
## Authoritative roots stay exact; the visible actor moves on every render frame.
var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ",label)

func _visible(actor: Node2D) -> Vector2:
	return actor.render_position() if actor.has_method("render_position") else actor.position

func _route_progress(path: PackedVector2Array, point: Vector2) -> float:
	var nearest := INF
	var progress := 0.0
	var length := 0.0
	var ambiguous := false
	for index in range(1,path.size()):
		var segment := path[index]-path[index-1]
		var distance := segment.length()
		var ratio := clampf((point-path[index-1]).dot(segment)/maxf(segment.length_squared(),0.000001),0.0,1.0)
		var gap := point.distance_squared_to(path[index-1]+segment*ratio)
		var candidate := length+distance*ratio
		if gap<nearest-0.0001:
			nearest = gap
			progress = candidate
			ambiguous = false
		elif absf(gap-nearest)<=0.0001 and absf(candidate-progress)>0.01:
			# A folded-back route can visit the same pixel twice. Such a point
			# has no unique geometric progress; compare its unambiguous frames.
			ambiguous = true
		length += distance
	return NAN if ambiguous else progress

func _scene(id: String) -> Node:
	var spec: Resource = load("res://content/shops/"+id+"/shop.tres")
	var owner := ShopRules.new(spec,42)
	var profile = load("res://game/app/profile.gd").new("user://smoothing-"+id+"-profile.json")
	profile.select_shop(id)
	var store := ShopSave.new(spec,"user://smoothing-"+id+"-shop.json")
	var session = load("res://game/app/shop_session.gd").new(profile,store,owner)
	session.guide_enabled = false
	var scene: Node = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = session
	root.add_child(scene)
	scene.set_process(false)
	owner.gold = maxf(owner.gold,float(spec.stages[0].cost))
	owner.unlock(spec.sold_at(0))
	return scene

func _motion(id: String) -> void:
	var scene := _scene(id)
	var previous := {}
	var previous_routes := {}
	var previous_progress := {}
	var moving := 0
	var repeats := 0
	var velocity_samples := 0
	var uneven_steps := 0
	var backward_steps := 0
	var expected_step: float = 170.0*scene.shop.layout.motion_units/60.0
	for tick in 240:
		scene._process(1.0/60.0)
		var frame: Dictionary = scene.view.render_snapshot()
		for key in frame.movement.customers:
			var row: Dictionary = frame.movement.customers[key]
			var actor: Node2D = scene._customers[key]
			if not row.seated: _check(actor.position.is_equal_approx(row.pos),id+": root remains authoritative")
			var point := _visible(actor)
			if row.walking and row.path.size()>1 and point.distance_to(row.path[-1])>expected_step*7.0:
				var progress := _route_progress(row.path,point)
				if is_finite(progress) and previous_routes.has(key) and previous_routes[key]==row.path:
					velocity_samples += 1
					var distance: float = progress-float(previous_progress[key])
					if distance< -0.001: backward_steps += 1
					if absf(distance-expected_step)>0.01: uneven_steps += 1
				if is_finite(progress):
					previous_routes[key] = row.path.duplicate()
					previous_progress[key] = progress
				else:
					previous_routes.erase(key)
					previous_progress.erase(key)
			else:
				previous_routes.erase(key)
				previous_progress.erase(key)
			if previous.has(key) and row.walking and row.path.size()>row.path_index and point.distance_to(row.path[-1])>25.0:
				moving += 1
				if point.is_equal_approx(previous[key]): repeats += 1
			previous[key] = point
	_check(moving>30,id+": observed sustained movement")
	_check(repeats<maxi(2,moving/20),id+": visible movement updates between 10 Hz snapshots (%d/%d repeated)"%[repeats,moving])
	_check(velocity_samples>30,id+": observed stable route velocity")
	_check(backward_steps==0,id+": visible route progress never snaps backward (%d/%d)"%[backward_steps,velocity_samples])
	_check(uneven_steps==0,id+": every visible step matches authoritative scene-unit speed (%d/%d uneven)"%[uneven_steps,velocity_samples])
	var paused_positions := {}
	for key in scene._customers: paused_positions[key] = _visible(scene._customers[key])
	scene.rules.paused = true
	for tick in 10: scene._process(1.0/60.0)
	for key in paused_positions: _check(_visible(scene._customers[key])==paused_positions[key],id+": pause freezes the actual visible point")
	scene.rules.paused = false
	scene._speed_factor = 2.0
	for tick in 12: scene._process(1.0/60.0)
	_check(scene.rules.clock>4.1,id+": resume at double speed advances the shared simulation")
	print("MOTION ",id," moving=",moving," repeated=",repeats," velocity_samples=",velocity_samples," uneven=",uneven_steps," backward=",backward_steps)
	scene.free()

func _route_and_lifecycle() -> void:
	var scene := _scene("tea")
	var row := {"id":999,"pos":Vector2(100,100),"path":PackedVector2Array([Vector2(100,100),Vector2(105,100),Vector2(105,200)]),"path_index":1,"walking":true,"seated":false,"dish":"","state":"queue","carry_item":"","carry_count":0,"wait":0.0,"seat":-1,"target":"queue:0","takeaway":false,"mood":0,"exiting":false,"presentation_version":1,"held_items":[]}
	var frame := {"clock":0.0,"paused":false,"presentation_version":1,"movement":{"customers":{"probe":row}}}
	scene._update_customers(0.0,frame)
	var actor: Node2D = scene._customers.probe
	var before := var_to_bytes(row)
	scene._update_customers(1.0/60.0,frame)
	var point := _visible(actor)
	_check(point.x>100.0 and point.x<=105.0,"predict only along first approved segment")
	scene._update_customers(3.0/60.0,frame)
	point = _visible(actor)
	_check(is_equal_approx(point.x,105.0) and point.y>100.0,"turn through waypoint without cutting corner")
	scene._z_by_y = true
	scene._update_customers(1.0/60.0,frame)
	_check(actor.z_index==int(_visible(actor).y),"depth ordering follows the visible feet when crossing a Y boundary")
	point = _visible(actor)
	_check(actor.position==row.pos and var_to_bytes(row)==before,"smoothing never edits authoritative root or snapshot")
	var frozen := point
	scene._update_customers(0.0,frame)
	_check(_visible(actor)==frozen,"paused renders preserve the visual pose")
	scene._speed_factor = 2.0
	scene._update_customers(1.0/120.0,frame)
	_check(is_equal_approx(_visible(actor).y-frozen.y,170.0/60.0),"double speed scales render distance in simulation time")
	scene._speed_factor = 1.0
	row.walking = false
	row.pos = Vector2(105,200)
	frame.clock = 0.1
	scene._update_customers(1.0/60.0,frame)
	_check(_visible(actor)==row.pos,"arrival immediately uses authority with no delivery lag")
	row.walking = true
	row.pos = Vector2(700,500)
	row.path = PackedVector2Array()
	frame.clock = 0.2
	scene._update_customers(0.016,frame)
	_check(_visible(actor)==row.pos,"no route means no invented movement")
	row.path = PackedVector2Array([row.pos,row.pos+Vector2(100,0)])
	row.path_index = 1
	frame.clock = 0.0
	scene._update_customers(0.016,frame)
	_check(_visible(actor)==row.pos,"rewind or restore resets prediction")
	row.pos = Vector2(900,800)
	row.path = PackedVector2Array([row.pos,row.pos+Vector2(0,100)])
	scene._update_customers(0.016,frame)
	point = _visible(actor)
	_check(is_equal_approx(point.x,900.0) and point.y>=800.0 and point.y<818.0,"teleport projects only from the new authoritative route")
	frame.movement.customers.clear()
	scene._update_customers(0.0,frame)
	_check(scene._customers.is_empty(),"removed actors leave no smoothing state")
	scene.free()

func _run() -> void:
	root.size = Vector2i(720,1280)
	root.get_node("ShopAudio")._can_play = false
	for id in ["tea","pancake","stirfry"]: _motion(id)
	_route_and_lifecycle()
	await process_frame
	for error in errors.take(): _check(false,error)
	OS.remove_logger(errors)
	print("CUSTOMER SMOOTHING: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
