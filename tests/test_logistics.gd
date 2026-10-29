extends "res://tests/test_case.gd"
## PXJ-23: real slicing recipes, generic parallel slots, and bounded backpressure.

const Cases := preload("res://tests/fixtures/production_cases.gd")


# Catches a toast alias bypassing slicing, lost material, or duplicate delivery.
func test_real_slicing_chain_conserves_material() -> void:
	var sim := make_sim(_chain())
	sim.run_seconds(60.0)
	check(Cases.produced(sim, "bread") > 0, "the oven actually baked bread")
	check(Cases.produced(sim, "sliced_bread") > 0, "the slicing recipe actually ran")
	check(sim.production.shelf.get("sliced_bread", 0) > 0, "sliced bread reached the shelf")
	check_eq(sim.production.shelf.get("bread", 0), 0, "unsliced bread cannot bypass the slicer")
	var consumed_bread: int = sim.diagnostics.item_flow.get("bread", {}).get("consumed", 0)
	var processing_loaves := 0
	for id in ["cutter_alpha", "cutter_beta"]:
		if Cases.state(sim, id).phase == StationState.Phase.PROCESSING:
			processing_loaves += 1
	check_eq(Cases.produced(sim, "sliced_bread"), (consumed_bread - processing_loaves) * 2, "each completed loaf yields two slices; in-flight input has no output yet")
	_check_conservation(sim)


# Catches parallel activation being tied to oven IDs or not adding actual capacity.
func test_parallel_slicers_raise_output_without_dispatch_changes() -> void:
	var cfg := _chain()
	var single := make_sim(cfg)
	var parallel := make_sim(cfg)
	parallel.submit(ActivateParallelCommand.new("cutter_beta"))
	single.run_seconds(60.0)
	parallel.run_seconds(60.0)
	check_eq(Cases.state(single, "cutter_beta").status, StationState.Status.EMPTY_PARALLEL, "control keeps the second slot empty")
	for id in ["cutter_alpha", "cutter_beta"]:
		check(parallel.diagnostics.produced_by_slot.get(id, 0) > 0, "both arbitrary slicer IDs produce: " + id)
	check(Cases.produced(parallel, "sliced_bread") > Cases.produced(single, "sliced_bread"), "a second slicer increases actual sliced output")
	check_eq(single.economy.gold - parallel.economy.gold, 10, "generic parallel activation charges once")
	_check_conservation(parallel)
	print("    PXJ-23 fixture: %.0f Hz, %d stations, %d belt segments, %d ticks; sliced output single=%d parallel=%d" % [
		1.0 / parallel.step_seconds, parallel.production.stations.size(), parallel.production.segments.size(), parallel.tick,
		Cases.produced(single, "sliced_bread"), Cases.produced(parallel, "sliced_bread")])


# Catches accepting into full buffers, dropping blocked items, or never recovering.
func test_full_shelf_backpressures_upstream_and_resumes_after_consumption() -> void:
	var sim := make_sim(_chain(true))
	sim.run_seconds(100.0)
	check_eq(sim.production.shelf.get("sliced_bread", 0), 2, "the bounded shelf is full")
	# One slice can enter the last belt gap before saturation; the remaining slice
	# occupies half the 2-slot output buffer, so the next two-slice batch cannot start.
	check_eq(Cases.state(sim, "cutter_alpha").outputs.get("sliced_bread", 0), 1, "a partial batch backs up and prevents the next two-slice batch")
	check_eq(Cases.state(sim, "heater_custom").outputs.get("bread", 0), 1, "bread backs up at the oven")
	check_eq(Cases.state(sim, "prep_custom").outputs.get("dough", 0), 1, "backpressure reaches the prep station")
	check_eq(Cases.state(sim, "supply_custom").outputs.get("flour", 0), 1, "backpressure reaches the supplier")
	var before := JSON.stringify(sim.production.to_dict(), "", false)
	var produced_before := Cases.produced(sim, "sliced_bread")
	var flour_before := Cases.produced(sim, "flour")
	sim.run_seconds(5.0)
	check_eq(JSON.stringify(sim.production.to_dict(), "", false), before, "the saturated chain retains all items without moving or duplicating them")
	_check_conservation(sim)
	check(sim.production.reserve(1000000, "sliced_bread", 2), "existing stock can be reserved for consumption")
	var consumed := sim.production.take_reserved(1000000)
	# Production emits a stock transaction; its caller feeds Diagnostics, as GameSim does for sales.
	sim.diagnostics.record(0.0, consumed)
	check_eq(sim.production.free_stock("sliced_bread"), 0, "consumption empties the shelf")
	sim.run_seconds(30.0)
	check_eq(sim.production.shelf.get("sliced_bread", 0), 2, "the shelf refills after consumption")
	check(Cases.produced(sim, "sliced_bread") > produced_before, "unblocking downstream resumes slicing")
	check(Cases.produced(sim, "flour") > flour_before, "freed capacity propagates all the way back to the supplier")
	_check_conservation(sim)


