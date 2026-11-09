extends "res://tests/test_case.gd"

const TEA = preload("res://content/shops/tea/shop.tres")
const CONTRACT = preload("res://game/rules/shop_content_contract.gd")
const SESSION = preload("res://game/app/shop_session.gd")
const Profile = preload("res://game/app/profile.gd")
const SpecValidator = preload("res://game/rules/shop_spec_validator.gd")
var paths: Array[String] = []

class BackupFailure extends ShopSave:
	var fail_backup := true
	func _backup_before_content_update() -> Error:
		return ERR_CANT_CREATE if fail_backup else super._backup_before_content_update()

func _path() -> String:
	var path := "user://content-save-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	paths.append(path)
	return path

func cleanup() -> void:
	for path in paths:
		for file in DirAccess.get_files_at(path.get_base_dir()):
			if file.begins_with(path.get_file()): DirAccess.remove_absolute(path.get_base_dir().path_join(file))

func _write(path: String, data: Dictionary, metadata: Dictionary = {}, version := 2) -> PackedByteArray:
	var bytes := var_to_bytes(data)
	var payload := {"format": ShopSave.FORMAT, "version": version, "shop": TEA.id, "speed": 2.0,
		"guides": ["opening"], "state": Marshalls.raw_to_base64(bytes), "state_sha256": bytes.hex_encode().sha256_text()}
	if not metadata.is_empty(): payload.content = metadata
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	return FileAccess.get_file_as_bytes(path)

func _backups(path: String) -> Array[String]:
	var result: Array[String] = []
	for file in DirAccess.get_files_at(path.get_base_dir()):
		if file.begins_with(path.get_file() + ".pre-content-"): result.append(path.get_base_dir().path_join(file))
	return result

func _with_optional_progress(mode: String) -> SpecShop:
	var spec: SpecShop = TEA.duplicate(true)
	if mode == "material":
		var material := SpecMaterial.new()
		material.id = "retired_material"
		material.item = "tea_leaf"
		material.track = SpecUpgradeTrack.new()
		material.track.id = "retired_material"
		var level := SpecUpgradeLevel.new()
		level.cost = 1
		material.track.levels.append(level)
		spec.station("supply").materials.append(material)
	elif mode == "station":
		var station := SpecStation.new()
		station.id = "retired_station"
		station.block = "dispenser"
		station.companion_of = "lemonade"
		spec.stations.append(station)
		spec.layout.points[station.id] = spec.layout.points.lemonade
	return spec

func test_legacy_removed_recorded_ids_protect_original_and_block_start_and_writes() -> void:
	for mode in ["staff", "material", "station"]:
		var old_spec := _with_optional_progress(mode)
		var changed: SpecShop = TEA.duplicate(true)
		if mode == "staff": changed.staff.tracks.remove_at(0)
		check(SpecValidator.validate(old_spec, Profile.CAMPAIGN).is_empty(), mode + " original content valid")
		check(SpecValidator.validate(changed, Profile.CAMPAIGN).is_empty(), mode + " changed content valid")
		var old := ShopRules.new(old_spec)
		old.unlock("lemonade")
		old.gold = 100000.0
		var key := "staff/front" if mode == "staff" else "supply/retired_material"
		if mode == "station": check(old.station_unlocked("retired_station"), "removed station was unlocked")
		else: check_eq(old.upgrade(key), "", mode + " track purchased")
		var data := old.to_dict()
		# The raw API intentionally keeps its permissive add/remove merge contract.
		var raw := ShopRules.new(changed)
		check_eq(raw.load_dict(data), "", mode + " raw restore still allows removed ID")
		check(not raw.unlocked.has("retired_station") if mode == "station" else not raw.levels.has(key), mode + " raw merge omits removed ID")
		var path := _path()
		var original := _write(path, data, {}, 1)
		var store := ShopSave.new(changed, path)
		check_eq(store.save_game(ShopRules.new(changed)), ERR_UNAVAILABLE, mode + " direct save blocked")
		store.load_game()
		check_eq(store.load_error, ERR_UNAVAILABLE, mode + " load protected")
		var profile := Profile.new(_path())
		profile.shop = "tea"
		var session := SESSION.new(profile, store)
		check_eq(session.start(), ERR_UNAVAILABLE, mode + " startup blocked")
		check(session.rules == null and not session.started, mode + " no playable candidate")
		check_eq(session.save(), ERR_UNAVAILABLE, mode + " session save blocked")
		var fresh_profile := Profile.new(_path())
		check_eq(fresh_profile.finish_shop({"shop": "pancake"}), OK, mode + " fresh marker seeded")
		var profile_bytes := FileAccess.get_file_as_bytes(fresh_profile.path)
		var fresh := SESSION.new(fresh_profile, ShopSave.new(changed, path))
		check_eq(fresh.start(), ERR_UNAVAILABLE, mode + " fresh save blocked")
		check(fresh_profile.fresh_shop and fresh.rules == null, mode + " fresh marker retained")
		check(FileAccess.get_file_as_bytes(fresh_profile.path) == profile_bytes, mode + " profile unchanged")
		check(FileAccess.get_file_as_bytes(path) == original, mode + " exact original retained")
		check_eq(_backups(path).size(), 0, mode + " no migration backup")

