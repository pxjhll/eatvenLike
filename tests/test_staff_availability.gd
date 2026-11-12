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


func _legacy_tea() -> Dictionary:
	var rules := ShopRules.new(TEA)
	rules.unlock("lemonade")
	rules.run(23.0)
	rules.gold = 1234.0
	var state := rules.to_dict()
	state.roster[0].kind = "cat"
	state.roster[0].name = "Cat"
	var idle: Dictionary = ShopRules.new(TEA).to_dict().roster[0]
	for row in [[2, "raccoon", "Raccoon"], [3, "fox", "Fox"]]:
		var worker := idle.duplicate(true)
		worker.id = row[0]
		worker.kind = row[1]
		worker.name = row[2]
		worker.post = ""
		worker.deployed = false
		state.roster.append(worker)
	state._next_staff = 4
	state.hire_pool = ["cat", "raccoon", "fox", "rabbit", "gray_cat", "bear"]
	return state


func test_old_roster_migrates_without_losing_jobs_ids_or_progress() -> void:
	var state := _legacy_tea()
	var original := var_to_bytes(state)
	var restored := ShopRules.new(TEA)
	check_eq(restored.load_dict(state), "", "old roster remains loadable")
	check_eq(var_to_bytes(state), original, "migration does not mutate the caller's state")
	check_eq(restored.roster.map(func(w): return w.kind), ["gray_cat", "bear", "fox"], "retired kinds are replaced and fox identity is retained")
	check_eq(restored.roster.map(func(w): return w.name), ["小灰猫", "小熊", "Fox"], "legacy fox name remains its own")
	check_eq(restored.roster.slice(0, 2).map(func(w): return w.stats.walk), [112.0, 88.0], "replacement definitions supply current base stats")
	check_eq(restored.hire_pool, ["gray_cat", "bear", "fox", "rabbit"] as Array[String], "saved recruit pool is migrated and deduplicated")
	var after := restored.to_dict()
	for key in state:
		if key not in ["roster", "hire_pool"]: check_eq(after[key], state[key], "migration preserves " + key)
	for i in state.roster.size():
		for key in state.roster[i]:
			if key not in ["kind", "name", "stats"]: check_eq(after.roster[i][key], state.roster[i][key], "worker preserves " + key)
	var copy := ShopRules.new(TEA)
	check_eq(copy.load_dict(after), "", "migrated roster reloads")
	restored.run(5.0)
	copy.run(5.0)
	check_eq(var_to_bytes(restored.to_dict()), var_to_bytes(copy.to_dict()), "active work resumes deterministically")


func test_v1_and_v2_save_files_migrate_and_keep_original_backup() -> void:
	for version in [1, 2]:
		var path := "user://staff-availability-%d-%d.json" % [OS.get_process_id(), version]
		paths.append(path)
		var bytes := var_to_bytes(_legacy_tea())
		var wrapper := {"format": ShopSave.FORMAT, "version": version, "shop": TEA.id, "speed": 2.0,
			"guides": ["welcome"], "state": Marshalls.raw_to_base64(bytes), "state_sha256": bytes.hex_encode().sha256_text()}
		if version == 2: wrapper.content = {"version": 1, "gameplay": "a".repeat(64), "structure": "b".repeat(64)}
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(wrapper))
		file.close()
		var original := FileAccess.get_file_as_bytes(path)
		var store := ShopSave.new(TEA, path)
		var rules := store.load_game()
		check_eq(store.last_error, "", "legacy file loads without starting over")
		check_eq(rules.gold, 1234.0, "gold retained")
		check_eq(rules.roster.map(func(w): return w.kind), ["gray_cat", "bear", "fox"], "file roster retains restored fox")
		check("fox" in rules.hire_pool and "parrot" in rules.hire_pool, "updated save can recruit both newly available employees")
		check_eq(store.loaded_speed, 2.0, "speed retained")
		check_eq(store.loaded_guides, ["welcome"], "guide progress retained")
		check(FileAccess.get_file_as_bytes(path) == original, "loading leaves original file untouched")
		check_eq(store.save_game(rules, 2.0, store.loaded_guides), OK, "migrated save can be written")
		var backup_found := false
		for saved in DirAccess.get_files_at("user://"):
			if saved.begins_with(path.get_file() + ".pre-content-"):
				backup_found = FileAccess.get_file_as_bytes("user://" + saved) == original
		check(backup_found, "original save is backed up before replacement")
		var again := ShopSave.new(TEA, path).load_game()
		check_eq(var_to_bytes(again.to_dict()), var_to_bytes(rules.to_dict()), "migrated file reload is stable")


func test_stirfry_old_front_and_customer_employees_keep_their_work() -> void:
	var rules := ShopRules.new(STIRFRY)
	rules.unlock("wok_a")
	rules.run(43.0)
	var state := rules.to_dict()
	state.roster[1].kind = "cat"
	state.roster[1].name = "三花猫"
	var idle: Dictionary = ShopRules.new(STIRFRY).to_dict().roster[0]
	for row in [[3, "dog", "小狗"], [4, "sheep", "小羊"]]:
		var worker := idle.duplicate(true)
		worker.id = row[0]
		worker.kind = row[1]
		worker.name = row[2]
		worker.deployed = false
		state.roster.append(worker)
	state._next_staff = 5
	state.hire_pool = ["rabbit", "bear", "dog", "sheep"]
	var migrated := ShopRules.new(STIRFRY)
	check_eq(migrated.load_dict(state), "", "serve-mode old roster can resume")
	check_eq(migrated.roster.map(func(w): return w.kind), ["gray_cat", "rabbit", "gray_cat", "bear"], "customer employees leave the roster")
	check_eq(migrated.worker_by_id(2).post, "counter", "front post stays assigned to the same worker")
	check_eq(migrated.hire_pool, ["rabbit", "bear", "gray_cat"] as Array[String], "customer kinds leave the saved recruit pool")
	var after := migrated.to_dict()
	for key in state:
		if key not in ["roster", "hire_pool"]: check_eq(after[key], state[key], "serve migration preserves " + key)
	for i in state.roster.size():
		for key in state.roster[i]:
			if key not in ["kind", "name", "stats"]: check_eq(after.roster[i][key], state.roster[i][key], "serve worker preserves " + key)
	var copy := ShopRules.new(STIRFRY)
	check_eq(copy.load_dict(after), "", "migrated serve roster reloads")
	migrated.run(10.0)
	copy.run(10.0)
	check_eq(var_to_bytes(migrated.to_dict()), var_to_bytes(copy.to_dict()), "serve jobs resume deterministically")


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
		state.hire_pool = ["rabbit", "gray_cat", "bear"]
		var rules := ShopRules.new(shop)
		check_eq(rules.load_dict(state, true), "", shop.id + " refreshes older three-species save")
		check("fox" in rules.hire_pool and "parrot" in rules.hire_pool, shop.id + " makes the new staff available after load")


func test_each_shop_registers_all_five_employee_kinds() -> void:
	for shop: SpecShop in [TEA, PANCAKE, STIRFRY]:
		for id in ACTIVE:
			check(shop.staff.kinds.any(func(kind): return kind.id == id), shop.id + " defines " + id)
			check(id in shop.staff.hire_pool, shop.id + " offers " + id)
			check(not shop.staff.retired_kinds.has(id), shop.id + " does not retire " + id)
