extends "res://tests/test_case.gd"
const Geometry := preload("res://tests/fixtures/movement_shop.gd")
const PATH := "res://game/rules/template/customers.gd"

func _motion(units := 1.0) -> RefCounted:
	check(ResourceLoader.exists(PATH), "every service template needs the same customer movement facts")
	if not ResourceLoader.exists(PATH): return null
	var shop := Geometry.definition("handoff", units)
	return load(PATH).new(RuleNav.new(shop.layout))

func test_customer_queue_pickup_and_exit_use_real_shared_arrival_facts() -> void:
	var motion := _motion()
	if motion == null: return
	check_eq(motion.spawn(1), "", "customer enters at the declared entrance")
	check_eq(motion.request(1, "queue:0"), "", "queue target")
	check(not motion.ready(1), "requesting a queue point is not arrival")
	for tick in 100:
		motion.advance(0.1)
		if motion.ready(1, "queue:0"): break
	check(motion.ready(1, "queue:0"), "customer physically reached queue position")
	check_eq(motion.request(1, "pickup"), "", "pickup target")
	check(not motion.ready(1, "pickup"), "new target clears the old arrival fact")
	check(not motion.remove(1).is_empty(), "customer cannot disappear before reaching exit")
	for tick in 100:
		motion.advance(0.1)
		if motion.ready(1, "pickup"): break
	check(motion.ready(1, "pickup"), "actual pickup arrival")
	motion.request(1, "exit")
	for tick in 100:
		motion.advance(0.1)
		if motion.ready(1, "exit"): break
	check_eq(motion.remove(1), "", "remove only after actual exit")
	check_eq(motion.record(1), {}, "departed customer no longer rendered")

func test_pause_and_native_scale_preserve_the_shared_customer_speed() -> void:
	var first := _motion(1.0)
	if first == null: return
	var second := _motion(2.0)
	first.spawn(1)
	second.spawn(1)
	first.request(1, "queue:0")
	second.request(1, "queue:0")
	for tick in 10:
		first.advance(0.1)
		second.advance(0.1)
	check(Vector2(first.record(1).pos).is_equal_approx(Vector2(second.record(1).pos)/2.0), "native scene density does not change logical walking speed")
	var saved: Dictionary = first.snapshot()
	first.advance(60.0, true)
	check_eq(first.snapshot(), saved, "pause freezes customer navigation")

func test_missing_queue_or_customer_port_is_an_error_without_fallback_coordinates() -> void:
	var motion := _motion()
	if motion == null: return
	motion.spawn(1)
	var before: Dictionary = motion.snapshot()
	check(not motion.request(1, "queue:99").is_empty(), "an unauthored queue position is rejected")
	check(not motion.request(1, "unknown_port").is_empty(), "missing service port is rejected")
	check_eq(motion.snapshot(), before, "missing port does not move or retarget the customer")

func test_saved_customer_route_resumes_and_wrong_access_profile_is_rejected() -> void:
	var motion := _motion()
	if motion == null: return
	motion.spawn(1)
	motion.request(1, "queue:0")
	motion.advance(1.0)
	var saved: Dictionary = motion.snapshot()
	var reopened := _motion()
	check_eq(reopened.restore(saved), "", "restore current customer route")
	for tick in 100:
		motion.advance(0.1)
		reopened.advance(0.1)
		if motion.ready(1): break
	check_eq(reopened.snapshot(), motion.snapshot(), "restored route follows the same authoritative positions")
	var before: Dictionary = reopened.snapshot()
	var broken: Dictionary = before.duplicate(true)
	broken.customers[0].motion.profile = "staff"
	check(not reopened.restore(broken).is_empty(), "customers cannot load employee access rights")
	check_eq(reopened.snapshot(), before, "invalid profile cannot partially replace live motion")

func test_unreachable_customer_target_waits_without_direct_line_movement() -> void:
	check(ResourceLoader.exists(PATH), "public customer motion exists")
	if not ResourceLoader.exists(PATH): return
	var shop := Geometry.definition("handoff")
	shop.layout.customer_points.pickup = Vector2(3000,3000)
	var motion: RefCounted = load(PATH).new(RuleNav.new(shop.layout))
	motion.spawn(1)
	check_eq(motion.request(1, "pickup"), "", "known port requests a route even when unreachable")
	var position: Vector2 = motion.record(1).pos
	for tick in 20: motion.advance(0.1)
	check_eq(motion.record(1).pos, position, "unreachable route never becomes a straight-line fallback")
	check(not motion.ready(1), "empty path cannot count as arrival")