func test_legacy_safe_additions_get_defaults_and_keep_recorded_ids() -> void:
	for mode in ["material", "station"]:
		var path := _path()
		var old := ShopRules.new(TEA)
		old.gold = 4321.0
		var data := old.to_dict()
		var original := _write(path, data, {}, 1)
		var changed := _with_optional_progress(mode)
		var store := ShopSave.new(changed, path)
		var resumed := store.load_game()
		check_eq(store.load_error, OK, mode + " safe addition loads")
		check_eq(resumed.gold, 4321.0, mode + " progress retained")
		for map in ShopRules.BY_DATA_ID:
			for id in data[map]: check(resumed.to_dict()[map].has(id), mode + " recorded ID retained: " + map + "." + str(id))
		if mode == "material": check_eq(resumed.levels["supply/retired_material"], 1, "new material gets default level")
		else: check_eq(resumed.unlocked.retired_station, false, "new station gets locked default")
		check_eq(store.save_game(resumed), OK, mode + " safe addition saves")
		var backups := _backups(path)
		check_eq(backups.size(), 1, mode + " migration backed up")
		if not backups.is_empty(): check(FileAccess.get_file_as_bytes(backups[0]) == original, mode + " exact original backed up")

func test_legacy_malformed_id_maps_remain_protected_without_runtime_errors() -> void:
	for map in ShopRules.BY_DATA_ID:
		for malformed in [null, [], 7, {7: true}]:
			var path := _path()
			var data := ShopRules.new(TEA).to_dict()
			data[map] = malformed
			var original := _write(path, data, {}, 1)
			var store := ShopSave.new(TEA, path)
			store.load_game()
			check_eq(store.load_error, ERR_UNAVAILABLE, map + " malformed legacy protected")
			check_eq(store.save_game(ShopRules.new(TEA)), ERR_UNAVAILABLE, map + " malformed legacy blocks save")
			check(FileAccess.get_file_as_bytes(path) == original, map + " malformed original retained")

func test_delete_reassesses_and_retains_protected_or_unreadable_files() -> void:
	for mode in ["future", "structure", "unreadable"]:
		var path := _path()
		var store := ShopSave.new(TEA, path)
		check_eq(store.save_game(ShopRules.new(TEA)), OK, mode + " seed compatible save")
		var metadata := CONTRACT.describe(TEA)
		if mode == "structure": metadata.structure = "a".repeat(64)
		_write(path, ShopRules.new(TEA).to_dict(), metadata, 99 if mode == "future" else 2)
		if mode == "unreadable":
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string("{unreadable-replacement")
			file.close()
		var original := FileAccess.get_file_as_bytes(path)
		store.delete()
		check(FileAccess.file_exists(path), mode + " delete retains replacement")
		if FileAccess.file_exists(path): check(FileAccess.get_file_as_bytes(path) == original, mode + " delete keeps exact bytes")

