extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const Fixture := preload("res://tests/fixtures/movement_shop.gd")
const Motion := preload("res://game/rules/customer_movement.gd")
var _motion: RefCounted = Motion.new()

func _available() -> bool:
	var available := _motion.has_method("sync_records")
	check(available,"customer motion needs a neutral intent input independent of business records")
	return available

func _record() -> Dictionary:
	return {"key":"guest:9","id":9,"target":"pickup","goal":Vector2(300,500),"data":{"state":"waiting","dish":"lemonade","wait":1.0,"seat":-1},"seated":false}

func test_same_neutral_customer_intent_moves_identically_under_all_old_business_labels() -> void:
	if not _available(): return
	var snapshots: Array = []
	for mode in ["handoff","single","serve"]:
		var owner := LegacyRules.new(Fixture.definition(mode),42)
		check_eq(_motion.call("sync_records",owner,[_record()]),"","accept neutral record")
		var start: Vector2 = owner.movement.customers["guest:9"].pos
		check_eq(start,owner.shop.layout.customer_points.entrance,"sync alone never teleports to target")
		for tick in 20:
			Motion.tick(owner,0.1)
			_motion.call("sync_records",owner,[_record()])
		snapshots.append(owner.movement.duplicate(true))
	check_eq(snapshots[0],snapshots[1],"handoff and single labels do not select a movement behavior")
	check_eq(snapshots[1],snapshots[2],"serve label does not select another movement behavior")

func test_invalid_intent_is_rejected_before_any_motion_or_actor_mutation() -> void:
	if not _available(): return
	var owner := LegacyRules.new(Fixture.definition(),42)
	_motion.call("sync_records",owner,[_record()])
	var before := owner.movement.duplicate(true)
	var bad := _record()
	bad.goal = Vector2(INF,0)
	check(not String(_motion.call("sync_records",owner,[bad])).is_empty(),"invalid geometry cannot select a fallback path")
	check_eq(owner.movement,before,"rejected record leaves route and actor intact")

func test_leaving_uses_same_exit_and_only_removes_actor_after_real_arrival() -> void:
	if not _available(): return
	var owner := LegacyRules.new(Fixture.definition(),42)
	_motion.call("sync_records",owner,[_record()])
	Motion.tick(owner,0.1)
	_motion.call("sync_records",owner,[])
	check(owner.movement.customers.has("guest:9"),"removal requests an exit instead of deleting an actor")
	for tick in 300:
		Motion.tick(owner,0.1)
		if owner.movement.customers.is_empty(): break
	check_eq(owner.movement.customers,{},"actual arrival completes departure")
