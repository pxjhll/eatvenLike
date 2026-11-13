extends "res://tests/test_case.gd"
const State := preload("res://game/rules/template/runtime.gd")
var paths: Array = []
class RefuseBackup extends ShopSave:
	func _backup_before_content_update() -> Error:
		return ERR_FILE_CANT_WRITE

func cleanup() -> void:
	for path in paths:
		for file in DirAccess.get_files_at(path.get_base_dir()):
			if file==path.get_file() or file.begins_with(path.get_file()+"."): DirAccess.remove_absolute(path.get_base_dir().path_join(file))

func _owner(id: String) -> ShopRules:
	var owner := ShopRules.new(load("res://content/shops/"+id+"/shop.tres").copy_for_editing(),42)
	owner.gold = 1000000.0
	check(owner.has_method("enable_runtime"),"ShopRules must own the sole public Runtime")
	if owner.has_method("enable_runtime"):
		check_eq(owner.call("enable_runtime",load("res://content/shops/"+id+"/shared_production.tres")),"","explicit shared template adoption")
	for stage in owner.shop.stages.size(): check_eq(owner.unlock(owner.shop.sold_at(stage)),"","outer purchases")
	return owner

func test_formal_owner_steps_one_runtime_and_saves_a_distinct_business_version() -> void:
	for id in ["tea","pancake","stirfry"]:
		var owner := _owner(id)
		if not owner.has_method("enable_runtime"): continue
		owner.run(12.0)
		var saved := owner.to_dict()
		check_eq(saved.get("version"),2,"new business state has its own version")
		check(saved.get("runtime") is Dictionary,"same public runtime is saved")
		check(not saved.has("serve") and not saved.has("stations") and not saved.has("orders"),"no second legacy business ledger in new saves")
		check_eq(saved.runtime.clock,owner.clock,"one simulation clock")
		check_eq(saved.runtime.service.arrivals.started,true,"formal flow opens through same public arrival capability")
		check_eq(owner.orders,[],"old customer loop is never advanced")

func test_shared_state_roundtrip_is_atomic_and_keeps_the_live_event_bus() -> void:
	for id in ["tea","pancake","stirfry"]:
		var owner := _owner(id)
		if not owner.has_method("enable_runtime"): continue
		owner.run(32.0)
		var saved := owner.to_dict()
		var before_rng := owner.rng.state
		var bus := owner.events
		check_eq(owner.load_dict(saved),"","restore actual runtime and outer purchases together")
		check_eq(owner.to_dict(),saved,"lossless live restoration")
		check_eq(owner.rng.state,before_rng,"restoring does not draw random choices")
		check_eq(owner.events,bus,"subscribers retain the same bus")
		var invalid := saved.duplicate(true)
		invalid.runtime.clock = -1.0
		check(not owner.load_dict(invalid).is_empty(),"reject invalid runtime before adopting outer values")
		check_eq(owner.to_dict(),saved,"rejection is atomic")

func test_active_employee_order_rejects_malformed_nested_data_atomically() -> void:
	var owner := _owner("tea")
	var saved := owner.to_dict()
	for payload in [null,[],1,"invalid"]:
		var invalid := saved.duplicate(true)
		invalid.runtime.runner = payload
		check(not owner.load_dict(invalid).is_empty(),"malformed runner rejected without runtime error")
		check_eq(owner.to_dict(),saved,"failed nested shape validation preserves live state")
	for actors in [null,{},[{}],[{"id":999999}]]:
		var invalid := saved.duplicate(true)
		invalid.runtime.runner.actors = actors
		check(not owner.load_dict(invalid).is_empty(),"invalid active order rejected")
		check_eq(owner.to_dict(),saved,"invalid actor order is atomic")

func test_restored_public_runtime_continues_with_the_original_owner_wallet() -> void:
	for id in ["tea","pancake","stirfry"]:
		var owner := _owner(id)
		if not owner.has_method("enable_runtime"): continue
		owner.run(7.0)
		var other := _owner(id)
		check_eq(other.load_dict(owner.to_dict()),"","restore independent owner")
		owner.run(70.0); other.run(70.0)
		check_eq(other.to_dict(),owner.to_dict(),"same complete continuation and RNG")
		check(owner.sold>0,"actual formal production reaches a sale")

func test_sale_observers_can_save_restore_and_recall_without_half_committed_state() -> void:
	var owner := _owner("stirfry")
	if not owner.has_method("enable_runtime"): return
	var observations := []
	var observer := func(_receipt: Dictionary) -> void:
		var saved := owner.to_dict()
		observations.append(saved.outer.sold)
		check_eq(owner.load_dict(saved),"","sale callback observes a fully committed runtime")
		check_eq(owner.to_dict(),saved,"callback restore does not settle twice")
		if not owner.workers.is_empty(): check_eq(owner.recall_worker(owner.workers[0].id),"","recall through the same inventory cancellation")
	owner.events.on("sale",observer)
	owner.run(130.0)
	owner.events.off("sale",observer)
	check(not observations.is_empty(),"real sale reaches the public event bus")
	check_eq(owner.load_dict(owner.to_dict()),"","state remains restorable after synchronous recall")

