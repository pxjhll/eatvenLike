extends "res://tests/test_case.gd"

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const STIRFRY: SpecShop = preload("res://content/shops/stirfry/shop.tres")
const Library := preload("res://presentation/characters/character_library.gd")
const Validator := preload("res://game/rules/shop_spec_validator.gd")
const ACTIVE := ["rabbit", "gray_cat", "bear", "fox", "parrot"]
var paths: Array[String] = []


func cleanup() -> void:
	for path in paths:
		for file in DirAccess.get_files_at("user://"):
			if file.begins_with(path.get_file()): DirAccess.remove_absolute("user://" + file)


func test_new_shops_and_repeated_recruitment_only_offer_active_staff() -> void:
	for shop: SpecShop in [TEA, PANCAKE, STIRFRY]:
		check(Validator.validate(shop).is_empty(), shop.id + " content is valid")
		var rules := ShopRules.new(shop)
		check_eq(rules.roster.size(), 2 if shop == STIRFRY else 1, shop.id + " starter count retained")
		check_eq(rules.post_owner(rules.counter_id) > 0, shop != PANCAKE, shop.id + " opening front post retained")
		for worker in rules.roster: check(worker.kind in ACTIVE, shop.id + " starter has animation")
		rules.gold = 1000000.0
		if shop == PANCAKE:
			rules.unlock("soy_milk")
			rules.stage_index = shop.stages.size() - 1
		for unused in 8:
			if rules.command_status("hire").code != "ok": break
			check(rules.next_hire_kind() in ACTIVE, shop.id + " next recruit is active")
			check_eq(rules.hire(), "", shop.id + " recruitment succeeds")
		for worker in rules.roster: check(worker.kind in ACTIVE, shop.id + " no archived or customer employee")


func test_customer_rotation_and_archived_art_remain_available() -> void:
	check_eq(Library.STAFF_IDS, ACTIVE, "employee preview grouping contains active staff")
	for row in [[1, "squirrel"], [2, "dog"], [3, "sheep"], [4, "hamster"], [5, "squirrel"]]:
		check_eq(Library.customer_art(row[0]), row[1], "customer appearance rotation is preserved")
	for id in ["cat", "raccoon"]:
		check(Library.portrait(id) != null and not Library.actions(id).is_empty(), id + " archived art is still previewable")


func test_old_unlock_effect_cannot_reintroduce_retired_staff() -> void:
	for shop: SpecShop in [TEA, STIRFRY]:
		var rules := ShopRules.new(shop)
		var before: Array = rules.hire_pool.duplicate()
		for id in ["cat", "raccoon", "dog", "sheep", "unknown"]:
			rules.apply_effect("event", "old_manager", SpecEffect.make("unlock_staff_kind", "add", 1.0, id))
		check_eq(rules.hire_pool, before, shop.id + " retired or unknown unlock is ignored")


func test_retired_staff_cannot_be_reenabled_in_shop_configuration() -> void:
	for field in ["starting", "hire_pool", "hire_order"]:
		var shop: SpecShop = TEA.duplicate(true)
		shop.staff.get(field).append("cat")
		check("Retired staff" in Validator.summary(Validator.validate(shop)), field + " rejects archived staff")


func _frozen_legacy(shop_id: String) -> Dictionary:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/runtime_legacy/"+shop_id+".json"))
	return bytes_to_var(Marshalls.base64_to_raw(fixture.states["899"]))


# Build a real public v2 session using the historical staff configuration.
# The public Runtime owns every active program, clock and physical item.
func _historical_public(shop: SpecShop) -> ShopRules:
	var previous := shop.copy_for_editing()
	previous.staff.retired_kinds.clear()
	var kinds: Array[String] = []
	for id in shop.staff.retired_kinds: kinds.append(id)
	kinds.append("fox")
	previous.staff.starting.assign(kinds)
	previous.staff.starting_posts.clear()
	for index in kinds.size(): previous.staff.starting_posts.append("counter" if index==0 else "")
	previous.staff.hire_pool.assign(kinds)
	var owner := ShopRules.new(previous,42)
	check_eq(owner.recall_worker(owner.roster.back().id),"","historical fox can remain on standby")
	owner.gold = 1234.0
	check_eq(owner.unlock("lemonade" if shop==TEA else "wok_a"),"","open historical public production")
	owner.run(23.0)
	check_eq(owner.runtime_error,"","historical public session runs")
	return owner