func test_legacy_refresh_is_read_only_until_exact_backup_and_save() -> void:
	var path := _path()
	var old := ShopRules.new(TEA)
	old.unlock(old.next_unlock())
	old.run(12.0)
	var original := _write(path, old.to_dict(), {}, 1)
	var updated: SpecShop = TEA.duplicate(true)
	updated.staff.kinds[0].stats.speed = 19.0
	updated.stations[0].params.capacity = 81
	updated.dishes[0].price_parts[updated.dishes[0].price_parts.keys()[0]] += 100.0
	var store := ShopSave.new(updated, path)
	var resumed := store.load_game()
	check_eq(resumed.roster[0].stats, updated.staff.kinds[0].stats, "legacy refresh uses current staff")
	check_eq(resumed.stations[updated.stations[0].id].capacity, 81, "legacy refresh uses current capacity")
	check_eq(resumed.gold, old.gold, "gold retained")
	check(resumed.dish_price(updated.dishes[0].id) != old.dish_price(TEA.dishes[0].id), "current numeric price adopted")
	check_eq(store.loaded_speed, 2.0, "speed retained")
	check_eq(store.loaded_guides, ["opening"], "guides retained")
	check_eq(FileAccess.get_file_as_bytes(path), original, "load is read only")
	check_eq(_backups(path).size(), 0, "load creates no backup")
	check_eq(store.save_game(resumed), OK, "migration saves")
	var backups := _backups(path)
	check_eq(backups.size(), 1, "migration makes one backup")
	if not backups.is_empty(): check_eq(FileAccess.get_file_as_bytes(backups[0]), original, "backup is original bytes")
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check_eq(int(payload.version), 2, "writes wrapper v2")
	var expected_metadata := CONTRACT.describe(updated)
	check_eq(int(payload.content.version), expected_metadata.version, "writes current metadata version")
	check_eq(payload.content.gameplay, expected_metadata.gameplay, "writes current gameplay hash")
	check_eq(payload.content.structure, expected_metadata.structure, "writes current structure hash")

func test_numeric_update_preserves_recorded_state_and_same_content_is_exact() -> void:
	var path := _path()
	var old := ShopRules.new(TEA)
	old.unlock(old.next_unlock())
	old.run(23.0)
	var saved := old.to_dict()
	var original := _write(path, saved, CONTRACT.describe(TEA))
	var same := ShopSave.new(TEA, path).load_game()
	check_eq(var_to_bytes(same.to_dict()), var_to_bytes(saved), "same content exact state")
	var updated: SpecShop = TEA.duplicate(true)
	updated.staff.kinds[0].stats.speed = 19.0
	updated.stations[0].params.capacity = 81
	for station in updated.stations:
		for track in station.tracks:
			for effect in track.base_effects: effect.value += 2.0
	var expected := ShopRules.new(updated)
	check_eq(expected.load_dict(saved, true), "", "candidate is valid")
	var store := ShopSave.new(updated, path)
	var resumed := store.load_game()
	check_eq(var_to_bytes(resumed.to_dict()), var_to_bytes(expected.to_dict()), "numeric update refreshes exactly")
	check_eq(FileAccess.get_file_as_bytes(path), original, "numeric load read only")
	check_eq(store.save_game(resumed), OK, "numeric update save")
	check_eq(_backups(path).size(), 1, "numeric backup")
	check_eq(store.save_game(resumed), OK, "same metadata save")
	check_eq(_backups(path).size(), 1, "no repeated migration backup")

