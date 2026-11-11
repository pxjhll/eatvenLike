extends "res://tests/test_case.gd"
const TOOL := "res://tools/shop_progression.gd"
const SHOP: SpecShop = preload("res://content/shops/stirfry/shop.tres")
var paths: Array[String] = []

func cleanup() -> void:
	for path in paths:
		for name in DirAccess.get_files_at("user://"):
			if name.begins_with(path.get_file()): DirAccess.remove_absolute("user://"+name)

func _tool() -> Script:
	check(ResourceLoader.exists(TOOL),"progression gate exists independently of all-open rhythm sampling")
	return load(TOOL) if ResourceLoader.exists(TOOL) else null

func test_busy_kitchen_can_recruit_even_when_dedicated_front_is_idle() -> void:
	var tool := _tool()
	if tool==null: return
	var rules := ShopRules.new(SHOP,11)
	rules.unlock("wok_a")
	rules.gold = rules.hire_cost()
	var before := rules.workers.size()
	var actions: Array = []
	tool.visit(rules,{"front":0.0,"kitchen":1.0},0.0,actions)
	check_eq(rules.workers.size(),before+1,"front idle time cannot hide a fully busy kitchen")
	check(actions.any(func(row: Array) -> bool: return row[1]=="hire"),"recruitment spends real shop money")
	check(rules.roster.all(func(worker: Dictionary) -> bool: return worker.deployed),"recruitment actually deploys the new employee")
	check_eq(rules.gold,0.0,"bot uses real costs rather than free staff")

func test_progression_starts_empty_and_records_replayable_commands_without_editing_content() -> void:
	var tool := _tool()
	if tool==null: return
	var contract := preload("res://game/rules/shop_content_contract.gd")
	var before := contract.describe(SHOP)
	var first: Dictionary = tool.sample(SHOP,60.0)
	var second: Dictionary = tool.sample(SHOP,60.0)
	check_eq(first,second,"identical seed and purchase policy reproduce the complete report")
	check_eq(contract.describe(SHOP),before,"sampling never mutates authored shop data")
	check_eq(first.actions[0],[1.0,"unlock wok_a"],"opening is a real first purchase from empty business")
	var replay := ShopRules.new(SHOP,SHOP.random_seed)
	var index := 0
	while replay.clock<60.0-0.0001:
		replay.step(0.1)
		while index<first.actions.size() and float(first.actions[index][0])<=replay.clock+0.0001:
			check_eq(preload("res://tests/baselines/replay_rules.gd").run_command(replay,first.actions[index][1]),"","recorded transaction can replay")
			index += 1
	check_eq(replay.revenue,first.revenue,"recording reproduces actual sales")
	check_eq(replay.sold,first.sold,"recording reproduces actual item count")
	check_eq(first.restore_error,"","sample leaves independently loadable state")

func test_unzoned_shop_can_recruit_into_its_shared_staff_slots() -> void:
	var tool := _tool()
	if tool==null: return
	var rules := ShopRules.new(load("res://content/shops/pancake/shop.tres"))
	rules.gold = 1000000.0
	rules.unlock(rules.next_unlock())
	rules.unlock(rules.next_unlock())
	rules.unlock_box(rules.pending_box())
	rules.gold = rules.hire_cost()
	var before := rules.workers.size()
	var actions: Array = []
	tool.visit(rules,{"all":1.0},0.0,actions)
	check_eq(rules.workers.size(),before+1,"shared staff capacity must not be checked as a nonexistent kitchen zone")

func test_completion_gate_rejects_unfinished_or_out_of_range_shops() -> void:
	var tool := _tool()
	if tool==null: return
	for seconds in [-1.0,3600.0]:
		check(not tool.target_errors({"stirfry":{"completed_at":seconds}}).is_empty(),"unfinished or slow third shop must fail acceptance")
	check_eq(tool.target_errors({"stirfry":{"completed_at":2760.0}}),[],"46-minute target is accepted")

