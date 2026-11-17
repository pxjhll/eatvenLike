extends "res://tests/test_case.gd"
## Real seed-84 active-player checkpoint at 1340s, main b60188c.
## Ten seconds later a released order-follow scope used to leave the customer's
## pickup target stale for one tick, making the formal save validator reject it.
const SHOP: SpecShop = preload("res://content/shops/tea/shop.tres")
const FIXTURE := "res://tests/fixtures/save_boundaries/tea_before_uncall.json"
var INPUT := "user://dispatch_boundary_input_%d.json" % OS.get_process_id()
var OUTPUT := "user://dispatch_boundary_output_%d.json" % OS.get_process_id()

func test_formal_save_and_resume_at_order_follower_release_boundary() -> void:
	var file := FileAccess.open(INPUT, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURE))
	file.close()
	var store := ShopSave.new(SHOP, INPUT)
	var rules := store.load_game()
	check_eq(store.load_error, OK, "captured valid checkpoint loads")
	check(is_equal_approx(rules.clock, 1340.0), "real checkpoint time")
	if store.load_error != OK or not is_equal_approx(rules.clock,1340.0): return
	var output := ShopSave.new(SHOP, OUTPUT)
	for tick in 101:
		rules.step(0.1)
		check_eq(rules.runtime_error, "", "valid transition")
		if tick < 98: continue
		check_eq(output.save_game(rules), OK, "save before/during/after follower release: " + output.last_error)
		var restored := output.load_game()
		check_eq(output.load_error, OK, "boundary disk save restores")
		check_eq(restored.to_dict(), rules.to_dict(), "boundary state fully retained")
		# Both continuations must preserve movement, dispatch, inventory and RNG.
		var control := ShopRules.new(SHOP)
		check_eq(control.load_dict(rules.to_dict()), "", "independent control restores")
		for future_tick in 5:
			control.step(0.1)
			restored.step(0.1)
		check_eq(restored.to_dict(), control.to_dict(), "same continuation after load")

func cleanup() -> void:
	for path in [INPUT, OUTPUT]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