func test_incompatible_legacy_structure_and_future_protect_direct_save() -> void:
	for mode in ["legacy", "structure", "future_wrapper", "future_content", "changed_invalid"]:
		var path := _path()
		var data := ShopRules.new(TEA).to_dict()
		var metadata := CONTRACT.describe(TEA)
		var version := 2
		if mode == "legacy":
			version = 1
			metadata = {}
			data.rng = []
		elif mode == "structure": metadata.structure = "a".repeat(64)
		elif mode == "future_wrapper": version = 99
		elif mode == "future_content": metadata.version = 99
		else:
			metadata.gameplay = "b".repeat(64)
			data.rng = []
		var original := _write(path, data, metadata, version)
		var store := ShopSave.new(TEA, path)
		check_eq(store.save_game(ShopRules.new(TEA)), ERR_UNAVAILABLE, mode + " direct save blocked")
		store.load_game()
		check_eq(store.get("load_error"), ERR_UNAVAILABLE, mode + " load blocked")
		check_eq(FileAccess.get_file_as_bytes(path), original, mode + " original retained")
		check_eq(_backups(path).size(), 0, mode + " no migration backup")

func test_external_replacement_is_reassessed_and_explicit_retry_reloads() -> void:
	var path := _path()
	var data := ShopRules.new(TEA).to_dict()
	data.gold = 4321.0
	_write(path, data, CONTRACT.describe(TEA))
	var store := ShopSave.new(TEA, path)
	var live := store.load_game()
	var metadata := CONTRACT.describe(TEA)
	metadata.structure = "a".repeat(64)
	var original := _write(path, data, metadata)
	check_eq(store.save_game(live), ERR_UNAVAILABLE, "external replacement assessed")
	var profile := Profile.new(_path())
	profile.shop = "tea"
	var session := SESSION.new(profile, store)
	check_eq(session.start(), ERR_UNAVAILABLE, "incompatible startup blocked")
	check(session.rules == null and not session.started, "failed start no rules")
	check(session.save() != OK, "failed start cannot save")
	check_eq(FileAccess.get_file_as_bytes(path), original, "blocked start retained")
	_write(path, data, CONTRACT.describe(TEA))
	check_eq(session.start(), OK, "same session retries repaired file")
	check_eq(session.rules.gold, 4321.0, "retry actually reloads")
	check_eq(store.get("load_error"), OK, "retry clears load error")
	check_eq(session.save(), OK, "retry clears write protection")

func test_backup_and_atomic_write_failure_allow_repair_retry() -> void:
	var path := _path()
	var data := ShopRules.new(TEA).to_dict()
	var original := _write(path, data, {}, 1)
	var store := BackupFailure.new(TEA, path)
	var resumed := store.load_game()
	check_eq(store.save_game(resumed), ERR_CANT_CREATE, "backup failure returned")
	check_eq(FileAccess.get_file_as_bytes(path), original, "backup failure retains original")
	store.fail_backup = false
	# A directory at the atomic temp path makes the real SaveService fail.
	DirAccess.make_dir_absolute(path + ".tmp")
	check(store.save_game(resumed) != OK, "atomic write failure returned")
	check_eq(FileAccess.get_file_as_bytes(path), original, "atomic failure retains original")
	var backups := _backups(path)
	check_eq(backups.size(), 1, "failed atomic write still retains migration backup")
	if not backups.is_empty(): check(FileAccess.get_file_as_bytes(backups[0]) == original, "failed-write backup exact")
	DirAccess.remove_absolute(path + ".tmp")
	check_eq(store.save_game(resumed), OK, "save retries after repair")

func test_fresh_intent_does_not_acknowledge_incompatible_shop() -> void:
	var profile := Profile.new(_path())
	check_eq(profile.finish_shop({"shop": "pancake"}), OK, "fresh tea marker")
	var before := FileAccess.get_file_as_bytes(profile.path)
	var path := _path()
	var metadata := CONTRACT.describe(TEA)
	metadata.structure = "a".repeat(64)
	var original := _write(path, ShopRules.new(TEA).to_dict(), metadata)
	var session := SESSION.new(profile, ShopSave.new(TEA, path))
	check_eq(session.start(), ERR_UNAVAILABLE, "fresh intent blocked")
	check(session.rules == null and profile.fresh_shop, "fresh intent retained")
	check_eq(FileAccess.get_file_as_bytes(path), original, "fresh intent preserves shop")
	check_eq(FileAccess.get_file_as_bytes(profile.path), before, "fresh intent preserves profile")