func _check_identities(owner: ShopRules, before: Array, refresh := false) -> void:
	check_eq(owner.roster.size(),before.size(),owner.shop.id+": keep every employee")
	for worker in before:
		var after := owner.worker_by_id(worker.id)
		check(not after.is_empty(),"keep stable worker id "+str(worker.id))
		if after.is_empty(): continue
		var replacement: String = owner.shop.staff.retired_kinds.get(worker.kind,worker.kind)
		check_eq(after.kind,replacement,"declared species replacement for "+worker.kind)
		var changed: bool = replacement!=worker.kind
		check_eq(after.name,owner._kind(replacement).display_name if changed else worker.name,"retired name is replaced; active name is retained")
		check_eq(after.stats,owner._kind(replacement).stats if changed or refresh else worker.stats,"replacement receives current global stats")
		for key in ["id","post","deployed","source","fatigue"]:
			check_eq(after[key],worker[key],"employee retains "+key)
		if not worker.deployed or worker.has("pos"):
			var physical: Dictionary = worker.get("standby",worker)
			check_eq(after.pos,physical.pos,"employee position is retained")
			check_eq(after.completed,physical.completed,"completed work is retained")
	for worker in owner.workers:
		check(is_same(worker,owner.worker_by_id(worker.id)),"active worker references the adopted roster object")


func _check_legacy_progress(owner: ShopRules, before: Dictionary) -> void:
	var after := owner.to_dict()
	check_eq(after.version,2,"historical format is adopted by the public protocol")
	for key in ["gold","revenue","sold","sold_by_dish","stage_index","unlocked","levels","boxes","completed_at","seats","_next_staff","rng","event_rng","_sale_carry"]:
		check_eq(after.outer[key],before[key],owner.shop.id+": migration preserves "+key)
	check_eq(after.runtime.clock,before.clock,"migration retains the simulation clock")
	check_eq(owner.runtime.runner.inventory.audit(),[],"converted inventory is conserved")


func _check_resumes(owner: ShopRules) -> void:
	var saved := owner.to_dict()
	var copy := ShopRules.new(owner.shop)
	check_eq(copy.load_dict(saved),"","migrated public state reloads strictly")
	owner.run(5.0)
	copy.run(5.0)
	check_eq(owner.runtime_error,"","migrated work resumes")
	check_eq(copy.runtime_error,"","reloaded work resumes")
	check_eq(var_to_bytes(owner.to_dict()),var_to_bytes(copy.to_dict()),"active work and RNG resume deterministically")


func test_frozen_old_rosters_migrate_without_losing_ids_posts_business_or_clocks() -> void:
	for shop: SpecShop in [TEA,PANCAKE,STIRFRY]:
		var state := _frozen_legacy(shop.id)
		var original := var_to_bytes(state)
		var owner := ShopRules.new(shop)
		var error := owner.load_dict(state,true)
		check_eq(error,"",shop.id+": frozen historical save remains loadable")
		if not error.is_empty(): continue
		check_eq(var_to_bytes(state),original,"migration does not mutate the caller's historical state")
		_check_identities(owner,state.roster,true)
		_check_legacy_progress(owner,state)
		for id in owner.hire_pool: check(id in ACTIVE,"migrated recruitment only contains active species")
		check("fox" in owner.hire_pool and "parrot" in owner.hire_pool,"content refresh adds the new recruitment choices")
		_check_resumes(owner)