func test_public_recall_cancels_actual_hand_and_releases_the_same_inventory_once() -> void:
	var owner := _owner("tea")
	if not owner.has_method("enable_runtime"): return
	for tick in 1600:
		owner.step(0.1)
		var carrying: Array = owner.workers.filter(func(worker: Dictionary) -> bool: return worker.carry_count>0)
		if carrying.is_empty(): continue
		var id: int = carrying[0].id
		check_eq(owner.recall_worker(id),"","recall active public actor")
		check_eq(owner.worker_by_id(id).carry_count,0,"recall commits actual inventory compensation")
		check(owner.runtime.runner.idle(id),"public task is released")
		check_eq(owner.load_dict(owner.to_dict()),"","cancelled graph/stock/service remains coherent")
		return
	check(false,"actual public transfer was observed")

func test_new_state_uses_existing_save_path_and_future_runtime_protects_original_bytes() -> void:
	var shop: SpecShop = load("res://content/shops/stirfry/shop.tres").copy_for_editing()
	shop.runtime_template = load("res://content/shops/stirfry/shared_production.tres")
	var owner := ShopRules.new(shop,42)
	check(owner.runtime!=null,"formal template is initialized by the ordinary constructor")
	var path := "user://u06-state-"+str(Time.get_ticks_usec())+".json"
	paths.append(path)
	var store := ShopSave.new(shop,path)
	check_eq(store.save_game(owner),OK,"new protocol uses existing save service")
	var restored := store.load_game()
	check_eq(store.load_error,OK,"new runtime format is accepted")
	check_eq(restored.to_dict(),owner.to_dict(),"disk roundtrip uses the same runtime state")
	var wrapper: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var future := owner.to_dict()
	future.version = 99
	var bytes := var_to_bytes(future)
	wrapper.state = Marshalls.raw_to_base64(bytes); wrapper.state_sha256 = bytes.hex_encode().sha256_text()
	var future_file := FileAccess.open(path,FileAccess.WRITE)
	future_file.store_string(JSON.stringify(wrapper)); future_file.close()
	var original := FileAccess.get_file_as_bytes(path)
	store.load_game()
	check_eq(store.load_error,ERR_UNAVAILABLE,"future public protocol seals the file")
	check_eq(store.save_game(owner),ERR_UNAVAILABLE,"automatic saving cannot replace future state")
	check_eq(FileAccess.get_file_as_bytes(path),original,"future bytes stay exact")

func test_formal_flyer_command_and_ui_share_the_same_cooldown_and_pending_wave() -> void:
	var owner := _owner("tea")
	var before: Dictionary = owner.runtime.service.flyers.snapshot()
	check_eq(owner.send_flyers(),"","send through the existing command API")
	var after: Dictionary = owner.runtime.service.flyers.snapshot()
	check(after.pending>before.pending,"command enqueues public arrivals")
	check(not owner.flyer_error().is_empty(),"same public cooldown rejects a duplicate")
	var view := ShopView.new(owner)
	check_eq(view.flyer().pending,after.pending,"UI reads the same pending count")
	check_eq(view.flyer().wait,after.cooldown,"UI reads the same remaining cooldown")

func test_view_follows_the_official_owner_across_atomic_restore() -> void:
	var owner := _owner("stirfry")
	var view := ShopView.new(owner)
	check_eq(view.render_snapshot().get("presentation_version"),1,"normal views select the owner runtime")
	owner.run(8.0)
	var saved := owner.to_dict()
	check_eq(owner.load_dict(saved),"","replace the owned runtime")
	owner.run(2.0)
	check_eq(view.render_snapshot().clock,owner.clock,"existing panels never retain a stale runtime")
	check_eq(view.activity_snapshot().clock,owner.clock,"activity queries follow the same current source")

func test_existing_unbound_production_is_adopted_once_by_orders_in_two_service_combinations() -> void:
	var fixture: Script = load("res://tests/fixtures/template_service.gd")
	for delivery in ["counter","self_pickup"]:
		var runtime: RefCounted = fixture.runtime(delivery)
		var prepared: int = runtime.request_production("drink").id
		for tick in 600:
			check_eq(runtime.step(0.1),"","prepare stock through the real public graph")
			if runtime.ready(prepared): break
		check(runtime.ready(prepared),"preparation completed")
		for unused in 2: check_eq(runtime.arrive([{"dish":"lemonade","qty":1}]).error,"","new customers")
		for tick in 1400:
			check_eq(runtime.step(0.1),"","prepared inventory and new production share fulfillment")
			if runtime.runner.owner.sold==2: break
		var units: Array = []
		for order in runtime.service.orders.snapshot().orders:
			for line in order.lines:
				for binding in line.units: units.append(int(binding.unit))
		check(prepared in units,"the existing prepared unit is used")
		check_eq(units.count(prepared),1,"preparation cannot be sold twice")

