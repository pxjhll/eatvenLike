extends "res://tests/test_case.gd"

const AUDIT_PATH := "res://game/rules/inventory_audit.gd"
const Inventory := preload("res://game/rules/rule_inventory.gd")
const SHOPS := [preload("res://content/shops/tea/shop.tres"), preload("res://content/shops/pancake/shop.tres"), preload("res://tests/fixtures/noodle/shop.tres")]

func _audit() -> Variant:
	if not ResourceLoader.exists(AUDIT_PATH):
		check(false, "InventoryAudit module must exist")
		return null
	return load(AUDIT_PATH)

func _station() -> Dictionary:
	return {"input": {"cup": 5, "tea": 0}, "output": {"cup": 7, "tea": 0}, "reserved_out": {}, "reserved_in": 0, "work_reserved": false, "processing": 0, "stock": 0, "capacity": 12}

func _owner() -> RefCounted:
	var inventory := Inventory.new()
	inventory.stations = {"machine": _station(), "rack": _station()}
	inventory.shelf_stock = {"cup": 5, "tea": 0}
	inventory.shelf_count = 5
	return inventory

func _worker(kind := "load", src := "supply", dst := "machine", carried := 0, item := "cup", count := 2) -> Dictionary:
	return {"deployed": true, "carry_count": carried, "job": {"kind": kind, "src": src, "dst": dst, "item": item, "count": count, "order_id": 9}}

func _row(code: String, path: String, expected: Variant, actual: Variant) -> Dictionary:
	return {"code": code, "path": path, "expected": expected, "actual": actual}

func _inspect(audit: Variant, inventory: RefCounted, workers: Array = [], belts: Array = [], orders: Array = [], mode := "handoff") -> Array:
	return audit.inspect(inventory, workers, belts, orders, mode, "supply", "counter")

func test_public_api_and_literal_bad_counter() -> void:
	var rules := ShopRules.new(SHOPS[0], 42)
	if not rules.has_method("inventory_diagnostics"):
		check(false, "ShopRules.inventory_diagnostics must exist")
		return
	rules.shelf_reserved_in = 2
	check_eq(rules.call("inventory_diagnostics"), [_row("reservation_mismatch", "shelf_reserved_in", 0, 2)], "public API uses live owner")

func test_negative_values_and_shelf_total_in_both_modes() -> void:
	var audit = _audit()
	if audit == null: return
	for mode in ["handoff", "single"]:
		# Each negative fixture changes exactly one numeric field. Equal shelf total
		# is checked separately so a fractional value must survive unchanged.
		for field in ["generated", "shelf_count", "shelf_reserved_in", "shelf_reserved_out"]:
			var owner := _owner()
			owner.set(field, -1)
			check(_inspect(audit, owner, [], [], [], mode).has(_row("negative_inventory", field, 0, -1)), mode + " negative " + field)
		for field in ["processing", "stock", "capacity", "reserved_in"]:
			var owner := _owner()
			owner.stations.machine[field] = -1
			check(_inspect(audit, owner, [], [], [], mode).has(_row("negative_inventory", "stations.machine." + field, 0, -1)), mode + " station " + field)
		for field in ["input", "output", "reserved_out"]:
			var owner := _owner()
			owner.stations.machine[field].cup = -0.25
			check(_inspect(audit, owner, [], [], [], mode).has(_row("negative_inventory", "stations.machine." + field + ".cup", 0, -0.25)), mode + " fractional " + field)
		var owner := _owner()
		owner.shelf_stock.cup = -0.25
		check(_inspect(audit, owner, [], [], [], mode).has(_row("negative_inventory", "shelf_stock.cup", 0, -0.25)), "fractional shelf stock")
		check(_inspect(audit, _owner(), [_worker("load", "supply", "machine", -1)], [], [], mode).has(_row("negative_inventory", "workers[0].carry_count", 0, -1)), "worker carried goods")
		check(_inspect(audit, _owner(), [], [{"dst": "rack", "item": "cup", "count": -1}], [], mode).has(_row("negative_inventory", "belt_items[0].count", 0, -1)), "shipment goods")
		owner = _owner()
		owner.shelf_count = 4
		check_eq(_inspect(audit, owner, [], [], [], mode), [_row("shelf_count_mismatch", "shelf_count", 5, 4)], "shelf sum")

