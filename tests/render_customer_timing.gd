extends SceneTree

const TestSession := preload("res://tests/shop_test_session.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
var failures := 0
var errors := preload("res://tests/error_counter.gd").new()


func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")


func _run() -> void:
	for speed in [1.0, 2.0]:
		var scene = load("res://presentation/shop/shop_play.tscn").instantiate()
		scene.session = TestSession.make(TEA, "customer-timing-%d-%s" % [OS.get_process_id(), speed])
		root.add_child(scene)
		await process_frame
		scene.set_process(false)
		scene.guide.enabled = false
		scene._speed_factor = speed
		scene.rules.gold = 1000.0
		_check(scene.rules.unlock("lemonade").is_empty(), "open the formal shop to obtain a real customer route")
		scene.rules.run(0.2)
		var before := var_to_bytes(scene.rules.to_dict())
		var frame: Dictionary = scene.view.render_snapshot()
		var customer: String = frame.movement.customers.keys()[0]
		_check(frame.movement.customers[customer].walking, "exercise the published route of an actual moving customer")
		frame.paused = false
		frame.clock = 0.0
		scene._update_customers(0.0, frame)
		var actor = scene._customers[customer]
		var previous: int = actor.frame_actor.sprite.frame
		var last := 0.0
		var holds: Array[float] = []
		for sample in range(1, 121):
			var t := sample / 60.0
			# Business simulation still advances in 100ms steps, independently of the renderer.
			frame.clock = floor((t * speed + 0.00001) / 0.1) * 0.1
			var input := var_to_bytes(frame)
			scene._update_customers(1.0 / 60.0, frame)
			_check(var_to_bytes(frame) == input, "animation must not mutate the caller's business snapshot")
			var current: int = actor.frame_actor.sprite.frame
			if current != previous:
				holds.append(t - last)
				last = t
				previous = current
		_check(holds.size() >= int(13 * speed), "customer retains the original seven-pose animation rate")
		for hold in holds:
			_check(hold >= 0.14 / speed - 1.0 / 60.0 - 0.0001 and hold <= 0.15 / speed + 1.0 / 60.0 + 0.0001,
				"100ms business ticks must not quantize a source hold into 100/200ms; actual %.4fs at speed %.0f" % [hold, speed])
		var phase: float = actor.frame_actor.get_phase()
		scene._update_customers(0.0, frame)
		_check(is_equal_approx(actor.frame_actor.get_phase(), phase), "paused movement freezes customer animation")
		_check(var_to_bytes(scene.rules.to_dict()) == before, "animation must not alter business state, RNG or save data")
		print("CUSTOMER HOLDS x%.0f: %s" % [speed, holds])
		scene.free()
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("CUSTOMER TIMING: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + message)
