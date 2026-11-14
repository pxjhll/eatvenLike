extends "res://tests/test_case.gd"
## These contracts catch early pickup, ignored capacity, duplicated goods and
## lost cancellation reservations. Expectations are hand-derived quantities.
const PATH := "res://game/rules/template/inventory.gd"

func _new_inventory() -> RefCounted:
	check(ResourceLoader.exists(PATH), "a shared authoritative inventory is required")
	if not ResourceLoader.exists(PATH): return null
	return load(PATH).new()

func _stock(inventory: RefCounted, at: String, capacity := 8, infinite: Array = []) -> void:
	check_eq(inventory.configure(at, capacity, infinite), "", "configure " + at)

func test_same_pickup_and_drop_contract_across_template_layouts() -> void:
	for places in [["pot", "mix"], ["pantry", "griddle"], ["rice", "plating"]]:
		var inventory := _new_inventory()
		if inventory == null: return
		_stock(inventory, places[0])
		_stock(inventory, places[1])
		check_eq(inventory.seed(places[0], "ingredient", 3).error, "", "initial stock")
		var task: Dictionary = inventory.reserve_transfer(1, places[0], places[1], "ingredient", 3, 2)
		check_eq(task.error, "", "reserve transfer")
		check_eq(task.count, 2, "worker capacity limits pickup")
		check_eq(inventory.quantity("hand:1", "ingredient"), 0, "reservation never creates a held item")
		check_eq(inventory.quantity(places[0], "ingredient"), 3, "not physically picked yet")
		check_eq(inventory.pickup(task.id), "", "pickup completion")
		check_eq(inventory.quantity("hand:1", "ingredient"), 2, "completed pickup creates held quantity")
		check_eq(inventory.quantity(places[0], "ingredient"), 1, "stock debited once")
		check_eq(inventory.pickup(task.id), "", "duplicate completion is harmless")
		check_eq(inventory.quantity("hand:1", "ingredient"), 2, "duplicate pickup cannot mint goods")
		check_eq(inventory.drop(task.id), "", "drop completion")
		check_eq(inventory.quantity("hand:1", "ingredient"), 0, "drop removes hand icon source")
		check_eq(inventory.quantity(places[1], "ingredient"), 2, "destination receives the same goods")
		check_eq(inventory.drop(task.id), "", "duplicate drop is harmless")
		check_eq(inventory.quantity(places[1], "ingredient"), 2, "drop cannot duplicate")
		check_eq(inventory.audit(), [], "conservation and reservations")

func test_source_target_and_worker_cannot_be_over_reserved() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "source")
	_stock(inventory, "target", 2)
	inventory.seed("source", "rice", 5)
	var first: Dictionary = inventory.reserve_transfer(1, "source", "target", "rice", 4, 3)
	check_eq(first.count, 2, "destination capacity also limits transfer")
	check_eq(inventory.incoming("target", "rice", -1), 2, "inbound query includes reserved delivery")
	var before: Dictionary = inventory.snapshot()
	check(not inventory.reserve_transfer(2, "source", "target", "rice", 1, 3).error.is_empty(), "reserved destination cannot be overfilled")
	check_eq(inventory.snapshot(), before, "failed reservation has no partial side effects")
	_stock(inventory, "other")
	check(not inventory.reserve_transfer(1, "source", "other", "rice", 1, 3).error.is_empty(), "one worker cannot hold two active assignments")
	inventory.cancel(first.id)
	var second: Dictionary = inventory.reserve_transfer(2, "source", "other", "rice", 8, 8)
	check_eq(second.count, 5, "source availability limits transfer")
	check(not inventory.reserve_transfer(3, "source", "target", "rice", 1, 1).error.is_empty(), "same goods cannot be reserved twice")
	check_eq(inventory.audit(), [], "reservation invariants")

func test_cancel_after_pickup_retains_return_capacity_and_original_ownership() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "source", 2)
	_stock(inventory, "target", 2)
	inventory.seed("source", "rice", 2)
	var task: Dictionary = inventory.reserve_transfer(1, "source", "target", "rice", 2, 2, -1, 41)
	inventory.pickup(task.id)
	check_eq(inventory.quantity("hand:1", "rice", 41), 2, "shared stock allocated only on physical pickup")
	check(not inventory.seed("source", "rice", 1).error.is_empty(), "return slots prevent refill from blocking cancellation")
	check_eq(inventory.cancel(task.id), "", "cancel held goods")
	check_eq(inventory.quantity("source", "rice", -1), 2, "shared source ownership restored")
	check_eq(inventory.quantity("hand:1", "rice"), 0, "hand cleared")
	check_eq(inventory.cancel(task.id), "", "repeated cancel harmless")
	check_eq(inventory.quantity("source", "rice"), 2, "compensation runs once")
	check_eq(inventory.audit(), [], "cancel conserves stock")