func test_old_public_rosters_migrate_only_identity_and_keep_active_runtime_exact() -> void:
	for shop: SpecShop in [TEA,STIRFRY]:
		var previous := _historical_public(shop)
		var state := previous.to_dict()
		check_eq(state.version,2,"historical staff use a genuine public v2 snapshot")
		var original := var_to_bytes(state)
		var owner := ShopRules.new(shop)
		var error := owner.load_dict(state)
		check_eq(error,"",shop.id+": retired public roster restores")
		if not error.is_empty(): continue
		check_eq(var_to_bytes(state),original,"public migration leaves caller data untouched")
		_check_identities(owner,state.outer.roster)
		var after := owner.to_dict()
		check_eq(after.runtime,state.runtime,"identity migration preserves every active program, physical item and runtime clock")
		for key in state.outer:
			if key not in ["roster","hire_pool"]: check_eq(after.outer[key],state.outer[key],"public migration preserves "+key)
		var expected_pool := []
		for id in state.outer.hire_pool:
			var replacement: String = shop.staff.retired_kinds.get(id,id)
			if replacement not in expected_pool: expected_pool.append(replacement)
		check_eq(after.outer.hire_pool,expected_pool,"strict restore only migrates and deduplicates saved recruitment")
		check("parrot" not in after.outer.hire_pool,"strict restore does not introduce new recruitment")
		_check_resumes(owner)


func test_v1_legacy_and_v2_public_save_files_migrate_and_keep_original_backup() -> void:
	for version in [1,2]:
		var historical := _historical_public(TEA)
		var state: Dictionary = _frozen_legacy("tea") if version==1 else historical.to_dict()
		var path := "user://staff-availability-%d-%d.json" % [OS.get_process_id(),version]
		paths.append(path)
		var bytes := var_to_bytes(state)
		var wrapper := {"format":ShopSave.FORMAT,"version":version,"shop":TEA.id,"speed":2.0,
			"guides":["welcome"],"state":Marshalls.raw_to_base64(bytes),"state_sha256":bytes.hex_encode().sha256_text()}
		if version==2: wrapper.content = preload("res://game/rules/shop_content_contract.gd").describe(historical.shop)
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(wrapper)); file.close()
		var original := FileAccess.get_file_as_bytes(path)
		var store := ShopSave.new(TEA,path)
		var owner := store.load_game()
		check_eq(store.last_error,"","historical file loads without starting over")
		check_eq(store.load_error,OK,"historical file migration succeeds")
		if store.load_error!=OK: continue
		check_eq(owner.gold,state.gold if version==1 else state.outer.gold,"saved gold retained")
		check("fox" in owner.hire_pool and "parrot" in owner.hire_pool,"numeric content refresh enables newly available employees")
		check_eq(store.loaded_speed,2.0,"speed retained")
		check_eq(store.loaded_guides,["welcome"],"guide progress retained")
		check_eq(FileAccess.get_file_as_bytes(path),original,"loading leaves original file untouched")
		check_eq(store.save_game(owner,2.0,store.loaded_guides),OK,"migrated save can be written")
		var backup_found := false
		for saved in DirAccess.get_files_at("user://"):
			if saved.begins_with(path.get_file()+".pre-content-"):
				backup_found = FileAccess.get_file_as_bytes("user://"+saved)==original
		check(backup_found,"original save is backed up before replacement")
		var again_store := ShopSave.new(TEA,path)
		var again := again_store.load_game()
		check_eq(again_store.load_error,OK,"migrated file loads normally")
		check_eq(var_to_bytes(again.to_dict()),var_to_bytes(owner.to_dict()),"migrated file reload is stable")


func test_all_five_employees_have_three_actions_and_thirteen_authored_views() -> void:
	for id in ACTIVE:
		check(Library.FRAME_ASSETS.has(id), id + " has animated resources")
		if not Library.FRAME_ASSETS.has(id): continue
		var frames: SpriteFrames = Library.FRAME_ASSETS[id]
		check_eq(Library.actions(id).map(func(a): return a.id), ["walk", "idle", "work"], id + " exposes exactly three actions")
		for action in ["walk", "idle", "work"]:
			var views := ["front", "right", "back_right"] if action == "work" else ["front", "front_right", "right", "back_right", "back"]
			for view in views:
				var clip: String = action + "_" + view
				check(frames.has_animation(clip), id + " has " + clip)


