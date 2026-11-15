extends "res://tests/test_case.gd"
const INVENTORY := preload("res://game/rules/template/inventory.gd")
const PATH := "res://game/rules/template/machines.gd"

func _new_machines(inventory: RefCounted) -> RefCounted:
	check(ResourceLoader.exists(PATH), "all device capabilities need one machine lifecycle")
	if not ResourceLoader.exists(PATH): return null
	return load(PATH).new(inventory)

func _inventory() -> RefCounted:
	var inventory := INVENTORY.new()
	inventory.configure("input", 8)
	inventory.configure("output", 8)
	inventory.seed("input", "raw", 4)
	return inventory

func test_automatic_machine_uses_reserved_inputs_and_produces_once() -> void:
	var inventory := _inventory()
	var machines := _new_machines(inventory)
	if machines == null: return
	check_eq(machines.configure("device", "input", "output"), "", "device configuration")
	var run: Dictionary = machines.start("device", {"raw":2}, {"tea":2}, 3.0)
	check_eq(run.error, "", "start automatic operation")
	check_eq(inventory.quantity("input", "raw", -1, true), 2, "two inputs are exclusively reserved")
	check_eq(inventory.quantity("output", "tea"), 0, "not produced early")
	machines.advance(2.9)
	check_eq(inventory.quantity("output", "tea"), 0, "still processing")
	machines.advance(0.1)
	check_eq(inventory.quantity("input", "raw"), 2, "consume the reserved amount once")
	check_eq(inventory.quantity("output", "tea"), 2, "one batch output")
	machines.advance(20.0)
	check_eq(inventory.quantity("output", "tea"), 2, "completed run cannot produce again")
	check_eq(machines.status("device").output, 2, "machine UI sees the authoritative stock")
	check_eq(machines.audit(), [], "machine and inventory agreement")

func test_manual_operation_waits_for_an_employee_and_uses_the_same_clock() -> void:
	var inventory := _inventory()
	var machines := _new_machines(inventory)
	if machines == null: return
	machines.configure("device", "input", "output", {"manual":true})
	var run: Dictionary = machines.start("device", {"raw":1}, {"meal":1}, 2.0)
	machines.advance(10.0)
	check_eq(inventory.quantity("output", "meal"), 0, "manual device cannot operate unattended")
	check_eq(machines.engage(run.id, 4), "", "employee starts the shared operation")
	machines.advance(1.0)
	check(is_equal_approx(float(machines.status("device").progress), 0.5), "UI reads the same operation clock")
	machines.advance(1.0)
	check_eq(inventory.quantity("output", "meal"), 1, "manual output uses the common transaction")
	check_eq(machines.run(run.id).operator, -1, "completion releases the employee")
	check_eq(machines.audit(), [], "manual run invariants")

func test_loading_stirring_and_unloading_are_composed_public_stages() -> void:
	var inventory := _inventory()
	var machines := _new_machines(inventory)
	if machines == null: return
	machines.configure("device", "input", "output", {"load_seconds":1.0, "unload_seconds":1.0, "stir_points":[0.5], "stir_seconds":1.0})
	var run: Dictionary = machines.start("device", {"raw":2}, {"rice":4}, 4.0)
	check_eq(machines.run(run.id).phase, "await_load", "batch begins with manual loading")
	machines.engage(run.id, 1)
	machines.advance(1.0)
	check_eq(machines.run(run.id).phase, "processing", "automatic cooking releases staff after loading")
	machines.advance(2.0)
	check_eq(machines.run(run.id).phase, "await_stir", "automatic clock stops at stirring point")
	machines.advance(10.0)
	check_eq(inventory.quantity("output", "rice"), 0, "cannot skip required interaction")
	machines.engage(run.id, 2)
	machines.advance(1.0)
	machines.advance(2.0)
	check_eq(machines.run(run.id).phase, "await_unload", "finished pot waits for public unload operation")
	check_eq(inventory.quantity("output", "rice"), 0, "unloaded output is not available early")
	machines.engage(run.id, 2)
	machines.advance(1.0)
	check_eq(inventory.quantity("output", "rice"), 4, "one batch becomes available on unload completion")
	check_eq(machines.audit(), [], "composed stage invariants")

func test_missing_branch_capacity_and_machine_slot_prevent_start_atomically() -> void:
	var inventory := _inventory()
	var machines := _new_machines(inventory)
	if machines == null: return
	machines.configure("device", "input", "output")
	var before: Dictionary = inventory.snapshot()
	check(not machines.start("device", {"raw":1, "sauce":1}, {"meal":1}, 1.0).error.is_empty(), "merge cannot start with a missing branch")
	check_eq(inventory.snapshot(), before, "failed production does not reserve any input")
	var run: Dictionary = machines.start("device", {"raw":1}, {"meal":1}, 2.0)
	check_eq(run.error, "", "first slot available")
	before = inventory.snapshot()
	check(not machines.start("device", {"raw":1}, {"meal":1}, 2.0).error.is_empty(), "machine has only one slot")
	check_eq(inventory.snapshot(), before, "occupied machine cannot reserve more material")
	check_eq(machines.cancel(run.id), "", "cancel a running operation")
	check_eq(inventory.quantity("input", "raw", -1, true), 4, "all input reservations released")
	check_eq(inventory.quantity("output", "meal"), 0, "cancel does not produce")
	check_eq(machines.cancel(run.id), "", "compensation is idempotent")
	check_eq(machines.audit(), [], "cancelled operation")