func test_owned_material_is_never_borrowed_by_another_order() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "input")
	_stock(inventory, "output")
	inventory.seed("input", "dish", 2, 31)
	check(not inventory.reserve_transfer(1, "input", "output", "dish", 1, 2, 32).error.is_empty(), "order 32 cannot claim order 31 ingredients")
	var task: Dictionary = inventory.reserve_transfer(1, "input", "output", "dish", 2, 2, 31)
	inventory.pickup(task.id)
	inventory.cancel(task.id)
	check_eq(inventory.quantity("input", "dish", 31), 2, "owned material keeps its owner on return")
	check_eq(inventory.audit(), [], "owned cancellation")

func test_infinite_source_mints_at_pickup_and_cancel_accounts_for_it() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "pantry", -1, ["raw"])
	_stock(inventory, "bench")
	var task: Dictionary = inventory.reserve_transfer(1, "pantry", "bench", "raw", 3, 2)
	check_eq(inventory.quantity("hand:1", "raw"), 0, "planning does not create raw ingredients")
	inventory.pickup(task.id)
	check_eq(inventory.quantity("hand:1", "raw"), 2, "source material appears on completed pickup")
	inventory.cancel(task.id)
	check_eq(inventory.quantity("pantry", "raw"), 0, "infinite source does not gain a finite pile on cancel")
	check_eq(inventory.audit(), [], "discarded minted materials are accounted for")

func test_multiple_inputs_commit_atomically_and_only_once() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "bench", 3)
	inventory.seed("bench", "rice", 1, 7)
	var before: Dictionary = inventory.snapshot()
	check(not inventory.reserve_operation(1, "bench", {"rice":1, "sauce":1}, {"meal":1}, 7).error.is_empty(), "missing branch blocks combine")
	check_eq(inventory.snapshot(), before, "missing input cannot reserve a partial recipe")
	inventory.seed("bench", "sauce", 1, 7)
	var task: Dictionary = inventory.reserve_operation(1, "bench", {"rice":1, "sauce":1}, {"meal":1}, 7)
	check_eq(task.error, "", "all recipe inputs available")
	check_eq(inventory.quantity("bench", "rice"), 1, "reserve does not consume")
	check_eq(inventory.quantity("bench", "meal"), 0, "reserve does not produce")
	check_eq(inventory.complete_operation(task.id), "", "complete operation")
	check_eq(inventory.quantity("bench", "rice"), 0, "input consumed")
	check_eq(inventory.quantity("bench", "sauce"), 0, "other input consumed atomically")
	check_eq(inventory.quantity("bench", "meal", 7), 1, "product keeps order ownership")
	check_eq(inventory.complete_operation(task.id), "", "duplicate work commit harmless")
	check_eq(inventory.quantity("bench", "meal"), 1, "work cannot duplicate product")
	check_eq(inventory.audit(), [], "recipe conservation accounting")

func test_cancelled_operation_releases_all_inputs_and_output_space() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "bench", 2)
	inventory.seed("bench", "raw", 2)
	var task: Dictionary = inventory.reserve_operation(1, "bench", {"raw":2}, {"meal":1})
	check_eq(task.error, "", "a full machine can reserve a reducing recipe")
	check_eq(inventory.cancel(task.id), "", "cancel uncommitted processing")
	check_eq(inventory.quantity("bench", "raw"), 2, "input remains")
	check_eq(inventory.quantity("bench", "meal"), 0, "no product exists")
	var next: Dictionary = inventory.reserve_operation(2, "bench", {"raw":2}, {"meal":1})
	check_eq(next.error, "", "next worker can acquire all released inputs")
	check_eq(inventory.audit(), [], "cancelled work reservations")

func test_saved_transfer_resumes_without_second_pickup_or_lost_return_claim() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "source", 3)
	_stock(inventory, "target", 3)
	inventory.seed("source", "tea", 3)
	var task: Dictionary = inventory.reserve_transfer(1, "source", "target", "tea", 2, 2)
	inventory.pickup(task.id)
	var reopened := _new_inventory()
	check_eq(reopened.restore(inventory.snapshot()), "", "restore in-flight goods")
	check_eq(reopened.pickup(task.id), "", "replayed pickup is not a second take")
	check_eq(reopened.drop(task.id), "", "resume the original drop")
	check_eq(reopened.quantity("source", "tea"), 1, "remaining source")
	check_eq(reopened.quantity("target", "tea"), 2, "same two goods delivered")
	check_eq(reopened.audit(), [], "restored ownership and reservation invariants")

func test_invalid_restore_and_mutating_snapshot_do_not_change_live_inventory() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "source")
	_stock(inventory, "target")
	inventory.seed("source", "tea", 3)
	var task: Dictionary = inventory.reserve_transfer(1, "source", "target", "tea", 2, 2)
	var original: Dictionary = inventory.snapshot()
	var broken: Dictionary = original.duplicate(true)
	broken.lots[0].count = -1
	check(not inventory.restore(broken).is_empty(), "negative stock is rejected")
	check_eq(inventory.snapshot(), original, "failed restore does not mutate live state")
	broken = original.duplicate(true)
	broken.claims[0].parts[0].count = 99
	check(not inventory.restore(broken).is_empty(), "reservation exceeding real stock is rejected")
	check_eq(inventory.snapshot(), original, "failed reservation restore is atomic")
	var detached: Dictionary = inventory.claim(task.id)
	detached.count = 100
	check_eq(inventory.claim(task.id).count, 2, "read models cannot mutate the ledger")

