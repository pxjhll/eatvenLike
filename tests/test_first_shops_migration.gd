extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/movement_shop.gd")
const Validator := preload("res://game/rules/shop_spec_validator.gd")
const LEGACY_TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/tea.tres")
const LEGACY_PANCAKE: SpecShop = preload("res://tests/fixtures/legacy_shops/pancake.tres")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
var paths: Array[String] = []

class QuarantineFailure extends ShopSave:
	var fail_backup := true
	func _backup_corrupt() -> Error:
		return ERR_CANT_CREATE if fail_backup else super._backup_corrupt()

func cleanup() -> void:
	for path in paths:
		for name in DirAccess.get_files_at("user://"):
			if name.begins_with(path.get_file()): DirAccess.remove_absolute("user://"+name)
	paths.clear()

func _adapters() -> bool:
	var found := true
	for mode in ["handoff","single"]:
		var path := "res://game/rules/%s_action_context.gd"%mode
		check(ResourceLoader.exists(path),"business action adapter exists: "+mode)
		found = found and ResourceLoader.exists(path)
	return found

func _shop(mode: String) -> SpecShop:
	var shop := Fixture.definition(mode)
	shop.dispatch.action_version = 1
	return shop

func _opened(mode: String) -> ShopRules:
	var shop := _shop(mode)
	var rules := ShopRules.new(shop,42)
	rules.gold = 1000000.0
	for index in shop.stages.size()+1:
		var next := rules.next_unlock()
		if next.is_empty(): break
		rules.unlock(next)
	for index in 10:
		var box := rules.pending_box()
		if box.is_empty(): break
		rules.unlock_box(box)
	for index in 2:
		if not rules.hire().is_empty(): break
		for worker: Dictionary in rules.roster:
			if not worker.deployed: rules.deploy_worker(worker.id)
	return rules

func test_handoff_and_single_opt_in_require_motion_but_support_their_existing_policies() -> void:
	for mode in ["handoff","single"]:
		var shop := _shop(mode)
		check_eq(Validator.validate(shop),[],"shared adapter accepts existing "+mode+" policy")
		shop.layout.motion_version = 0
		check(not Validator.validate(shop).is_empty(),"action adapter cannot bypass shared movement")

func test_controlled_business_uses_real_action_programs_and_each_phase_restores_exactly() -> void:
	if not _adapters(): return
	for mode in ["handoff","single"]:
		var rules := _opened(mode)
		var seen := {}
		for tick in 1800:
			rules.step(0.1)
			for worker: Dictionary in rules.workers:
				if not worker.has("action"): continue
				var step: Dictionary = worker.action.steps[worker.action.index]
				var key: String = step.kind+":"+worker.action.status
				if seen.has(key): continue
				seen[key] = true
				var state := rules.to_dict()
				var resumed := ShopRules.new(rules.shop,42)
				check_eq(resumed.load_dict(state),"","restore current "+mode+" "+key)
				check_eq(resumed.to_dict(),state,"all serialized fields are exact: "+mode+" "+key)
		for kind in (["move","operate","pickup","transport","drop"] if mode=="handoff" else ["move","operate","pickup","drop"]):
			check(seen.keys().any(func(key: String) -> bool: return key.begins_with(kind+":")),"real business executes "+mode+" "+kind)
		check(rules.sold>0,"shared adapter completes sales: "+mode)

func test_sale_callbacks_capture_a_fully_committed_resumable_business() -> void:
	if not _adapters(): return
	for mode in ["handoff","single"]:
		var rules := _opened(mode)
		var snapshots: Array = []
		var listener := func(_event: Dictionary) -> void: snapshots.append(rules.to_dict())
		rules.events.on("sale",listener)
		rules.run(180.0)
		rules.events.off("sale",listener)
		check(not snapshots.is_empty(),"real sale callbacks: "+mode)
		for state: Dictionary in snapshots.slice(0,4): check_eq(ShopRules.new(rules.shop,42).load_dict(state),"","sale callback must not retain terminal business lease: "+mode)