func test_pause_and_restore_preserve_remaining_work_and_commit_once() -> void:
	var inventory := _inventory()
	var machines := _new_machines(inventory)
	if machines == null: return
	machines.configure("device", "input", "output")
	var run: Dictionary = machines.start("device", {"raw":1}, {"meal":1}, 5.0)
	machines.advance(2.0)
	var saved: Dictionary = machines.snapshot()
	machines.advance(100.0, true)
	check_eq(machines.snapshot(), saved, "paused clocks do not advance")
	var loaded_inventory := INVENTORY.new()
	check_eq(loaded_inventory.restore(inventory.snapshot()), "", "restore authoritative inventory")
	var loaded := _new_machines(loaded_inventory)
	check_eq(loaded.restore(saved), "", "restore machine against the same claims")
	loaded.advance(3.0)
	check_eq(loaded_inventory.quantity("output", "meal"), 1, "resume only the remaining time")
	check_eq(loaded.run(run.id).phase, "completed", "original run completes")
	loaded.advance(3.0)
	check_eq(loaded_inventory.quantity("output", "meal"), 1, "no second production after restore")
	check_eq(loaded.audit(), [], "restored clock and inventory agree")

func test_invalid_saved_claim_or_clock_is_rejected_without_mutation() -> void:
	var inventory := _inventory()
	var machines := _new_machines(inventory)
	if machines == null: return
	machines.configure("device", "input", "output")
	machines.start("device", {"raw":1}, {"meal":1}, 5.0)
	var original: Dictionary = machines.snapshot()
	var broken: Dictionary = original.duplicate(true)
	broken.runs[0].claim = 99
	check(not machines.restore(broken).is_empty(), "machine cannot refer to a different inventory transaction")
	check_eq(machines.snapshot(), original, "bad references do not replace live machine state")
	broken = original.duplicate(true)
	broken.runs[0].remaining = -1.0
	check(not machines.restore(broken).is_empty(), "negative clocks rejected")
	check_eq(machines.snapshot(), original, "bad clocks do not replace live machine state")
	check(not machines.advance(NAN).is_empty(), "invalid dt rejected")
	check_eq(machines.snapshot(), original, "invalid dt cannot corrupt time")

func test_recalled_employee_keeps_completed_manual_work_on_reassignment() -> void:
	var inventory := _inventory()
	var machines := _new_machines(inventory)
	if machines == null: return
	machines.configure("device", "input", "output", {"manual":true})
	var task: Dictionary = machines.start("device", {"raw":1}, {"meal":1}, 5.0)
	machines.engage(task.id, 1)
	machines.advance(2.0)
	check_eq(machines.release_employee(task.id, 1), "", "recall releases employee only")
	machines.advance(10.0)
	check_eq(inventory.quantity("output", "meal"), 0, "unattended unfinished work stops")
	check_eq(machines.engage(task.id, 2), "", "another employee takes the unfinished stage")
	machines.advance(3.0)
	check_eq(inventory.quantity("output", "meal"), 1, "only three remaining seconds are required")
	check_eq(machines.audit(), [], "recall and reassignment preserve the original claim")

func test_bad_capability_configuration_is_rejected_and_employees_cannot_double_operate() -> void:
	var inventory := _inventory()
	var machines := _new_machines(inventory)
	if machines == null: return
	check(not machines.configure("bad", "input", "output", {"custom_tick":"shop_script"}).is_empty(), "arbitrary behavior is not a machine capability")
	check(not machines.configure("bad", "input", "output", {"stir_points":[0.7, 0.3]}).is_empty(), "unordered stopping points rejected")
	for id in ["a", "b"]: machines.configure(id, "input", "output", {"manual":true})
	var a: Dictionary = machines.start("a", {"raw":1}, {"meal":1}, 2.0)
	var b: Dictionary = machines.start("b", {"raw":1}, {"meal":1}, 2.0)
	check_eq(machines.engage(a.id, 1), "", "one employee acquires first stage")
	check(not machines.engage(b.id, 1).is_empty(), "the same employee cannot occupy another machine")
	check_eq(machines.engage(b.id, 2), "", "a different employee can work concurrently")
	machines.advance(2.0)
	check_eq(inventory.quantity("output", "meal"), 2, "independent machines complete using shared stock reservations")
	check_eq(machines.audit(), [], "parallel operations conserve inputs")

func test_reassigned_manual_work_uses_the_new_employee_rate_without_resetting_progress() -> void:
	var inventory := _inventory()
	var machines := _new_machines(inventory)
	if machines == null: return
	machines.configure("device", "input", "output", {"manual":true})
	var operation: Dictionary = machines.start("device", {"raw":1}, {"meal":1}, 6.0)
	check_eq(machines.engage(operation.id, 1, 1.0), "", "first employee works at normal rate")
	machines.advance(2.0)
	machines.release_employee(operation.id, 1)
	check_eq(machines.engage(operation.id, 2, 2.0), "", "faster employee resumes the same stage")
	machines.advance(2.0)
	check_eq(inventory.quantity("output", "meal"), 1, "four units of remaining work take two seconds at rate two")
	check_eq(machines.audit(), [], "work rates and saved progress remain consistent")