func test_saved_carried_goods_cannot_change_the_owner_to_which_cancel_returns_them() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "source")
	_stock(inventory, "target")
	inventory.seed("source", "meal", 1, 31)
	var task: Dictionary = inventory.reserve_transfer(1, "source", "target", "meal", 1, 2, 31, 41)
	inventory.pickup(task.id)
	var original: Dictionary = inventory.snapshot()
	var broken: Dictionary = original.duplicate(true)
	broken.claims[0].held[0].owner = 99
	check(not inventory.restore(broken).is_empty(), "saved return ownership must match the original source claim")
	check_eq(inventory.snapshot(), original, "bad ownership cannot replace live state")
	check_eq(inventory.cancel(task.id), "", "valid original claim still cancels")
	check_eq(inventory.quantity("source", "meal", 31), 1, "original order gets its goods back")

func test_recipe_output_space_is_reserved_until_commit_and_released_by_cancel() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "source", 4)
	_stock(inventory, "output", 2)
	inventory.seed("source", "raw", 2)
	var first: Dictionary = inventory.reserve_operation(1, "source", {"raw":1}, {"meal":2}, -1, "output")
	check_eq(first.error, "", "first operation reserves all output slots")
	var before: Dictionary = inventory.snapshot()
	check(not inventory.reserve_operation(2, "source", {"raw":1}, {"meal":1}, -1, "output").error.is_empty(), "another operation cannot over-reserve output")
	check_eq(inventory.snapshot(), before, "failed start leaves all other inputs available")
	inventory.cancel(first.id)
	var second: Dictionary = inventory.reserve_operation(2, "source", {"raw":1}, {"meal":1}, -1, "output")
	check_eq(second.error, "", "cancel releases output capacity")
	inventory.complete_operation(second.id)
	check_eq(inventory.quantity("output", "meal"), 1, "only committed operation produces")
	check_eq(inventory.audit(), [], "capacity and quantities remain consistent")

func test_integrated_machine_supply_uses_the_same_recipe_transaction_without_fake_carried_goods() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "mixer", 2, ["milk"])
	_stock(inventory, "output", 2)
	inventory.seed("mixer", "tea", 2, 7)
	var task: Dictionary = inventory.reserve_operation(1, "mixer", {"tea":2, "milk":2}, {"drink":2}, 7, "output")
	check_eq(task.error, "", "installed infinite supply can participate in the normal recipe")
	if not String(task.error).is_empty(): return
	check_eq(inventory.quantity("hand:1", "milk"), 0, "integrated supply is not an employee pickup")
	check_eq(inventory.complete_operation(task.id), "", "complete normal recipe with supplied input")
	check_eq(inventory.quantity("mixer", "tea"), 0, "finite input consumed")
	check_eq(inventory.quantity("output", "drink", 7), 2, "one recipe output")
	check_eq(inventory.audit(), [], "integrated input generation and consumption are accounted together")

func test_virtual_recipe_input_cannot_create_extra_output_capacity() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "mixer", 2, ["milk"])
	inventory.seed("mixer", "tea", 2)
	var before: Dictionary = inventory.snapshot()
	check(not inventory.reserve_operation(1, "mixer", {"tea":1, "milk":2}, {"drink":2}).error.is_empty(), "infinite input occupies no physical slot and cannot offset output growth")
	check_eq(inventory.snapshot(), before, "invalid expansion cannot reserve a partial recipe")

func test_carried_goods_cannot_be_stolen_or_consumed_by_a_second_capability() -> void:
	var inventory := _new_inventory()
	if inventory == null: return
	_stock(inventory, "source")
	_stock(inventory, "target")
	inventory.seed("source", "tea", 2)
	var task: Dictionary = inventory.reserve_transfer(1, "source", "target", "tea", 2, 2)
	inventory.pickup(task.id)
	var before: Dictionary = inventory.snapshot()
	check(not inventory.reserve_transfer(2, "hand:1", "target", "tea", 1, 2).error.is_empty(), "another actor cannot take a leased hand item")
	check(not inventory.reserve_operation(2, "hand:1", {"tea":1}, {"meal":1}, -1, "target").error.is_empty(), "another operation cannot consume an item still being carried")
	check(not inventory.seed("hand:1", "tea", 1).error.is_empty(), "seed cannot bypass pickup timing and create orphan held goods")
	check_eq(inventory.snapshot(), before, "failed competing actions have no side effects")
	check_eq(inventory.drop(task.id), "", "original carrier can finish its valid drop")
	check_eq(inventory.quantity("target", "tea"), 2, "all original material arrives once")