func test_single_cancel_releases_unfinished_material_and_resumes_paid_order_without_recharging() -> void:
	if not _adapters(): return
	var rules := _opened("single")
	var found := false
	for tick in 2400:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if not worker.get("action",{}).get("lease",{}).get("stock_taken",false): continue
			var id: int = worker.order
			var index: int = worker.step
			var station: String = worker.steps[index].station
			var stock: int = rules.stations[station].stock
			var revenue := rules.revenue
			check_eq(rules.recall_worker(worker.id),"","recall active single worker")
			check_eq(rules.stations[station].stock,stock+1,"uncommitted stock is returned once")
			check_eq(worker.order,id,"paid order identity remains with saved checkpoint")
			check_eq(worker.step,index,"completed recipe progress is retained")
			check_eq(rules.revenue,revenue,"cancel does not charge again")
			check_eq(rules.deploy_worker(worker.id),"","redeploy resumes saved order")
			found = true
			break
		if found: break
	check(found,"actual recipe reaches a material reservation")
	rules.run(120.0)
	check(rules.sold>0,"recalled order can finish after redeployment")
	check_eq(ShopRules.new(rules.shop,42).load_dict(rules.to_dict()),"","cancellation leaves a valid complete state")

func test_first_two_formal_shops_share_staff_and_enable_the_common_protocols() -> void:
	for shop in [TEA,PANCAKE]:
		check(shop.layout.motion_version==1 and shop.dispatch.action_version==1,"formal store opts in to common movement and actions: "+shop.id)
		for kind in shop.staff.kinds:
			check(is_same(kind,load("res://content/characters/staff/%s.tres"%kind.id)),"global definition reused: "+kind.id)

func test_every_captured_legacy_phase_adopts_without_repeating_business_effects() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_shops/states.json"))
	for pair in [["tea","handoff"],["pancake","single"]]:
		var shop: SpecShop = TEA if pair[0]=="tea" else PANCAKE
		for name: String in fixtures[pair[0]]:
			var state: Dictionary = bytes_to_var(Marshalls.base64_to_raw(fixtures[pair[0]][name].state))
			var rules := ShopRules.new(shop,42)
			var error := rules.load_dict(state)
			check_eq(error,"","adopt real legacy "+pair[0]+" "+name)
			if not error.is_empty(): continue
			check_eq(rules.revenue,state.revenue,"adoption does not recharge")
			check_eq(rules.stations,state.stations,"adoption does not replay inventory")
			for worker: Dictionary in rules.workers:
				check(rules.nav.can_stand(worker.pos,"staff"),"adopted staff footprint is legal")
			check_eq(ShopRules.new(shop,42).load_dict(rules.to_dict()),"","adopted phase roundtrips")
			rules.run(15.0)
			check_eq(ShopRules.new(shop,42).load_dict(rules.to_dict()),"","adopted phase continues: "+pair[0]+" "+name)

func test_malformed_business_bindings_and_effects_are_rejected_atomically() -> void:
	for mode in ["handoff","single"]:
		var rules := _opened(mode)
		for tick in 300:
			rules.step(0.1)
			if rules.workers.any(func(worker: Dictionary) -> bool: return worker.has("action")): break
		var saved := rules.to_dict()
		var active: Array = saved.roster.filter(func(worker: Dictionary) -> bool: return worker.has("action"))
		check(not active.is_empty(),"real active action")
		if active.is_empty(): continue
		var id: int = active[0].id
		for field in ["owner","target","effect","cursor","stock"]:
			var bad := saved.duplicate(true)
			var worker: Dictionary = bad.roster.filter(func(row: Dictionary) -> bool: return row.id==id)[0]
			match field:
				"owner": worker.action.lease.owner = 999
				"target": worker.action.steps[0].target = "arbitrary"
				"effect": worker.action.steps[0].kind = "drop"
				"cursor": worker.action.index = worker.action.steps.size()
				"stock": worker.action.lease.stock_taken = true
			check(not rules.load_dict(bad).is_empty(),"reject "+mode+" "+field)
			check_eq(rules.to_dict(),saved,"failed load preserves live state")