# Catches treating empty inventory or overlapping orders as extra available stock.
func test_empty_and_reserved_inventory_do_not_create_stock() -> void:
	var sim := make_sim(_chain())
	check(not sim.production.reserve(41, "sliced_bread", 1), "empty stock refuses reservation")
	check(sim.production.reservations.is_empty(), "failed reservations leave no ownership record")
	sim.run_seconds(20.0)
	var stock := sim.production.free_stock("sliced_bread")
	check(stock > 0, "the real chain supplies inventory")
	check(sim.production.reserve(42, "sliced_bread", stock), "all available stock can be reserved once")
	check_eq(sim.production.free_stock("sliced_bread"), 0, "reserved stock is unavailable to another order")
	check(not sim.production.reserve(43, "sliced_bread", 1), "another order cannot reserve the same stock")
	sim.production.release(42)
	check_eq(sim.production.free_stock("sliced_bread"), stock, "cancelling restores availability, not total quantity")
	_check_conservation(sim)


func _chain(bounded: bool = false) -> ShopConfig:
	var supply := Cases.slot("supply_custom", StationDef.Mode.SUPPLY, {}, {"flour": 1})
	supply.station.supply_interval = 0.2
	var prep := Cases.slot("prep_custom", StationDef.Mode.AUTO, {"flour": 1}, {"dough": 1}, 0.2)
	var oven := Cases.slot("heater_custom", StationDef.Mode.AUTO, {"dough": 1}, {"bread": 1}, 0.2)
	var alpha := Cases.slot("cutter_alpha", StationDef.Mode.AUTO, {"bread": 1}, {"sliced_bread": 2}, 2.0)
	alpha.station.parallel_cost = 10
	var beta := SlotDef.new()
	beta.id = "cutter_beta"
	beta.station = alpha.station
	beta.parallel_of = "cutter_alpha"
	var cfg := Cases.config([supply, prep, oven, alpha, beta], [
		Cases.connection("supply_prep", "supply_custom", "prep_custom"),
		Cases.connection("prep_heater", "prep_custom", "heater_custom"),
		Cases.connection("heater_alpha", "heater_custom", "cutter_alpha"),
		Cases.connection("heater_beta", "heater_custom", "cutter_beta"),
		Cases.connection("alpha_shelf", "cutter_alpha", "shelf"),
		Cases.connection("beta_shelf", "cutter_beta", "shelf"),
	])
	cfg.shelf_capacity = 2 if bounded else 10000
	if bounded:
		for s in [supply, prep, oven, alpha]:
			s.station.output_capacity = 2 if s == alpha else 1
			for item in s.station.input_capacity:
				s.station.input_capacity[item] = 1
	return cfg


func _check_conservation(sim: GameSim) -> void:
	var on_field := sim.production.count_items()
	for item in ["flour", "dough", "bread", "sliced_bread"]:
		check_eq(on_field.get(item, 0), sim.diagnostics.expected_on_field(item), "conservation through actual slicing: " + item)
