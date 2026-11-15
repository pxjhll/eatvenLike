extends "res://tests/test_case.gd"
const Actors := preload("res://tests/fixtures/movement_shop.gd")
const Runner := preload("res://game/rules/template/capability_runner.gd")

func _runner(rules: ShopRules) -> RefCounted:
	var runner := Runner.new(rules)
	check(runner.has_method("interact"), "admission needs a public arrival-and-work capability")
	if not runner.has_method("interact"): return null
	rules.workers[0].post = ""
	rules.workers[0].pos = Vector2(500,500)
	runner.define_place("front", Vector2(180,180))
	return runner

func test_interaction_walks_to_its_port_then_works_before_publishing_one_completion() -> void:
	var rules := Actors.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	check_eq(runner.interact(worker.id, "front", 1.0, "admit", 7), "", "known public purpose")
	check_eq(runner.take_interactions(), [], "walking is not admission")
	var worked := 0
	for tick in 300:
		if worker.phase == "work":
			worked += 1
			check(worker.pos.is_equal_approx(Vector2(180,180)), "employee works at actual admission port")
		runner.step(0.1)
		if runner.idle(worker.id): break
	check_eq(worked, 10, "real employee work clock")
	var events: Array = runner.take_interactions()
	check_eq(events.size(), 1, "one terminal result")
	check_eq(events[0].subject, 7, "stable customer reference")
	check_eq(events[0].result, "completed", "service can commit admission after completion")
	check_eq(runner.take_interactions(), [], "cannot consume twice")

func test_cancelled_and_restored_interactions_never_publish_a_success_for_a_recalled_employee() -> void:
	var rules := Actors.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	runner.interact(worker.id, "front", 1.0, "admit", 7)
	for tick in 10: runner.step(0.1)
	var saved: Dictionary = runner.snapshot()
	var reopened_rules := Actors.opened("handoff")
	var reopened := _runner(reopened_rules)
	check_eq(reopened.restore(saved), "", "restore standard movement and interaction program")
	check_eq(reopened.cancel(worker.id), "", "recall")
	check_eq(reopened.cancel(worker.id), "", "repeat recall")
	var events: Array = reopened.take_interactions()
	check_eq(events.size(), 1, "one cancellation result")
	check_eq(events[0].result, "cancelled", "cancel is never interpreted as order taken")
	check_eq(reopened_rules.workers[0].completed, 0, "no fake completed work")

func test_unknown_interaction_purpose_cannot_install_shop_callbacks() -> void:
	var rules := Actors.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var before: Dictionary = runner.snapshot()
	check(not runner.interact(rules.workers[0].id, "front", 1.0, "private_shop_callback", 7).is_empty(), "only public interaction purposes")
	check_eq(runner.snapshot(), before, "bad request is atomic")