func test_reservations_rebuild_per_item_and_detect_stale_positive_entries() -> void:
	var audit = _audit()
	if audit == null: return
	var owner := _owner()
	owner.stations.machine.reserved_in = 1
	check_eq(_inspect(audit, owner, [_worker()]), [_row("reservation_mismatch", "stations.machine.reserved_in", 2, 1)], "destination from unfinished supply job")
	owner = _owner()
	owner.shelf_reserved_in = 1
	check_eq(_inspect(audit, owner, [_worker("carry", "supply", "shelf")]), [_row("reservation_mismatch", "shelf_reserved_in", 2, 1)], "shelf destination")
	owner = _owner()
	owner.shelf_reserved_out = 1
	check_eq(_inspect(audit, owner, [_worker("serve", "shelf", "counter")], [], [{"id": 9, "reserved": true}]), [_row("reservation_mismatch", "shelf_reserved_out", 2, 1)], "shelf source")
	owner = _owner()
	owner.stations.machine.reserved_out = {"tea": 2}
	check_eq(_inspect(audit, owner, [_worker("carry", "machine", "counter")]), [
		_row("reservation_mismatch", "stations.machine.reserved_out.tea", 0, 2),
		_row("reservation_mismatch", "stations.machine.reserved_out.cup", 2, 0)], "same total wrong item is inconsistent")
	owner = _owner()
	owner.stations.machine.reserved_out = {"stale": 3}
	owner.stations.machine.reserved_in = 2
	owner.shelf_reserved_in = 1
	owner.shelf_reserved_out = 4
	check_eq(_inspect(audit, owner), [
		_row("reservation_mismatch", "shelf_reserved_out", 0, 4), _row("reservation_mismatch", "shelf_reserved_in", 0, 1),
		_row("reservation_mismatch", "stations.machine.reserved_out.stale", 0, 3), _row("reservation_mismatch", "stations.machine.reserved_in", 0, 2)], "stale positive claims")

func test_work_order_flags_and_multiple_work_claims_are_independent() -> void:
	var audit = _audit()
	if audit == null: return
	var owner := _owner()
	check_eq(_inspect(audit, owner, [_worker("pot_take", "machine", "machine")]), [_row("work_reservation_mismatch", "stations.machine.work_reserved", true, false)], "pot_take claims work without source or destination")
	owner.stations.machine.work_reserved = true
	check_eq(_inspect(audit, owner, [_worker("pot_take", "machine", "machine"), _worker("stir", "machine", "machine")]), [_row("multiple_work_claims", "stations.machine.work_reserved", 1, 2)], "duplicate work owners")
	check_eq(_inspect(audit, owner), [_row("work_reservation_mismatch", "stations.machine.work_reserved", false, true)], "stale work flag")
	owner = _owner()
	check_eq(_inspect(audit, owner, [_worker("serve", "supply", "counter", 2)], [], [{"id": 9, "reserved": false}, {"id": 10, "reserved": true}]), [
		_row("order_reservation_mismatch", "orders[0].reserved", true, false), _row("order_reservation_mismatch", "orders[1].reserved", false, true)], "serve jobs independently claim matching order")

func test_source_over_reserved_distinguishes_input_output_and_shelf_items() -> void:
	var audit = _audit()
	if audit == null: return
	for kind in ["work", "pot_start", "carry"]:
		var owner := _owner()
		owner.stations.machine.input.cup = 1 if kind != "carry" else 20
		owner.stations.machine.output.cup = 1 if kind == "carry" else 20
		owner.stations.machine.reserved_out.cup = 2
		owner.stations.machine.work_reserved = kind != "carry"
		check_eq(_inspect(audit, owner, [_worker(kind, "machine", "counter")]), [_row("source_over_reserved", "stations.machine." + ("output" if kind == "carry" else "input") + ".cup", 1, 2)], "input and output cannot cover each other " + kind)
	var owner := _owner()
	owner.stations.machine.input.cup = 2
	owner.stations.machine.output.cup = 2
	owner.stations.machine.reserved_out.cup = 4
	owner.stations.machine.work_reserved = true
	check_eq(_inspect(audit, owner, [_worker("work", "machine", "machine"), _worker("carry", "machine", "counter")]), [], "distinct pools each supply their own claims")
	owner = _owner()
	owner.shelf_stock = {"cup": 1, "tea": 20}
	owner.shelf_count = 21
	owner.shelf_reserved_out = 2
	check_eq(_inspect(audit, owner, [_worker("carry", "shelf", "counter")]), [_row("source_over_reserved", "shelf_stock.cup", 1, 2)], "other shelf items cannot cover source")