func test_renamed_shop_with_shared_save_path_is_protected() -> void:
	var path := _path()
	var data := ShopRules.new(TEA).to_dict()
	var original := _write(path, data, CONTRACT.describe(TEA))
	var renamed: SpecShop = TEA.duplicate(true)
	renamed.id = "renamed_tea"
	var store := ShopSave.new(renamed, path)
	check_eq(store.save_game(ShopRules.new(renamed)), ERR_UNAVAILABLE, "renamed shop direct save blocked")
	store.load_game()
	check_eq(store.get("load_error"), ERR_UNAVAILABLE, "renamed shop load blocked")
	check(FileAccess.get_file_as_bytes(path) == original, "renamed shop preserves original")

func test_outgoing_content_and_invalid_state_cannot_be_mislabeled() -> void:
	var path := _path()
	var store := ShopSave.new(TEA, path)
	var different: SpecShop = TEA.duplicate(true)
	different.staff.kinds[0].stats.work = 12.0
	check_eq(store.save_game(ShopRules.new(different)), ERR_INVALID_PARAMETER, "different gameplay rejected")
	check(not store.exists(), "mismatched rules do no IO")
	var copy: SpecShop = TEA.duplicate(true)
	check_eq(store.save_game(ShopRules.new(copy)), OK, "equivalent resource accepted")
	var original := FileAccess.get_file_as_bytes(path)
	var invalid := ShopRules.new(TEA)
	invalid.gold = -1.0
	check_eq(store.save_game(invalid), ERR_INVALID_DATA, "invalid outgoing state rejected")
	check(FileAccess.get_file_as_bytes(path) == original, "invalid state preserves original")

func test_real_topology_and_level_count_changes_block() -> void:
	for mode in ["geometry", "levels"]:
		var path := _path()
		var original := _write(path, ShopRules.new(TEA).to_dict(), CONTRACT.describe(TEA))
		var changed: SpecShop = TEA.duplicate(true)
		if mode == "geometry": changed.layout.points[changed.layout.points.keys()[0]] += Vector2(1, 0)
		else:
			for station in changed.stations:
				if not station.tracks.is_empty() and not station.tracks[0].levels.is_empty():
					station.tracks[0].levels.pop_back()
					break
		var store := ShopSave.new(changed, path)
		store.load_game()
		check_eq(store.get("load_error"), ERR_UNAVAILABLE, mode + " blocks")
		check_eq(store.save_game(ShopRules.new(changed)), ERR_UNAVAILABLE, mode + " blocks save")
		check(FileAccess.get_file_as_bytes(path) == original, mode + " retains bytes")

func test_missing_or_malformed_metadata_and_legacy_binary_corruption_quarantine() -> void:
	for mode in ["missing", "hash", "legacy_binary"]:
		var path := _path()
		var metadata := CONTRACT.describe(TEA)
		if mode == "missing": metadata = {}
		if mode == "hash": metadata.gameplay = 7
		_write(path, ShopRules.new(TEA).to_dict(), metadata, 1 if mode == "legacy_binary" else 2)
		if mode == "legacy_binary":
			var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			payload.state = "!!!="
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(JSON.stringify(payload))
			file.close()
		var original := FileAccess.get_file_as_bytes(path)
		var store := ShopSave.new(TEA, path)
		store.load_game()
		check_eq(store.get("load_error"), OK, mode + " recovered corruption")
		check(not store.exists(), mode + " quarantined")
		var retained := false
		for file in DirAccess.get_files_at(path.get_base_dir()):
			if file.begins_with(path.get_file() + ".corrupt-"):
				retained = FileAccess.get_file_as_bytes(path.get_base_dir().path_join(file)) == original
		check(retained, mode + " exact quarantine bytes")