func test_formal_content_changes_only_shared_staff_spatial_data_and_action_opt_in() -> void:
	var content := preload("res://game/rules/shop_content_contract.gd")
	var contract := preload("res://presentation/shop/shop_scene_contract.gd")
	for pair in [[TEA,LEGACY_TEA],[PANCAKE,LEGACY_PANCAKE]]:
		var original: SpecShop = pair[1]
		var shop: SpecShop = pair[0]
		var comparable := shop.copy_for_editing()
		comparable.layout = original.layout.duplicate(true)
		comparable.staff.kinds = original.staff.duplicate(true).kinds
		comparable.dispatch.action_version = 0
		check_eq(content.describe(comparable),content.describe(original),"recipes, policies, economy and progression unchanged: "+shop.id)
		var prepared := contract.prepare(shop)
		check_eq(prepared.errors,[],"formal authored geometry agrees: "+shop.id)
		if prepared.art!=null: prepared.art.free()
		var nav := RuleNav.new(shop.layout)
		check(not nav.can_stand(shop.layout.points[shop.layout.spawn_point],"customer"),"customers cannot enter employee kitchen")
		check(nav.path(shop.layout.customer_points.entrance,shop.layout.points[shop.layout.spawn_point],"customer").is_empty(),"customer routes respect kitchen permissions")

func test_actual_legacy_files_get_byte_exact_backup_and_new_state_roundtrips() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_shops/states.json"))
	for shop in [TEA,PANCAKE]:
		var path := "user://first-migration-%s-%d.json"%[shop.id,Time.get_ticks_usec()]
		paths.append(path)
		var original := JSON.stringify(fixtures[shop.id].active,"  ").to_utf8_buffer()
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
		var store := ShopSave.new(shop,path)
		var rules := store.load_game()
		check_eq(store.load_error,OK,"old active file loads: "+store.last_error)
		check_eq(rules.clock,bytes_to_var(Marshalls.base64_to_raw(fixtures[shop.id].active.state)).clock,"old progress preserved")
		check_eq(FileAccess.get_file_as_bytes(path),original,"opening keeps old bytes")
		check_eq(store.save_game(rules),OK,"first replacement saves: "+store.last_error)
		var backups: Array[String] = []
		for name in DirAccess.get_files_at("user://"):
			if name.begins_with(path.get_file()+".pre-content-"): backups.append("user://"+name)
		check_eq(backups.size(),1,"one durable original backup")
		if not backups.is_empty(): check_eq(FileAccess.get_file_as_bytes(backups[0]),original,"backup byte for byte")
		var loaded := ShopSave.new(shop,path).load_game()
		check_eq(loaded.to_dict(),rules.to_dict(),"new state loads without relocation")

func test_unmigratable_old_geometry_is_backed_up_and_does_not_lock_shop_entry() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_shops/states.json"))
	for source in [TEA,PANCAKE]:
		var shop: SpecShop = source.copy_for_editing()
		shop.layout.actor_areas.staff = []
		var path := "user://first-protected-%s-%d.json"%[shop.id,Time.get_ticks_usec()]
		paths.append(path)
		var original := JSON.stringify(fixtures[shop.id].active).to_utf8_buffer()
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
		var store := ShopSave.new(shop,path)
		var recovered := store.load_game()
		check_eq(store.load_error,OK,"spatial migration failure does not lock shop entry")
		check_eq(recovered.clock,0.0,"unrecoverable progress starts safe fresh business")
		check(not store.last_error.is_empty(),"recovery exposes a warning to the session")
		var backups: Array[String] = []
		for name in DirAccess.get_files_at("user://"):
			if name.begins_with(path.get_file()+".corrupt-"): backups.append("user://"+name)
		check_eq(backups.size(),1,"original is retained before fresh business starts")
		if not backups.is_empty(): check_eq(FileAccess.get_file_as_bytes(backups[0]),original,"recoverable original remains byte exact")
		check_eq(ShopSave.new(shop,path).load_game().clock,0.0,"repeated entry does not return to retry")