func test_numeric_template_refresh_keeps_committed_work_and_adopts_future_recipe_times() -> void:
	var owner := _owner("pancake")
	owner.run(13.0)
	var saved := owner.to_dict()
	var shop: SpecShop = owner.shop.copy_for_editing()
	shop.runtime_template = owner._runtime_template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for node in shop.runtime_template.recipes.ham.nodes:
		if node.id=="grill": node.seconds = 17.0
	var replacement := ShopRules.new(shop,42)
	check_eq(replacement.load_dict(saved,true),"","numeric-only template adoption")
	check_eq(replacement.runtime._definition.recipes.ham.nodes.grill.seconds,17.0,"future work uses the new definition")
	check_eq(replacement.runtime.runner.machines.snapshot().runs,saved.runtime.runner.machines.runs,"existing runs retain exact original durations and remaining work")
	check_eq(replacement.rng.state,saved.outer.rng[1],"numeric adoption does not redraw a menu")

func test_legacy_disk_adoption_requires_an_exact_backup_before_any_replacement() -> void:
	for id in ["tea","pancake","stirfry"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/runtime_legacy/"+id+".json"))
		var old: Dictionary = bytes_to_var(Marshalls.base64_to_raw(fixture.states["599"]))
		var shop: SpecShop = load("res://content/shops/"+id+"/shop.tres")
		var legacy: SpecShop = shop.duplicate(false)
		legacy.runtime_template = null
		var path: String = "user://u06-legacy-disk-"+id+"-"+str(Time.get_ticks_usec())+".json"
		paths.append(path)
		var bytes := var_to_bytes(old)
		var payload := {"format":ShopSave.FORMAT,"version":ShopSave.VERSION,"shop":id,"content":load("res://game/rules/shop_content_contract.gd").describe(legacy),"speed":2.0,"guides":["prior-guide"],"state":Marshalls.raw_to_base64(bytes),"state_sha256":bytes.hex_encode().sha256_text()}
		check_eq(SaveService.new(path).save(payload),OK,"write authentic legacy envelope")
		var original := FileAccess.get_file_as_bytes(path)
		var denied := RefuseBackup.new(shop,path)
		var converted := denied.load_game()
		check_eq(denied.load_error,OK,"legacy session starts with converted facts")
		check_eq(converted.to_dict().version,2,"old disk state is actually converted")
		check_eq(denied.loaded_speed,2.0,"playback setting survives migration")
		check_eq(denied.loaded_guides,["prior-guide"],"guide history survives migration")
		check_eq(FileAccess.get_file_as_bytes(path),original,"load is read-only")
		check_eq(denied.save_game(converted),ERR_FILE_CANT_WRITE,"failed backup blocks replacement")
		check_eq(FileAccess.get_file_as_bytes(path),original,"backup failure preserves exact original bytes")
		var store := ShopSave.new(shop,path)
		check_eq(store.save_game(converted,2.0,["prior-guide"]),OK,"successful copy permits replacement")
		var backups := []
		for file in DirAccess.get_files_at(path.get_base_dir()):
			if file.begins_with(path.get_file()+".pre-content-"): backups.append(path.get_base_dir().path_join(file))
		check_eq(backups.size(),1,"one durable backup was made")
		if not backups.is_empty(): check_eq(FileAccess.get_file_as_bytes(backups[0]),original,"backup bytes are verified exact")
		check_eq(store.load_game().to_dict(),converted.to_dict(),"converted disk state reopens without migrating again")

func test_authoring_example_uses_the_same_formal_constructor_commands_and_state_protocol() -> void:
	var shop: SpecShop = load("res://content/examples/modular_shop.tres")
	check(shop.id!="stirfry" and shop.runtime_template!=null,"example is an independent configured shop")
	var owner := ShopRules.new(shop,42)
	check(owner.runtime!=null and owner.runtime_error.is_empty(),"no example executor is installed")
	owner.gold = 1000000.0
	for stage in shop.stages.size(): check_eq(owner.unlock(shop.sold_at(stage)),"","same public purchase command")
	owner.run(70.0)
	check(owner.sold>0,"example actually produces and settles through the formal runtime")
	check_eq(owner.load_dict(owner.to_dict()),"","same strict public save version")
func test_invalid_formal_template_cannot_fall_back_to_legacy_save_and_hints_survive_restore() -> void:
	var shop: SpecShop = load("res://content/shops/tea/shop.tres").copy_for_editing()
	shop.runtime_template = shop.runtime_template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	shop.runtime_template.recipes.clear()
	var invalid := ShopRules.new(shop,42)
	check(not invalid.runtime_error.is_empty(),"bad declared template fails construction")
	var path := "user://u06-invalid-"+str(Time.get_ticks_usec())+".json"
	paths.append(path)
	check_eq(ShopSave.new(shop,path).save_game(invalid),ERR_INVALID_DATA,"cannot persist an accidental old protocol")
	check(not FileAccess.file_exists(path),"invalid formal session cannot create a player save")
	var owner := _owner("pancake")
	owner.run(12.0)
	check(not owner.side_idle.is_empty(),"public activity drives bottleneck observations")
	var saved := owner.to_dict()
	check_eq(owner.load_dict(saved),"","restore public session with accumulated hint observations")
	check_eq(owner.side_idle,saved.outer.get("side_idle"),"hint history is persistent")
