extends "res://tests/test_case.gd"
## Frozen v0 business regression; formal v1 coverage: test_first_shops_migration.
## Literal local ledgers: recipes and employee execution stay in ShopRules.

const PATH := "res://game/rules/rule_inventory.gd"
const TEA := preload("res://tests/fixtures/legacy_shops/tea.tres")

func _owner() -> Variant:
	if not ResourceLoader.exists(PATH):
		check(false, "RuleInventory module must exist")
		return null
	return load(PATH).new()

func _station() -> Dictionary:
	return {"input": {"cup": 5}, "output": {"cup": 7}, "reserved_out": {}, "reserved_in": 0, "work_reserved": false, "processing": 0, "processing_item": "flavor", "phase": "ready", "progress": 1.0}

func _job(kind := "carry_to_rack", src := "shelf", dst := "rack") -> Dictionary:
	return {"kind": kind, "src": src, "dst": dst, "item": "cup", "count": 2, "order_id": -1}

func test_shelf_lifecycle_reserve_take_cancel_and_completed_delivery() -> void:
	var owner = _owner()
	if owner == null: return
	owner.stations = {"rack": _station()}
	owner.shelf_stock = {"cup": 5}
	owner.shelf_count = 5
	var job := _job()
	var before := job.duplicate(true)
	owner.reserve(job, "supply", "counter")
	check_eq([owner.shelf_count, owner.shelf_stock.cup, owner.shelf_reserved_out, owner.stations.rack.reserved_in], [5, 5, 2, 2], "reservation changes claims only")
	owner.take(job, "supply")
	check_eq([owner.shelf_count, owner.shelf_stock.cup, owner.shelf_reserved_out, owner.stations.rack.reserved_in], [3, 3, 0, 2], "pickup releases source claim only")
	owner.cancel(job, 2, "supply", "counter")
	check_eq([owner.shelf_count, owner.shelf_stock.cup, owner.shelf_reserved_out, owner.stations.rack.reserved_in], [5, 5, 0, 0], "carried goods return to original shelf")
	owner.reserve(job, "supply", "counter")
	owner.take(job, "supply")
	owner.deliver("rack", "cup", 2)
	check_eq([owner.shelf_count, owner.shelf_stock.cup, owner.stations.rack.output.cup, owner.stations.rack.reserved_in], [3, 3, 9, 0], "delivery deposits goods once and releases destination")
	check_eq(job, before, "job remains unchanged across transitions")

func test_cancel_before_pickup_and_empty_cancel_leave_physical_stock() -> void:
	var owner = _owner()
	if owner == null: return
	owner.stations = {"rack": _station()}
	owner.shelf_stock = {"cup": 5}
	owner.shelf_count = 5
	var job := _job()
	owner.reserve(job, "supply", "counter")
	owner.cancel(job, 0, "supply", "counter")
	owner.cancel({}, 0, "supply", "counter")
	check_eq([owner.shelf_count, owner.shelf_stock.cup, owner.shelf_reserved_out, owner.stations.rack.reserved_in], [5, 5, 0, 0], "unpicked cancellation and empty job")

func test_supply_generated_count_undo_and_station_destinations() -> void:
	var owner = _owner()
	if owner == null: return
	owner.stations = {"machine": _station()}
	var job := _job("load", "supply", "machine")
	owner.reserve(job, "supply", "counter")
	check_eq([owner.generated, owner.stations.machine.reserved_in], [0, 2], "supply reservation creates no goods")
	owner.take(job, "supply")
	check_eq(owner.generated, 2, "supply creates goods at pickup")
	owner.cancel(job, 2, "supply", "counter")
	check_eq([owner.generated, owner.stations.machine.reserved_in], [0, 0], "supply cancellation undoes generated goods")
	owner.reserve(job, "supply", "counter")
	owner.take(job, "supply")
	owner.deliver("machine", "cup", 2)
	check_eq([owner.generated, owner.stations.machine.input.cup, owner.stations.machine.reserved_in], [2, 7, 0], "station receives raw item")
	owner.shelf_stock = {"cup": 0}
	owner.shelf_reserved_in = 2
	owner.deliver("shelf", "cup", 2)
	check_eq([owner.shelf_count, owner.shelf_stock.cup, owner.shelf_reserved_in], [2, 2, 0], "owner receives already normalized shelf item")

func test_station_output_transfer_and_counter_have_separate_claims() -> void:
	var owner = _owner()
	if owner == null: return
	owner.stations = {"machine": _station()}
	var job := _job("serve", "machine", "counter")
	var before := job.duplicate(true)
	owner.reserve(job, "supply", "counter")
	check_eq(owner.stations.machine.reserved_out.cup, 2, "counter transfer only reserves source")
	owner.take(job, "supply")
	check_eq([owner.stations.machine.input.cup, owner.stations.machine.output.cup, owner.stations.machine.reserved_out.cup], [5, 5, 0], "transfer consumes output")
	owner.cancel(job, 2, "supply", "counter")
	check_eq([owner.stations.machine.input.cup, owner.stations.machine.output.cup], [5, 7], "transfer cancellation returns output")
	check_eq(job, before, "operation does not retain or mutate job data")