func test_in_flight_destinations_deployed_jobs_and_single_scope() -> void:
	var audit = _audit()
	if audit == null: return
	var owner := _owner()
	owner.stations.rack.reserved_in = 5
	var worker := _worker("carry", "machine", "rack", 2)
	var shipments := [{"dst": "rack", "item": "cup", "count": 3}]
	check_eq(_inspect(audit, owner, [worker], shipments), [], "picked worker and in-flight belt reserve destination only")
	owner.stations.rack.reserved_in = 2
	check_eq(_inspect(audit, owner, [worker], shipments), [_row("reservation_mismatch", "stations.rack.reserved_in", 5, 2)], "shipment destination is included")
	owner.shelf_reserved_in = 3
	check_eq(_inspect(audit, owner, [worker], [{"dst": "shelf", "item": "cup", "count": 3}]), [], "shipment can independently reserve shelf destination")
	owner.shelf_reserved_in = 0
	worker.deployed = false
	owner.stations.rack.reserved_in = 3
	check_eq(_inspect(audit, owner, [worker], shipments), [], "undeployed worker has no claims")
	owner.stations.machine.reserved_out = {"stale": 7}
	owner.stations.machine.work_reserved = true
	check_eq(_inspect(audit, owner, [worker], shipments, [{"id": 9, "reserved": true}], "single"), [], "single only checks basic inventory and shelf sum")

func test_reports_are_fresh_detached_data_and_reads_preserve_live_state() -> void:
	var audit = _audit()
	if audit == null: return
	var owner := _owner()
	owner.stations.machine.reserved_out = {"cup": 3}
	var report := _inspect(audit, owner)
	var retained_row: Dictionary = report[0]
	var expected := report.duplicate(true)
	owner.stations.machine.reserved_out.cup = 4
	var fresh := _inspect(audit, owner)
	check_eq(report, expected, "actual returned Array remains unchanged after live edit and another inspect")
	check_eq(retained_row, expected[0], "actual returned row remains unchanged")
	report[0].actual = 999
	report.append({"code": "caller"})
	check_eq(owner.stations.machine.reserved_out.cup, 4, "editing report cannot change stock")
	check_eq(fresh, [_row("reservation_mismatch", "stations.machine.reserved_out.cup", 0, 4)], "earlier fresh result is independent of caller edits")
	check_eq(_inspect(audit, owner), fresh, "new result is independent")
	var rules := ShopRules.new(SHOPS[0], 42)
	if not rules.has_method("inventory_diagnostics"):
		check(false, "ShopRules.inventory_diagnostics must exist")
		return
	_open(rules)
	for tick in 600: rules.step(0.1)
	var before := rules.to_dict()
	var events_before := rules.events.log.duplicate(true)
	var emitted: Array = []
	var listener := func(event: Dictionary) -> void: emitted.append(event)
	rules.events.on("*", listener)
	var identities := [rules.get("_inventory"), rules.stations, rules.shelf_stock, rules.workers, rules.orders, rules.belt_items, rules.rng, rules.event_rng, rules.events]
	var nested: Array = []
	for station in rules.stations.values(): nested.append([station, station.input, station.output, station.reserved_out])
	for worker in rules.workers: nested.append([worker, worker.job, worker.ticket])
	for i in 3: check_eq(rules.call("inventory_diagnostics"), [], "representative active read")
	check_eq(emitted, [], "no events, including unlogged tick events, emitted by reads")
	rules.events.off("*", listener)
	check_eq(rules.to_dict(), before, "full state and both RNGs unchanged by reads")
	check_eq(rules.events.log, events_before, "event history unchanged")
	var after := [rules.get("_inventory"), rules.stations, rules.shelf_stock, rules.workers, rules.orders, rules.belt_items, rules.rng, rules.event_rng, rules.events]
	for i in identities.size(): check(is_same(identities[i], after[i]), "live identity preserved " + str(i))
	var nested_after: Array = []
	for station in rules.stations.values(): nested_after.append([station, station.input, station.output, station.reserved_out])
	for worker in rules.workers: nested_after.append([worker, worker.job, worker.ticket])
	for i in nested.size():
		for j in nested[i].size(): check(is_same(nested[i][j], nested_after[i][j]), "nested live identity preserved %d/%d" % [i, j])

func _command(rules: ShopRules, name: String, args: Dictionary = {}) -> void:
	check_eq(rules.execute_command(name, args).code, "ok", rules.shop.id + " command " + name)
	check_eq(rules.call("inventory_diagnostics"), [], rules.shop.id + " command boundary " + name)

