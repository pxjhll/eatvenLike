extends "res://tests/test_case.gd"

const CASES := [
	{"shop":"pancake", "supply":"raw_ingredients", "station":"rear_equipment", "material":"flour", "kind":"gray_cat", "price":30, "dish":"plain"},
	{"shop":"tea", "supply":"supply", "station":"boil", "material":"tea_leaf", "kind":"bear", "price":35, "dish":"black_tea"},
]
var paths: Array[String] = []

func _open(definition: SpecShop, station: String) -> ShopRules:
	var rules := ShopRules.new(definition,42)
	rules.gold = 10000.0
	check_eq(rules.unlock(definition.sold_at(0)),"","open the shop")
	check_eq(rules.unlock(station),"","purchase the first kitchen machine")
	return rules

func _previous_shop(case: Dictionary) -> SpecShop:
	var shop: SpecShop = load("res://content/shops/"+case.shop+"/shop.tres").copy_for_editing()
	shop.station(case.supply).material(case.material).grant_worker = ""
	if case.shop=="pancake":
		shop.stages.back().staff_slots[""] = 4
		shop.staff.hire_costs = [30,100,200]
	return shop

func test_machine_purchase_waits_for_the_material_box_and_gift_is_free_and_once() -> void:
	for case in CASES:
		var shop: SpecShop = load("res://content/shops/"+case.shop+"/shop.tres")
		var rules := _open(shop,case.station)
		check_eq(rules.workers.size(),1,"buying the machine alone gives no employee")
		var before := rules.gold
		check_eq(rules.unlock_box(case.material),"","buy the actual first ingredient box")
		check_eq(rules.gold,before-20.0,"only the ingredient box costs coins")
		check_eq(rules.workers.size(),2,"the helper immediately joins the active staff")
		check_eq(rules.workers.back().kind,case.kind,"use the configured animal")
		check_eq(rules.workers.back().source,"解锁","gift has free provenance")
		check_eq(rules.workers.back().post,"","helper is mobile")
		if case.shop=="tea": check_eq(rules.kitchen_staff(),1,"the bear works in the kitchen")
		check_eq(rules.hire_cost(),case.price,"the free helper preserves the first paid tier")
		check(rules.menu().has(case.dish),"equipment, ingredients and staff enable the first kitchen dish")
		check(not rules.unlock_box(case.material).is_empty(),"repeat purchase is rejected")
		check_eq(rules.roster.size(),2,"repeat purchase cannot duplicate the reward")
		check_eq(rules.load_dict(rules.to_dict()),"","gift roundtrips through the normal save protocol")
		rules.run(180.0)
		check(rules.runtime_error.is_empty(),"new team runs without runtime errors")
		check(int(rules.sold_by_dish[case.dish])>0,"the gifted team actually produces and sells its first kitchen dish")

func test_first_shop_final_slot_accepts_five_workers_at_existing_paid_tiers() -> void:
	var shop: SpecShop = load("res://content/shops/pancake/shop.tres")
	var rules := _open(shop,"rear_equipment")
	check_eq(rules.unlock_box("flour"),"","receive the first helper")
	for station in ["fryer","topping"]: check_eq(rules.unlock(station),"","open the next machine")
	check_eq(rules.staff_slots(),4,"before bagging there are four places")
	check_eq(rules.unlock("bag"),"","open bagging")
	check_eq(rules.staff_slots(),5,"bagging opens the fifth place")
	for price in [30,100,200]:
		check_eq(rules.hire_cost(),price,"paid hiring retains its existing cost")
		check_eq(rules.hire(),"","hire into a real available place")
	check_eq(rules.workers.size(),5,"all five places can be filled")
	check(not rules.hire().is_empty(),"cannot hire beyond five places")
	check_eq(rules.load_dict(rules.to_dict()),"","five employees restore normally")

func test_prebought_staff_keeps_the_gift_until_the_next_slot_opens() -> void:
	var shop: SpecShop = load("res://content/shops/pancake/shop.tres")
	var rules := _open(shop,"rear_equipment")
	check_eq(rules.hire(),"","player may recruit before buying ingredients")
	check_eq(rules.unlock_box("flour"),"","ingredient purchase still grants a helper")
	check_eq(rules.roster.size(),3,"the gift is retained")
	check_eq(rules.workers.size(),2,"the gift respects occupied slots")
	check(not rules.roster.back().deployed,"gift waits for an available place")
	check_eq(rules.load_dict(rules.to_dict()),"","waiting gift is preserved")
	check_eq(rules.unlock("fryer"),"","next machine opens another place")
	check_eq(rules.workers.size(),3,"waiting helper takes the newly opened place")
	check_eq(rules.hire_cost(),100,"only the actual paid recruit used a price tier")

