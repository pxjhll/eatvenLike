extends "res://tests/test_case.gd"

const TEA := preload("res://content/shops/tea/shop.tres")
const PANCAKE := preload("res://content/shops/pancake/shop.tres")
const STIRFRY := preload("res://content/shops/stirfry/shop.tres")

func test_order_unlock_refill_fifth_slot_swap_replace_and_restore() -> void:
	var rules := ShopRules.new(TEA, 12)
	var lucky := rules.lucky
	check(not lucky.draw(rules), "closed shop cannot draw")
	rules.unlock("lemonade")
	for i in 80:
		rules.run(0.5)
		if rules.sold > 0: break
	check_eq(lucky.charges, 1, "first real sale awards one draw")
	lucky.sync(lucky.next_at - 0.1, rules.sold)
	check_eq(lucky.charges, 1, "early refill blocked")
	lucky.sync(lucky.next_at, rules.sold)
	check_eq(lucky.charges, 2, "refill at three minutes")
	lucky.sync(rules.clock + 1000, rules.sold)
	check_eq(lucky.charges, 2, "bank capped at two")
	lucky.progress = 4
	lucky.held = ["walk"]
	check(lucky.draw(rules), "fifth reveal succeeds")
	check_eq(lucky.slots(), 2, "new slot immediately available")
	lucky.pending = "guest"
	check(lucky.act(rules, "save"), "fifth ticket fits")
	check(lucky.act(rules, "swap"), "tap rear ticket")
	check_eq(lucky.held, ["walk", "guest"], "front changes")
	lucky.pending = "tips"
	check(not lucky.act(rules, "save"), "no overflow or implicit discard")
	check(lucky.act(rules, "replace", 1), "consume selected guest ticket")
	check_eq(lucky.guests, 1, "selected old ticket applied exactly once")
	check_eq(lucky.held, ["walk", "tips"], "new ticket occupies former slot")
	var saved := rules.to_dict()
	var loaded := ShopRules.new(TEA, 17)
	check_eq(loaded.load_dict(saved), "", "active state reloads")
	check_eq(loaded.lucky.snapshot(), lucky.snapshot(), "complete ticket state roundtrips")
	saved.outer.erase("fortunes")
	check_eq(loaded.load_dict(saved), "", "pre-feature save still loads")
	check_eq(loaded.lucky.charges, 1, "existing trading shop gets first charge")

func test_pool_pity_cash_tips_and_effect_stacking() -> void:
	var rules := ShopRules.new(TEA, 23)
	rules.unlock("lemonade")
	var lucky := rules.lucky
	lucky.sync(0.0, 1)
	lucky.history = [5, 10, 15, 20, 25]
	var seen := {}
	var previous_fun := false
	for i in 500:
		lucky.charges = 1
		var balance := rules.gold
		check(lucky.draw(rules), "available draw succeeds")
		var id: String = lucky.pending
		seen[id] = true
		var fun: bool = id in lucky.FUN
		check(not (previous_fun and fun), "guaranteed business draw after a cosmetic")
		previous_fun = fun
		check(id != "machine", "manual opening station excluded")
		if id == "cash":
			check_eq(rules.gold - balance, 30.0, "cash uses five recent base receipts")
			var state: Dictionary = lucky.snapshot()
			check(lucky.restore(state), "pending cash feedback reloads")
			check_eq(rules.gold - balance, 30.0, "reload never pays again")
		lucky.act(rules, "done" if fun or id == "cash" else "use")
	for id in ["cash","walk","tips","guest","stamp","flower","postcard"]: check(seen.has(id), "eligible ticket " + id)
	lucky.tips = 3
	for i in 4:
		var payout: Dictionary = rules._sales.credit_order(10.0, 1)
		check_eq(payout.income, 13 if i < 3 else 11, "three bonus receipts")
	lucky.walk_until = 0.0
	var base := rules.walk_speed(rules.workers[0])
	lucky.pending = "walk"
	check(lucky.act(rules, "use"), "use speed ticket now")
	check(is_equal_approx(rules.walk_speed(rules.workers[0]), base * 1.4), "real movement multiplier")
	lucky.held = ["walk"]
	check(lucky.act(rules, "held"), "use second speed ticket")
	check_eq(lucky.walk_until, rules.clock + 40.0, "duration extends")
	rules.clock += 40.0
	check(is_equal_approx(rules.walk_speed(rules.workers[0]), base), "restores normal speed")

