extends "res://tests/test_case.gd"

const MODULE := "res://game/rules/rule_sales.gd"
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")

# This fixture observes query boundaries without installing callbacks in the owner.
class QuoteRules extends ShopRules:
	var observations := []
	func seat_seconds() -> float:
		observations.append(["seat", sold, diners.size(), gold])
		return 7.0
	func dish_price(_dish: String) -> float:
		observations.append(["price", sold, sold_by_dish.lemonade, diners.size(), gold])
		return 1.25
	func order_price_single(c: Dictionary) -> int:
		observations.append(["quote", queue.duplicate(), c.state, gold, revenue, sold])
		return 17

func _owner() -> Variant:
	if not ResourceLoader.exists(MODULE):
		check(false, "Sales module must exist")
		return null
	return load(MODULE).new()

func test_handoff_literal_count_credit_and_exact_payload() -> void:
	var sales = _owner()
	if sales == null: return
	sales.sold_by_dish = {"tea": 0}
	sales.count_handoff("tea", 3)
	check_eq([sales.sold, sales.sold_by_dish, sales.gold, sales.revenue], [3, {"tea": 3}, 0.0, 0.0], "count precedes credit")
	var job := {"item": "tea", "count": 3, "order_id": 12, "extra": {"keep": true}}
	var before := job.duplicate(true)
	check_eq(sales.credit_handoff(job, 1.25), {"dish": "tea", "count": 3, "income": 3}, "literal handoff payload")
	check_eq([sales.gold, sales.revenue, sales.sold, sales.sale_carry], [3.0, 3.0, 3, 0.75], "literal handoff state")
	check_eq(job, before, "credit does not alter job")

func test_handoff_epsilon_clamp_and_cumulative_fraction() -> void:
	var sales = _owner()
	if sales == null: return
	check_eq(sales.credit_handoff({"item": "tea", "count": 1}, 0.99995), {"dish": "tea", "count": 1, "income": 1}, "epsilon rounds just below integer")
	check_eq(sales.sale_carry, 0.0, "epsilon overpayment clamps negative remainder")
	sales.gold = 10.0
	sales.revenue = 2.0
	var incomes := []
	for unused in 4:
		incomes.append(sales.credit_handoff({"item": "tea", "count": 1}, 0.25).income)
	check_eq(incomes, [0, 0, 0, 1], "four quarters accumulate")
	check_eq([sales.gold, sales.revenue, sales.sale_carry, sales.sold], [11.0, 3.0, 0.0, 0], "credit alone does not count sold")
	check_eq(sales.credit_handoff({"item": "tea", "count": 1}, 0.9998).income, 0, "outside epsilon remains fraction")
	check(is_equal_approx(sales.sale_carry, 0.9998), "outside epsilon retained")

func test_two_owners_have_independent_money_and_dictionaries() -> void:
	var first = _owner()
	if first == null: return
	var second = _owner()
	check_eq([second.gold, second.revenue, second.sold, second.sale_carry, second.sold_by_dish], [0.0, 0.0, 0, 0.0, {}], "fresh owner defaults")
	first.sold_by_dish.tea = 0
	first.count_handoff("tea", 2)
	first.credit_handoff({"item": "tea", "count": 2}, 1.25)
	check_eq([second.gold, second.revenue, second.sold, second.sale_carry, second.sold_by_dish], [0.0, 0.0, 0, 0.0, {}], "owners independent")

func test_single_pay_modes_addon_and_exact_payload() -> void:
	for pay_on_take in [true, false]:
		var sales = _owner()
		if sales == null: return
		sales.gold = 10.0
		sales.revenue = 4.0
		sales.sold_by_dish = {"plain": 2.9, "soy": 1.9}
		var c := {"id": 9, "kind": "plain", "addon": true, "state": "queue", "paid": 0, "wait": 6.0}
		sales.accept_single(c, 17, pay_on_take)
		check_eq(c, {"id": 9, "kind": "plain", "addon": true, "state": "paid", "paid": 17, "wait": 6.0}, "accept keeps unrelated customer values")
		check_eq([sales.gold, sales.revenue, sales.sold], [27.0 if pay_on_take else 10.0, 21.0 if pay_on_take else 4.0, 0], "pay policy at accept")
		check_eq(sales.complete_single(c, "soy", pay_on_take), {"dish": "plain", "income": 17}, "single payload has no count or order")
		check_eq([sales.gold, sales.revenue, sales.sold, sales.sold_by_dish, sales.sale_carry, c.state], [27.0, 21.0, 2, {"plain": 3, "soy": 2}, 0.0, "leaving"], "exactly one credit with integer dish counts")

func test_single_addon_dedup_and_no_addon() -> void:
	for row in [["soy", true], ["plain", false]]:
		var sales = _owner()
		if sales == null: return
		sales.sold_by_dish = {"plain": 0, "soy": 0}
		var c := {"kind": row[0], "addon": row[1], "paid": 6, "state": "paid"}
		check_eq(sales.complete_single(c, "soy", false), {"dish": row[0], "income": 6}, "payload remains single")
		check_eq([sales.sold, sales.sold_by_dish[row[0]], sales.gold, sales.revenue], [1, 1, 6.0, 6.0], "standalone addon or absent addon counts one dish")