func test_previous_saves_receive_only_a_missing_helper_and_keep_business_state() -> void:
	for case in CASES:
		var previous := _previous_shop(case)
		var old := _open(previous,case.station)
		check_eq(old.unlock_box(case.material),"","previous version has the box without a gift")
		old.run(4.0)
		var saved := old.to_dict()
		var current: SpecShop = load("res://content/shops/"+case.shop+"/shop.tres")
		var rules := ShopRules.new(current,42)
		check_eq(rules.load_dict(saved,true),"","refresh the previous save")
		check_eq(rules.workers.size(),2,"missing helper is supplied on refresh")
		check_eq(rules.gold,old.gold,"refresh preserves coins")
		check_eq(rules.sold,old.sold,"refresh preserves sales")
		var runtime: Dictionary = rules.runtime.snapshot()
		check_eq(runtime.service,saved.runtime.service,"orders and customer movement remain exact")
		check_eq(runtime.runner.inventory,saved.runtime.runner.inventory,"inventory and reservations remain exact")
		check_eq(runtime.runner.tasks,saved.runtime.runner.tasks,"existing work remains exact")
		var restored := rules.to_dict()
		check_eq(rules.load_dict(restored,true),"","repeated content refresh is supported")
		check_eq(rules.roster.size(),2,"repeated refresh gives no duplicate")
		check_eq(rules.hire_cost(),case.price,"backfilled helpers preserve paid recruitment tiers")

func test_previous_staffed_saves_and_recalled_gifts_do_not_gain_extra_workers() -> void:
	for case in CASES:
		var old := _open(_previous_shop(case),case.station)
		check_eq(old.unlock_box(case.material),"","buy ingredients in the previous version")
		check_eq(old.hire(),"","the previous player already recruited a helper")
		if case.shop=="tea": check_eq(old.deploy_worker(old.roster.back().id),"","deploy the paid kitchen helper")
		var rules := ShopRules.new(load("res://content/shops/"+case.shop+"/shop.tres"),42)
		check_eq(rules.load_dict(old.to_dict(),true),"","staffed previous save restores")
		check_eq(rules.roster.size(),2,"an equipped previous team gains no duplicate helper")
	var tea := _open(load("res://content/shops/tea/shop.tres"),"boil")
	check_eq(tea.unlock_box("tea_leaf"),"","receive the new bear")
	var bear: Dictionary = tea.roster.back()
	check_eq(tea.recall_worker(bear.id),"","player can recall the gift")
	check_eq(tea.load_dict(tea.to_dict(),true),"","recalled gift survives a refresh")
	check_eq(tea.roster.size(),2,"recall does not recreate the gift")
	check_eq(tea.kitchen_staff(),0,"refresh respects the player's recall")
	check_eq(tea.unlock("seal"),"","open another machine after recall")
	check_eq(tea.kitchen_staff(),0,"new equipment respects the recalled kitchen helper")

func test_disk_update_preserves_original_progress_and_saves_backfilled_helper_once() -> void:
	for case in CASES:
		var previous := _previous_shop(case)
		var old := _open(previous,case.station)
		check_eq(old.unlock_box(case.material),"","old version buys the first ingredients")
		old.run(1.0)
		var path := "user://material-gift-%s-%d.json" % [case.shop,Time.get_ticks_usec()]
		paths.append(path)
		check_eq(ShopSave.new(previous,path).save_game(old,2.0,["opening"]),OK,"write a previous-version disk save")
		var original := FileAccess.get_file_as_bytes(path)
		var current: SpecShop = load("res://content/shops/"+case.shop+"/shop.tres")
		check_eq(old.to_dict().template,ShopRules.new(current,42).to_dict().template,"gift and slot changes retain the runtime template identity")
		var store := ShopSave.new(current,path)
		var loaded := store.load_game()
		check_eq(store.load_error,OK,"normal entry opens the previous save")
		check_eq(loaded.workers.size(),2,"normal disk load backfills the missing helper")
		check_eq(loaded.gold,old.gold,"disk update keeps coins")
		check_eq(loaded.stage_index,old.stage_index,"disk update keeps machine progression")
		check_eq(store.loaded_speed,2.0,"playback preference survives")
		check_eq(store.loaded_guides,["opening"],"guide history survives")
		check_eq(FileAccess.get_file_as_bytes(path),original,"reading the old file does not replace it")
		check_eq(store.save_game(loaded,2.0,["opening"]),OK,"save the migrated team through the normal path")
		var reopened := store.load_game()
		check_eq(store.load_error,OK,"updated file reopens")
		check_eq(reopened.roster.size(),2,"reopening cannot duplicate the gift")
		check_eq(reopened.hire_cost(),case.price,"disk roundtrip preserves the first paid price")

func test_full_previous_first_shop_can_recruit_into_the_new_fifth_place() -> void:
	var previous := _previous_shop(CASES[0])
	var old := _open(previous,"rear_equipment")
	check_eq(old.unlock_box("flour"),"","old version buys ingredients")
	for station in ["fryer","topping","bag"]: check_eq(old.unlock(station),"","complete previous equipment progression")
	for index in 3: check_eq(old.hire(),"","fill all four original positions")
	check_eq(old.hire_cost(),-1,"previous version has exhausted its paid tiers")
	var current := ShopRules.new(load("res://content/shops/pancake/shop.tres"),42)
	check_eq(current.load_dict(old.to_dict(),true),"","restore the full previous team")
	check_eq(current.workers.size(),4,"retain the player's full team")
	check_eq(current.staff_slots(),5,"the previous bagging purchase opens the new place")
	check_eq(current.hire_cost(),300,"the additional paid tier makes the new place usable")
	check_eq(current.hire(),"","fill the fifth place through normal hiring")
	check_eq(current.workers.size(),5,"the previous save can use all five places")

func cleanup() -> void:
	for path in paths:
		for file in DirAccess.get_files_at(path.get_base_dir()):
			if file.begins_with(path.get_file()): DirAccess.remove_absolute(path.get_base_dir().path_join(file))
