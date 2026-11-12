extends "res://tests/test_case.gd"
const Inventory := preload("res://game/rules/template/inventory.gd")

func _stock() -> RefCounted:
	var stock := Inventory.new()
	check(stock.has_method("reserve_bundle"), "multi-item transport must be a public inventory capability")
	if not stock.has_method("reserve_bundle"): return null
	for place in ["main", "side", "guest:1"]: stock.configure(place, 4)
	stock.seed("main", "meal", 1, 11)
	stock.seed("side", "soup", 1, 12)
	return stock

func _entries() -> Array:
	return [{"from":"main","to":"guest:1","item":"meal","count":1,"owner":11},
		{"from":"side","to":"guest:1","item":"soup","count":1,"owner":12}]

func test_whole_order_reservation_is_atomic_when_a_side_item_or_capacity_is_missing() -> void:
	var stock := _stock()
	if stock == null: return
	var entries := _entries()
	entries[1].item = "missing"
	var before: Dictionary = stock.snapshot()
	check(not stock.reserve_bundle("staff:1", entries, 2).error.is_empty(), "main cannot be reserved without its side item")
	check_eq(stock.snapshot(), before, "failed group leaves no main-item reservation")
	check(not stock.reserve_bundle("staff:1", _entries(), 1).error.is_empty(), "all items must fit the real carrier capacity")
	check_eq(stock.snapshot(), before, "capacity failure cannot allocate half an order")

func test_staff_collects_two_sources_then_delivers_every_item_in_one_commit() -> void:
	var stock := _stock()
	if stock == null: return
	var request: Dictionary = stock.reserve_bundle("staff:1", _entries(), 2)
	check_eq(request.error, "", "reserve main and side together")
	var group: Dictionary = stock.bundle(request.id)
	check_eq(stock.quantity("hand:1"), 0, "reservation creates no held icons")
	check_eq(stock.pickup_bundle_part(group.id, group.claims[0]), "", "collect main at its real port")
	check_eq(stock.quantity("hand:1", "meal", 11), 1, "main is carried")
	check_eq(stock.quantity("side", "soup", 12, true), 0, "side stays reserved while carrier approaches")
	check(not stock.drop_bundle(group.id).is_empty(), "cannot deliver a half-collected bundle")
	check_eq(stock.quantity("guest:1"), 0, "partial bundle never reaches customer early")
	stock.pickup_bundle_part(group.id, group.claims[1])
	check_eq(stock.quantity("hand:1"), 2, "both actual items carried")
	check_eq(stock.drop_bundle(group.id), "", "drop both items atomically")
	check_eq(stock.drop_bundle(group.id), "", "duplicate group drop harmless")
	check_eq(stock.quantity("guest:1", "meal", 11), 1, "main keeps ownership")
	check_eq(stock.quantity("guest:1", "soup", 12), 1, "side keeps ownership")
	check_eq(stock.audit(), [], "group and child inventory claims agree")

func test_customer_uses_the_same_bundle_and_cannot_mutate_a_single_child_outside_it() -> void:
	var stock := _stock()
	if stock == null: return
	var request: Dictionary = stock.reserve_bundle("customer:1", _entries(), 2)
	var group: Dictionary = stock.bundle(request.id)
	check(not stock.pickup(group.claims[0]).is_empty(), "group children cannot bypass the group lifecycle")
	check_eq(stock.pickup_bundle(group.id), "", "customer collects the complete group through shared pickup")
	check_eq(stock.quantity("hand@customer:1"), 2, "customer carries real main and side")
	check(not stock.drop(group.claims[0]).is_empty(), "single-child drop cannot split whole-order delivery")
	check(not stock.cancel(group.claims[0]).is_empty(), "single-child cancel cannot release a side item alone")
	check_eq(stock.drop_bundle(group.id), "", "same public group drop")
	check_eq(stock.audit(), [], "customer uses one authoritative ledger")

func test_cancel_after_first_pickup_returns_every_ownership_and_releases_every_reservation() -> void:
	var stock := _stock()
	if stock == null: return
	var request: Dictionary = stock.reserve_bundle("staff:1", _entries(), 2)
	var group: Dictionary = stock.bundle(request.id)
	stock.pickup_bundle_part(group.id, group.claims[0])
	check_eq(stock.cancel_bundle(group.id), "", "cancel partially collected group")
	check_eq(stock.cancel_bundle(group.id), "", "group compensation only once")
	check_eq(stock.quantity("main", "meal", 11, true), 1, "main physically returned")
	check_eq(stock.quantity("side", "soup", 12, true), 1, "side reservation released")
	check_eq(stock.quantity("hand:1"), 0, "hand cleared")
	check_eq(stock.audit(), [], "partial group cancellation conserves everything")

func test_saved_bundle_resumes_its_remaining_pickup_without_duplicating_main() -> void:
	var stock := _stock()
	if stock == null: return
	var request: Dictionary = stock.reserve_bundle("staff:1", _entries(), 2)
	var group: Dictionary = stock.bundle(request.id)
	stock.pickup_bundle_part(group.id, group.claims[0])
	var reopened := Inventory.new()
	check_eq(reopened.restore(stock.snapshot()), "", "restore parent and child claims together")
	check_eq(reopened.pickup_bundle(group.id), "", "complete remaining pickup")
	reopened.drop_bundle(group.id)
	check_eq(reopened.quantity("guest:1"), 2, "one main and one side delivered after restore")
	check_eq(reopened.audit(), [], "restored group remains consistent")

func test_corrupt_bundle_membership_is_rejected_without_adopting_any_state() -> void:
	var stock := _stock()
	if stock == null: return
	var request: Dictionary = stock.reserve_bundle("staff:1", _entries(), 2)
	var before: Dictionary = stock.snapshot()
	var broken: Dictionary = before.duplicate(true)
	broken.bundles[0].claims[1] = broken.bundles[0].claims[0]
	check(not stock.restore(broken).is_empty(), "same claim cannot fill two legs of a bundle")
	check_eq(stock.snapshot(), before, "invalid group references leave live ledger intact")
	check_eq(stock.bundle(request.id).claims.size(), 2, "original bundle remains usable")