func test_legacy_position_can_adopt_a_legal_port_without_a_walkable_grid_center() -> void:
	var shop := _shop("handoff")
	shop.layout.cell = 40.0
	shop.layout.grid_size = Vector2i(2,1)
	shop.layout.areas = [Rect2i(0,0,2,1)]
	shop.layout.actor_areas = {"staff":[Rect2i(0,0,2,1)]}
	shop.layout.obstacles = [Rect2(0,0,25,40),Rect2(55,0,25,40)]
	shop.layout.obstacle_stations = ["",""]
	var rules := ShopRules.new(shop,42)
	var goal := Vector2(40,20)
	check(rules.nav.can_stand(goal),"current authored port accommodates whole footprint")
	check(not rules.nav.can_stand(Vector2(20,20)) and not rules.nav.can_stand(Vector2(60,20)),"grid centers cannot accommodate this narrow port")
	var actual: Vector2 = preload("res://game/rules/movement_adoption.gd")._nearest(rules,Vector2(-100,20),goal,"staff")
	check_eq(actual,goal,"legacy position falls back to a legal current port without discarding business")

func test_failed_migration_backup_retains_original_and_can_retry_after_repair() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_shops/states.json"))
	var shop := TEA.copy_for_editing()
	shop.layout.actor_areas.staff = []
	var path := "user://first-backup-retry-%d.json"%Time.get_ticks_usec()
	paths.append(path)
	var original := JSON.stringify(fixtures.tea.active).to_utf8_buffer()
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(original)
	file.close()
	var store := QuarantineFailure.new(shop,path)
	store.load_game()
	check_eq(store.load_error,ERR_CANT_CREATE,"backup failure blocks before adopting fresh business")
	check_eq(FileAccess.get_file_as_bytes(path),original,"failed backup cannot remove old progress")
	# Use valid fresh geometry so this checks the write seal, not state validation.
	store.shop = TEA
	check_eq(store.save_game(ShopRules.new(TEA)),ERR_UNAVAILABLE,"failed backup seals automatic writes")
	store.shop = shop
	store.fail_backup = false
	store.load_game()
	check_eq(store.load_error,OK,"explicit retry succeeds when backup can be retained")

func test_unreachable_actions_block_without_business_effects_and_resume_when_route_opens() -> void:
	for mode in ["handoff","single"]:
		var rules := _opened(mode)
		for tick in 300:
			rules.step(0.1)
			if rules.workers.any(func(row: Dictionary) -> bool: return row.get("action",{}).get("index",-1)==0): break
		var active: Array = rules.workers.filter(func(row: Dictionary) -> bool: return row.get("action",{}).get("index",-1)==0)
		check(not active.is_empty(),"real movement starts")
		if active.is_empty(): continue
		var worker: Dictionary = active[0]
		var pos: Vector2 = worker.pos
		var lease: Dictionary = worker.action.lease.duplicate(true)
		rules.shop.layout.obstacles = [Rect2(0,0,1280,1280)]
		rules.shop.layout.obstacle_stations = [""]
		rules.nav.set_open(rules.unlocked)
		rules.run(1.0)
		check_eq(worker.pos,pos,"unreachable route cannot move actor")
		check_eq(worker.action.status,"blocked","blocked movement exposes recoverable status")
		check_eq(worker.action.lease,lease,"route failure cannot consume or reassign goods")
		rules.shop.layout.obstacles.clear()
		rules.shop.layout.obstacle_stations.clear()
		rules.nav.set_open(rules.unlocked)
		rules.run(90.0)
		check(rules.sold>0,"reopened route continues original business")
