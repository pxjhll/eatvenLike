extends "res://tests/test_case.gd"
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const Requirements := preload("res://game/rules/template/requirements.gd")

func test_real_tea_staff_gap_requires_equipment_and_materials_not_orders() -> void:
	var rules := ShopRules.new(TEA)
	var view := ShopView.new(rules)
	check(view.staffing_gap().is_empty(), "closed shop has no configuration warning")
	rules.gold = 1000000
	check_eq(rules.unlock("lemonade"), "", "open")
	check(view.staffing_gap().is_empty(), "normal opening only sells front items")
	check_eq(rules.unlock("boil"), "", "open kitchen machine")
	check(view.staffing_gap().is_empty(), "missing ingredients is not misdiagnosed as staffing")
	check_eq(rules.unlock_box("tea_leaf"), "", "ready material")
	var before := rules.rng.state
	var gap := view.staffing_gap()
	check_eq(gap.get("dish"), "black_tea", "first ready staff-gated recipe")
	check_eq(gap.get("missing"), 1, "one qualifying employee needed")
	check_eq(rules.rng.state, before, "query does not consume random state")
	check_eq(rules.hire(), "", "hire")
	check_eq(view.staffing_gap().get("missing"), 1, "roster alone does not satisfy deployment")
	for worker in rules.roster:
		if not worker.deployed: check_eq(rules.deploy_worker(worker.id), "", "deploy")
	check(view.staffing_gap().is_empty(), "deployed mobile worker resolves warning without waiting for travel")
	for worker in rules.workers:
		if worker.post != rules.counter_id:
			check_eq(rules.place_worker(worker.id, "boil"), "", "fixed kitchen post")
	check(view.staffing_gap().is_empty(), "fixed qualifying worker is not reported missing")

func test_generic_requirement_uses_configured_posts_and_count() -> void:
	var rules := ShopRules.new(PANCAKE)
	rules.gold = 1000000
	check_eq(rules.unlock(PANCAKE.goals.opening_station), "", "open unzoned shop")
	var requirement: Dictionary = Requirements.compile({"workers": {"minimum": 2, "exclude_posts": ["arbitrary-post"]}}).definition
	check_eq(Requirements.staff_shortfall(requirement, rules), 1, "generic minimum is not hardcoded to one")
	check(ShopView.new(rules).staffing_gap().is_empty(), "ungated pancake menu gets no tea-specific warning")

func test_toast_distinguishes_configuration_gap_from_fixed_carriers() -> void:
	var rules := ShopRules.new(TEA)
	var scene: Node2D = load("res://presentation/shop/shop_play.gd").new()
	scene.rules = rules
	scene.shop = TEA
	scene.view = ShopView.new(rules)
	rules.gold = 1000000
	rules.unlock("lemonade")
	check_eq(scene._staffing_warning(), "", "opening front worker is enough")
	rules.unlock("boil")
	check_eq(scene._staffing_warning(), "", "ingredients not ready does not report carrier gap")
	rules.unlock_box("tea_leaf")
	check(scene._staffing_warning().contains("红茶"), "ready recipe names the missing configuration")
	check(not scene._staffing_warning().contains("拖到空地"), "no kitchen staff needs deployment, not only dragging")
	rules.hire()
	var kitchen := -1
	for worker in rules.roster:
		if not worker.deployed:
			kitchen = worker.id
			rules.deploy_worker(kitchen)
	check_eq(scene._staffing_warning(), "", "mobile kitchen clears reminder immediately")
	rules.place_worker(kitchen, "boil")
	check(scene._staffing_warning().contains("流动员工"), "all seated kitchen retains carrier advice")
	scene.free()