func _open(rules: ShopRules) -> void:
	rules.gold = 1000000.0
	for guard in 30:
		var next := rules.next_unlock()
		if next.is_empty(): break
		_command(rules, "unlock", {"id": next})
		for material in rules.boxes:
			if not rules.boxes[material] and rules.command_status("unlock_box", {"material": material}).code == "ok": _command(rules, "unlock_box", {"material": material})
	for key in rules.levels:
		for i in 3:
			if rules.command_status("upgrade", {"key": key}).code != "ok": break
			_command(rules, "upgrade", {"key": key})
	for i in 2:
		if rules.command_status("hire").code == "ok": _command(rules, "hire")
	for worker in rules.roster:
		if not worker.deployed: _command(rules, "deploy_worker", {"id": worker.id, "post": ""})
	for connection in rules.connection_rows():
		if rules.command_status("buy_connection", {"id": connection.id}).code == "ok": _command(rules, "buy_connection", {"id": connection.id})
	if rules.command_status("send_flyers").code == "ok": _command(rules, "send_flyers")

func test_three_real_shops_keep_invariants_during_work_recall_load_and_reopen() -> void:
	var audit = _audit()
	if audit == null: return
	for shop in SHOPS:
		var rules := ShopRules.new(shop, 42)
		if not rules.has_method("inventory_diagnostics"):
			check(false, "ShopRules.inventory_diagnostics must exist")
			return
		_open(rules)
		var phases := {}
		var active := 0
		var work := 0
		var processing := 0
		var belt_ticks := 0
		var shipments := 0
		var saved_jobs := 0
		var saved_claims := 0
		for tick in range(1, 5001):
			rules.step(0.1)
			var diagnostics: Array = rules.call("inventory_diagnostics")
			if not diagnostics.is_empty():
				check_eq(diagnostics, [], "%s stable tick %d" % [shop.id, tick])
				return
			for shipment in rules.belt_items:
				if shipment.progress == 0.0: shipments += 1
			if not rules.belt_items.is_empty(): belt_ticks += 1
			for station in rules.stations.values():
				if station.processing > 0: processing += 1
			for worker in rules.workers:
				if not worker.job.is_empty() or int(worker.get("order", -1)) >= 0: active += 1
				if worker.phase in ["work", "working", "action"]: work += 1
			if shop.fulfillment.handoff == "handoff" and tick < 2000 and phases.size() < 6:
				for worker in rules.workers.duplicate():
					if worker.job.is_empty(): continue
					var phase := "%s/%s" % [worker.job.kind, worker.phase]
					if phases.has(phase): continue
					phases[phase] = tick
					var post: String = worker.post
					check_eq(rules.call("inventory_diagnostics"), [], "before recall " + phase)
					_command(rules, "recall_worker", {"id": worker.id})
					_command(rules, "deploy_worker", {"id": worker.id, "post": post})
					break
			if tick == 2500:
				for worker in rules.workers:
					if not worker.job.is_empty() or int(worker.get("order", -1)) >= 0: saved_jobs += 1
				for station in rules.stations.values():
					saved_claims += int(station.reserved_in) + int(station.work_reserved)
					for count in station.reserved_out.values(): saved_claims += int(count)
				saved_claims += rules.shelf_reserved_in + rules.shelf_reserved_out
				var state := rules.to_dict()
				check_eq(rules.load_dict(state), "", "active load " + shop.id)
				check_eq(rules.to_dict(), state, "active save round trip " + shop.id)
				check_eq(rules.call("inventory_diagnostics"), [], "after active load " + shop.id)
		var sold := rules.sold
		check(sold > 0 and active > 0 and work > 0 and saved_jobs > 0, "nonvacuous work/sales/save " + shop.id)
		if shop.id == "tea": check(processing > 0 and shipments > 0 and belt_ticks > 0 and phases.size() >= 4 and saved_claims > 0, "tea processing/belts/phases/active claims")
		rules.reset(42)
		check_eq(rules.call("inventory_diagnostics"), [], "after reset " + shop.id)
		_open(rules)
		for tick in 1000:
			rules.step(0.1)
			check_eq(rules.call("inventory_diagnostics"), [], "reopen tick " + shop.id + "/" + str(tick))
		check(rules.sold > 0, "reopened sales " + shop.id)
		print("AUDIT_LIVE ", {"shop": shop.id, "sold": sold, "reopen_sold": rules.sold, "active": active, "work": work, "processing": processing, "belt_ticks": belt_ticks, "shipments": shipments, "cancel_phases": phases, "saved_jobs": saved_jobs, "saved_claims": saved_claims})