func test_operations_claim_work_and_only_input_operations_reserve_goods() -> void:
	var owner = _owner()
	if owner == null: return
	for kind in ["work", "pot_start", "pot_take", "stir"]:
		owner.stations = {"machine": _station()}
		var job := _job(kind, "machine", "machine")
		var before := job.duplicate(true)
		check(owner.is_operation(job), kind + " recognized")
		owner.reserve(job, "supply", "counter")
		check_eq([owner.stations.machine.work_reserved, owner.stations.machine.reserved_in], [true, 0], kind + " claims work without destination")
		if kind in ["work", "pot_start"]:
			check_eq(owner.stations.machine.reserved_out.cup, 2, kind + " reserves input")
			owner.cancel(job, 0, "supply", "counter")
			check_eq([owner.stations.machine.input.cup, owner.stations.machine.reserved_out.cup, owner.stations.machine.work_reserved], [5, 0, false], kind + " unpicked cancel leaves input and releases both claims")
			owner.reserve(job, "supply", "counter")
			owner.take(job, "supply")
			check_eq([owner.stations.machine.input.cup, owner.stations.machine.output.cup, owner.stations.machine.reserved_out.cup], [3, 7, 0], kind + " consumes input only")
			owner.cancel(job, 2, "supply", "counter", true)
			check_eq([owner.stations.machine.input.cup, owner.stations.machine.work_reserved, owner.stations.machine.processing_item], [5, false, ""], kind + " rolls back input and optional topping flavor")
		else:
			check_eq(owner.stations.machine.reserved_out, {}, kind + " claims no goods")
			owner.cancel(job, 0, "supply", "counter")
			check_eq([owner.stations.machine.input.cup, owner.stations.machine.output.cup, owner.stations.machine.work_reserved, owner.stations.machine.processing_item], [5, 7, false, "flavor"], kind + " releases work without changing goods or flavor")
		check_eq(job, before, kind + " job remains read only")
	check(not owner.is_operation(_job()), "transport is not operation")

func test_stock_and_refresh_preserve_processing_and_active_work() -> void:
	var owner = _owner()
	if owner == null: return
	var station := _station()
	station.processing = 3
	station.phase = "cook"
	station.progress = 0.4
	check_eq(owner.stock(station), 15, "stock includes input output and processing only")
	owner.refresh_after_pickup(station)
	check_eq([station.phase, station.progress], ["cook", 0.4], "processing phase is preserved")
	station.processing = 0
	station.work_reserved = true
	station.phase = "working"
	owner.refresh_after_pickup(station)
	check_eq([station.phase, station.progress], ["working", 0.4], "active manual work is preserved")
	station.work_reserved = false
	owner.refresh_after_pickup(station)
	check_eq([station.phase, station.progress], ["ready", 1.0], "remaining output is ready")
	station.output.cup = 0
	owner.refresh_after_pickup(station)
	check_eq([station.phase, station.progress], ["idle", 0.0], "input alone is idle")

func test_rules_fields_forward_assignment_nested_mutations_and_independent_owners() -> void:
	var owner = _owner()
	if owner == null: return
	var rules := ShopRules.new(TEA, 42)
	var second := ShopRules.new(TEA, 42)
	var backing: Variant = rules.get("_inventory")
	check(backing != null, "Rules has private owner")
	if backing == null: return
	check(backing != second.get("_inventory"), "Rules owners are independent")
	rules.set("stations", rules.stations.duplicate(true))
	rules.set("shelf_stock", {"lemonade": 5})
	rules.set("shelf_count", 5)
	rules.set("shelf_reserved_in", 2)
	rules.set("shelf_reserved_out", 1)
	rules.set("generated", 8)
	check_eq([backing.shelf_stock.lemonade, backing.shelf_count, backing.shelf_reserved_in, backing.shelf_reserved_out, backing.generated], [5, 5, 2, 1, 8], "set reaches six-field owner")
	rules.stations.rack.output.lemonade = 3
	check_eq(backing.stations.rack.output.lemonade, 3, "nested station mutation reaches owner")
	backing.stations.rack.output.lemonade = 4
	check_eq(rules.get("stations").rack.output.lemonade, 4, "station getter reads reassigned owner map")
	backing.shelf_stock.lemonade = 4
	backing.shelf_count = 4
	check_eq([rules.get("shelf_stock").lemonade, rules.get("shelf_count")], [4, 4], "get reads current owner")
	check_eq([second.shelf_count, second.stations.rack.output.lemonade], [0, 0], "another Rules is unchanged")

func test_restore_and_reset_bind_current_maps_for_actual_transfer_facades() -> void:
	var owner = _owner()
	if owner == null: return
	var rules := ShopRules.new(TEA, 42)
	var stale_stations := rules.stations
	var stale_shelf := rules.shelf_stock
	var saved := rules.to_dict()
	saved.shelf_count = 5
	saved.shelf_stock.lemonade = 5
	saved.shelf_reserved_out = 2
	saved.stations.rack.reserved_in = 2
	check_eq(rules.load_dict(saved), "", "candidate restore succeeds")
	check_eq(rules.to_dict(), saved, "all serialized keys and values stay compatible")
	var job := {"kind": "carry_to_rack", "src": "shelf", "dst": "rack", "item": "lemonade", "count": 2}
	rules._take(job)
	rules._deliver("rack", "lemonade", 2)
	check_eq([rules.shelf_count, rules.shelf_stock.lemonade, rules.stations.rack.output.lemonade, rules.stations.rack.reserved_in], [3, 3, 2, 0], "facades mutate adopted candidate maps")
	check_eq([stale_shelf.lemonade, stale_stations.rack.output.lemonade], [0, 0], "preload maps are not cached")
	var loaded_stations := rules.stations
	rules.reset(42)
	rules.shelf_stock.lemonade = 5
	rules.shelf_count = 5
	rules.shelf_reserved_out = 2
	rules.stations.rack.reserved_in = 2
	rules._take(job)
	rules._deliver("rack", "lemonade", 2)
	check_eq([rules.shelf_count, rules.stations.rack.output.lemonade, loaded_stations.rack.output.lemonade], [3, 2, 2], "reset transfer uses rebuilt maps")
	check_eq(rules.get("_inventory").generated, 0, "reset clears owner scalar")
