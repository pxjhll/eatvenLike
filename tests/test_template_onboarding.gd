extends "res://tests/test_case.gd"
const Schema := preload("res://game/rules/shop_spec_validator.gd")
var paths: Array = []
func cleanup() -> void:
	for path in paths:
		for file in DirAccess.get_files_at(path.get_base_dir()):
			if file==path.get_file() or file.begins_with(path.get_file()+"."): DirAccess.remove_absolute(path.get_base_dir().path_join(file))
func test_data_only_shop_and_new_shared_employee_complete_two_public_service_combinations() -> void:
	for delivery in ["table","self_pickup"]:
		var file: String = "res://content/examples/onboarding/"+delivery+".tres"
		check(ResourceLoader.exists(file),"persisted public onboarding data: "+delivery)
		if not ResourceLoader.exists(file): continue
		var shop: SpecShop = load(file)
		check_eq(Schema.validate(shop),[],"new shop validates by capabilities")
		for kind in shop.staff.kinds: check(is_same(kind,load("res://content/characters/staff/"+kind.id+".tres")),"canonical employee resource "+kind.id)
		check(shop.staff.starting.has("squirrel"),"new employee uses existing registered art without a controller edit")
		var owner := ShopRules.new(shop,42)
		owner.gold = 1000000.0
		for stage in shop.stages.size(): check_eq(owner.unlock(shop.sold_at(stage)),"","ordinary purchases")
		for box in owner.boxes: check_eq(owner.unlock_box(box),"","ordinary materials")
		owner.runtime.set_tracing(true)
		var operations := {}; var squirrel_worked := false; var cancelled := false
		for tick in 3000:
			owner.step(0.1)
			if not owner.runtime_error.is_empty(): break
			for row in owner.runtime.take_trace().events: operations[row.operation] = true
			for worker in owner.workers.duplicate():
				if worker.kind!="squirrel": continue
				squirrel_worked = squirrel_worked or worker.phase=="work"
				if worker.carry_count>0 and not cancelled:
					check_eq(owner.recall_worker(worker.id),"","cancel real hand through common compensation")
					check_eq(owner.deploy_worker(worker.id),"","redeploy new employee")
					cancelled = true
			if owner.sold>=2 and cancelled and squirrel_worked: break
		check_eq(owner.runtime_error,"","new data uses no special executor")
		check(owner.sold>=2 and cancelled and squirrel_worked,"new employee produces and delivers after actual recall")
		for op in ["inventory.reserve_transfer","inventory.pickup","inventory.drop","inventory.complete_operation"]: check(operations.has(op),"same common operation used: "+op)
		check_eq(owner.runtime.runner.inventory.audit(),[],"one conserved physical inventory")
		var path: String = "user://u07-demo-"+delivery+"-"+str(Time.get_ticks_usec())+".json"; paths.append(path)
		var store := ShopSave.new(shop,path)
		check_eq(store.save_game(owner),OK,"ordinary save")
		var resumed := store.load_game()
		check_eq(store.load_error,OK,"ordinary restore")
		check_eq(_differences(owner.to_dict(),resumed.to_dict()),[],"complete state matches")
		owner.run(3.0); resumed.run(3.0)
		check_eq(_differences(owner.to_dict(),resumed.to_dict()),[],"identical independent continuation")

func _differences(expected: Variant, actual: Variant, path := "") -> Array:
	var out := []
	if expected is Dictionary and actual is Dictionary:
		for key in actual:
			if not expected.has(key): out.append(path+"."+str(key)+": unexpected")
		for key in expected:
			if not actual.has(key): out.append(path+"."+str(key)+": missing")
			else: out.append_array(_differences(expected[key],actual[key],path+"."+str(key)))
	elif expected is Array and actual is Array:
		if expected.size()!=actual.size(): return [path+": array size differs"]
		for index in expected.size(): out.append_array(_differences(expected[index],actual[index],path+"["+str(index)+"]"))
	elif expected!=actual: out.append(path+": "+str(expected)+" != "+str(actual))
	return out