func test_rules_forward_assignment_reset_candidate_load_and_rejection() -> void:
	if _owner() == null: return
	var rules := ShopRules.new(TEA, 42)
	var owner: RefCounted = rules._sales
	var replacement := rules.sold_by_dish.duplicate()
	replacement.lemonade = 4
	rules.sold_by_dish = replacement
	rules.gold = 91.0
	rules.revenue = 11.0
	rules.sold = 4
	rules._sale_carry = 0.25
	check(is_same(rules.sold_by_dish, replacement) and is_same(owner.sold_by_dish, replacement), "dictionary replacement forwarded without cached alias")
	check_eq([owner.gold, owner.revenue, owner.sold, owner.sale_carry], [91.0, 11.0, 4, 0.25], "all scalar setters forward")
	owner.gold = 92.0
	owner.sale_carry = 0.5
	check_eq([rules.gold, rules._sale_carry], [92.0, 0.5], "getters read current owner")
	var saved := rules.to_dict()
	check(not saved.has("_sales") and saved.has("_sale_carry"), "save keys unchanged")
	rules.reset(42)
	check(is_same(rules._sales, owner), "reset uses existing owner")
	check(not is_same(rules.sold_by_dish, replacement), "reset replaces dish dictionary")
	check_eq([rules.gold, rules.revenue, rules.sold, rules._sale_carry, rules.sold_by_dish.lemonade], [float(TEA.start_gold), 0.0, 0, 0.0, 0], "reset money defaults")
	check_eq(rules.load_dict(saved), "", "validated candidate load accepted")
	check(is_same(rules._sales, owner), "candidate load retains live owner")
	check_eq(rules.to_dict(), saved, "candidate load restores all forwarded counters")
	var invalid := saved.duplicate(true)
	invalid.gold = -1.0
	check(not rules.load_dict(invalid).is_empty(), "invalid candidate rejected")
	check_eq(rules.to_dict(), saved, "rejected load preserves money and dictionary")
	check_eq(replacement.lemonade, 4, "reset/load never mutate old external dictionary")

func test_handoff_seat_count_price_event_and_cleanup_order() -> void:
	if _owner() == null: return
	var rules := QuoteRules.new(TEA, 42)
	rules.gold = 10.0
	rules.orders = [{"id": 17, "seat": 2, "takeaway": false}]
	var worker: Dictionary = rules.workers[0]
	worker.job = {"kind": "serve", "item": "lemonade", "count": 3, "order_id": 17, "src": "shelf", "dst": "counter"}
	worker.phase = "dropoff"
	worker.action_left = 0.05
	worker.carry_item = "lemonade"
	worker.carry_count = 3
	var observed := []
	var listener := func(event: Dictionary) -> void:
		observed.append([event.duplicate(), rules.gold, rules.revenue, rules.sold, rules._sale_carry, rules.diners.duplicate(true), worker.phase, worker.job.order_id, worker.carry_count, rules.orders.size()])
	rules.events.on("sale", listener)
	rules._update_worker(worker)
	rules.events.off("sale", listener)
	check_eq(rules.observations, [["seat", 0, 0, 10.0], ["price", 3, 3, 1, 10.0]], "seat before sold before price")
	check_eq(observed, [[{"dish": "lemonade", "count": 3, "income": 3}, 13.0, 3.0, 3, 0.75, [{"seat": 2, "dish": "lemonade", "left": 7.0}], "dropoff", 17, 3, 1]], "synchronous sale sees credit and original assignment/order")
	check_eq([worker.phase, worker.job, worker.carry_count, worker.completed, rules.orders], ["idle", {}, 0, 1, []], "cleanup follows sale callback")

func test_single_queue_quote_pay_event_and_cleanup_order() -> void:
	if _owner() == null: return
	for policy in ["on_take", "on_hand"]:
		var spec: SpecShop = PANCAKE.duplicate(true)
		spec.fulfillment.pay_at = policy
		var rules := QuoteRules.new(spec, 42)
		rules.gold = 10.0
		var c := {"id": 17, "kind": "plain", "addon": true, "state": "queue", "paid": 0}
		rules.customers = [c]
		rules.queue = [17, 19]
		var worker: Dictionary = rules.workers[0]
		worker.order = 17
		worker.steps = [{"action": "take"}, {"action": "hand"}]
		worker.step = 0
		worker.phase = "work"
		rules._finish_work_single(worker)
		check_eq(rules.observations, [["quote", [19], "queue", 10.0, 0.0, 0]], "queue removal precedes price query")
		check_eq([c.state, c.paid, worker.step, rules.gold, rules.revenue, rules.sold], ["paid", 17, 1, 27.0 if policy == "on_take" else 10.0, 17.0 if policy == "on_take" else 0.0, 0], "accept integrates pay policy")
		worker.phase = "work"
		worker.carry_item = "plain"
		worker.carry_count = 1
		var observed := []
		var listener := func(event: Dictionary) -> void:
			observed.append([event.duplicate(), c.state, rules.gold, rules.revenue, rules.sold, rules.sold_by_dish.plain, rules.sold_by_dish.soy, worker.order, worker.phase, worker.step, worker.steps.size(), worker.carry_item])
		rules.events.on("sale", listener)
		rules._finish_work_single(worker)
		rules.events.off("sale", listener)
		check_eq(observed, [[{"dish": "plain", "income": 17}, "leaving", 27.0, 17.0, 2, 1, 1, 17, "idle", 1, 2, "plain"]], "sale after work finish and before order cleanup")
		check_eq([worker.order, worker.steps, worker.carry_item, worker.carry_count], [-1, [], "", 0], "terminal order cleanup follows callback")