func test_regular_takeaway_delivers_without_seat_in_all_three_shops() -> void:
	for entry in [[PANCAKE,"soy_milk"], [TEA,"lemonade"], [STIRFRY,"plum_dispenser"]]:
		var rules := ShopRules.new(entry[0], 42)
		check_eq(rules.unlock(entry[1]), "", "open " + entry[1])
		rules.lucky.pending = "guest"
		rules.lucky.act(rules, "use")
		var guest_id := -1
		var checked := false
		for i in 2400:
			rules.run(0.1)
			if not rules.runtime_error.is_empty():
				check(false, "regular guest simulation: " + rules.runtime_error)
				break
			var service = rules.runtime.service
			if guest_id < 0:
				for g in service.orders.active_snapshot().guests:
					if g.get("regular", false): guest_id = g.id
			if guest_id < 0: continue
			var guest: Dictionary = service.orders.guest(guest_id)
			if guest.order < 1: continue
			if not checked:
				check_eq(guest.seat, "", "regular customer needs no seat")
				check_eq(guest.request.size(), 1, "one feasible dish")
				check_eq(guest.request[0].qty, 1, "one item only")
				var copy := ShopRules.new(entry[0], 42)
				check_eq(copy.load_dict(rules.to_dict()), "", "save mid-order in " + entry[1])
				checked = true
			if guest.state == "gone":
				check(service.orders.order(guest.order).paid, "ordinary checkout")
				break
		check(checked and rules.runtime.service.orders.guest(guest_id).get("state") == "gone", "guest completes service in " + entry[1])

func test_machine_ticket_speeds_only_automatic_phase_of_existing_batch() -> void:
	var stock := preload("res://game/rules/template/inventory.gd").new()
	var machines := preload("res://game/rules/template/machines.gd").new(stock)
	stock.configure("in", 8)
	stock.configure("out", 8)
	stock.seed("in", "leaf", 1)
	machines.configure("pot", "in", "out", {"load_seconds":2.0})
	var batch := machines.start("pot", {"leaf":1}, {"tea":1}, 12.0)
	machines.engage(batch.id, 1)
	machines.advance(1.0, false, 1.5)
	check_eq(machines.run(batch.id).stage_left, 1.0, "employee loading at normal speed")
	machines.advance(1.0)
	machines.advance(2.0)
	machines.advance(2.0, false, 1.5)
	check_eq(machines.run(batch.id).remaining, 7.0, "running batch immediately benefits")
	machines.advance(7.0)
	check_eq(stock.quantity("out", "tea"), 1, "normal batch yield")

func test_disk_reload_and_cross_shop_unlock() -> void:
	var fixture := preload("res://tests/shop_test_session.gd")
	var prefix := "user://fortune-transition-%d" % Time.get_ticks_usec()
	var session := fixture.make(PANCAKE, prefix)
	check_eq(session.start(), OK, "first session opened")
	session.rules.unlock("soy_milk")
	for i in 100:
		session.rules.run(0.5)
		if session.rules.sold > 0: break
	session.rules.lucky.progress = 4
	check_eq(session.fortune_action("draw"), OK, "fifth draw commits on disk")
	var state: Dictionary = session.rules.lucky.snapshot()
	var again := fixture.make(PANCAKE, prefix)
	check_eq(again.start(), OK, "reopen after reveal")
	check_eq(again.rules.lucky.snapshot(), state, "same pending card, timers and rng")
	check_eq(again.jump(TEA.id), OK, "transition with pending ticket")
	var next := fixture.make(TEA, prefix+"-tea", null, null, again.profile)
	check_eq(next.start(), OK, "start second store")
	check_eq(next.rules.lucky.slots(), 2, "permanent slot inherited")
	check_eq(next.rules.lucky.held, [], "personal store pocket starts empty")
	for suffix in ["-profile.json","-shop.json","-tea-shop.json"]:
		for name in DirAccess.get_files_at("user://"):
			if name.begins_with(prefix.get_file()+suffix): DirAccess.remove_absolute("user://".path_join(name))