func test_existing_three_species_saves_gain_new_recruitment_choices() -> void:
	for shop: SpecShop in [TEA, PANCAKE, STIRFRY]:
		var state := ShopRules.new(shop).to_dict()
		state.outer.hire_pool = ["rabbit", "gray_cat", "bear"]
		var strict := ShopRules.new(shop)
		check_eq(strict.load_dict(state), "", shop.id + " strictly restores the recorded pool")
		check_eq(strict.hire_pool, ["rabbit", "gray_cat", "bear"] as Array[String], shop.id + " strict load preserves recruitment")
		var rules := ShopRules.new(shop)
		check_eq(rules.load_dict(state, true), "", shop.id + " refreshes older three-species save")
		check("fox" in rules.hire_pool and "parrot" in rules.hire_pool, shop.id + " makes the new staff available after load")


func test_each_shop_registers_all_five_employee_kinds() -> void:
	for shop: SpecShop in [TEA, PANCAKE, STIRFRY]:
		for id in ACTIVE:
			check(shop.staff.kinds.any(func(kind): return kind.id == id), shop.id + " defines " + id)
			check(id in shop.staff.hire_pool, shop.id + " offers " + id)
			check(not shop.staff.retired_kinds.has(id), shop.id + " does not retire " + id)

func test_nonempty_retirement_policy_changes_content_fingerprints() -> void:
	var contract := preload("res://game/rules/shop_content_contract.gd")
	var shop := TEA.copy_for_editing()
	var current: Dictionary = contract.describe(shop)
	shop.staff.retired_kinds.clear()
	var empty: Dictionary = contract.describe(shop)
	check(current.gameplay!=empty.gameplay,"actual retirement policy participates in gameplay identity")
	check(current.structure!=empty.structure,"actual retirement policy participates in structural identity")
	shop.staff.retired_kinds["cat"] = "rabbit"
	var changed: Dictionary = contract.describe(shop)
	check(changed.gameplay!=current.gameplay,"replacement changes cannot masquerade as the same policy")


func test_tea_hire_order_prices_and_roster_without_limit() -> void:
	var rules := ShopRules.new(TEA)
	var expected := [[35, "bear", 2], [60, "rabbit", 3], [85, "fox", 4], [110, "parrot", 5], [135, "gray_cat", 6], [160, "bear", 7]]
	for row in expected:
		check_eq(rules.hire_cost(), row[0], "recruitment prices retain their progression")
		check_eq(rules.next_hire_kind(), row[1], "five-species recruitment order")
		rules.gold = float(row[0]) - 1.0
		var before := rules.to_dict()
		check(rules.hire() != "", "insufficient funds reject recruitment")
		check_eq(rules.to_dict(), before, "failed recruitment is read-only")
		rules.gold = float(row[0])
		check_eq(rules.hire(), "", "recruitment succeeds at the exact price")
		check_eq(rules.gold, 0.0, "recruitment charges the full price")
		check_eq(rules.worker_by_id(row[2]).kind, row[1], "each recruit keeps a unique worker ID")
	check_eq(rules.workers.size(), 1, "recruits enter the roster before deployment")
	check_eq(rules.worker_by_id(4).name, "Fox", "restored fox retains its own identity")
	check_eq(rules.worker_by_id(5).name, "小鹦鹉", "parrot has its own identity")
	check_eq(rules.next_hire_kind(), "rabbit", "fewest-species recruitment repeats without an identity collision")
	var copy := ShopRules.new(TEA)
	check_eq(copy.load_dict(rules.to_dict()), "", "five-species roster saves and reloads")