func test_completion_gate_cannot_hide_a_slow_or_missing_secondary_seed() -> void:
	var tool := _tool()
	if tool==null: return
	check(tool.has_method("completion_errors"),"completion gate validates default and secondary seed reports")
	if not tool.has_method("completion_errors"): return
	var report := {"shops":{"stirfry":{"completed_at":2760.0}},"audits":{"stirfry":{"42":{"seed":42,"completed_at":3691.9},"84":{"seed":84,"completed_at":2781.1}}}}
	check(not tool.completion_errors(report).is_empty(),"a passing default cannot conceal the actual slow seed42 regression")
	report.audits.stirfry["42"].completed_at = 2760.0
	check_eq(tool.completion_errors(report),[],"all three seeds within target pass together")
	report.audits.stirfry["42"].seed = 11
	check(not tool.completion_errors(report).is_empty(),"default seed cannot masquerade as a secondary seed")
	report.audits.stirfry["42"].seed = 42
	report.audits.stirfry["84"].completed_at = 3691.9
	check(not tool.completion_errors(report).is_empty(),"second audit is subject to the same completion target")
	report.audits.stirfry["84"].completed_at = 2781.1
	report.audits.stirfry.erase("42")
	check(not tool.completion_errors(report).is_empty(),"omitting an inconvenient audit must fail")

func test_numeric_calibration_preserves_inflight_business_and_original_file_bytes() -> void:
	for id in ["tea","pancake","stirfry"]:
		var current: SpecShop = load("res://content/shops/%s/shop.tres"%id)
		var old_path := "res://tests/fixtures/stirfry_modularity/legacy_shop.tres" if id=="stirfry" else "res://tests/fixtures/legacy_shops/%s.tres"%id
		var legacy: SpecShop = load(old_path).duplicate(true)
		# Same modern protocols/geometry/employee baseline, pre-calibration numbers.
		var before := current.copy_for_editing()
		before.stations = legacy.stations
		before.dishes = legacy.dishes
		before.stages = legacy.stages
		before.staff.hire_costs = legacy.staff.hire_costs
		var rules := ShopRules.new(before,42)
		rules.gold = 1000000.0
		for unused in before.stages.size()+1:
			var next := rules.next_unlock()
			if next.is_empty(): break
			rules.unlock(next)
		for unused in 10:
			var box := rules.pending_box()
			if box.is_empty(): break
			rules.unlock_box(box)
		if rules.workers.size()<2:
			rules.hire()
			for worker: Dictionary in rules.roster:
				if not worker.deployed: rules.deploy_worker(worker.id)
		rules.run(120.0)
		var saved := rules.to_dict()
		var path := "user://calibration-%s-%d.json"%[id,Time.get_ticks_usec()]
		paths.append(path)
		check_eq(ShopSave.new(before,path).save_game(rules),OK,"pre-calibration modern business saves: "+id)
		var bytes := FileAccess.get_file_as_bytes(path)
		var store := ShopSave.new(current,path)
		var resumed := store.load_game()
		check_eq(store.load_error,OK,"numeric calibration retains valid progress: "+id)
		check_eq(FileAccess.get_file_as_bytes(path),bytes,"opening remains read-only: "+id)
		var after := resumed.to_dict()
		for key in saved:
			if key=="mods": continue
			check_eq(after.get(key),saved[key],"recorded business/timers/inventory preserved: "+id+" "+key)
		check_eq(store.save_game(resumed),OK,"migrated business saves: "+id)
		var backups: Array[String] = []
		for name in DirAccess.get_files_at("user://"):
			if name.begins_with(path.get_file()+".pre-content-"): backups.append("user://"+name)
		check_eq(backups.size(),1,"one durable pre-calibration backup: "+id)
		if not backups.is_empty(): check_eq(FileAccess.get_file_as_bytes(backups[0]),bytes,"original business retained byte for byte: "+id)
		resumed.run(120.0)
		check(resumed.sold>rules.sold,"updated business continues actual sales: "+id)
		check_eq(ShopRules.new(current).load_dict(resumed.to_dict()),"","continued state independently reloads: "+id)
