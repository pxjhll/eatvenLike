extends "res://tests/test_case.gd"
## All persistence tests own a unique directory and never open player saves.

const SAVE_SCRIPT := "res://game/tea_playtest/tea_shop_save.gd"
const SIM_SCRIPT := "res://game/tea_playtest/tea_shop_sim.gd"
var _test_dir := ""


func _path(name: String = "shop.json") -> String:
	if _test_dir.is_empty():
		_test_dir = "user://tea_shop_save_tests_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
		DirAccess.make_dir_recursive_absolute(_test_dir)
	return _test_dir + "/" + name


func _store(path: String = ""):
	if not ResourceLoader.exists(SAVE_SCRIPT):
		check(false, "shop save service exists")
		return null
	return load(SAVE_SCRIPT).new(_path() if path.is_empty() else path)


func _sim():
	return load(SIM_SCRIPT).new()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _envelope(state: Variant, version: int = 1) -> Dictionary:
	var bytes := var_to_bytes(state)
	return {"format": "tea_shop", "version": version, "speed": 1.0,
		"state": Marshalls.raw_to_base64(bytes), "state_sha256": bytes.hex_encode().sha256_text()}


func _backups(path: String) -> PackedStringArray:
	var found := PackedStringArray()
	for name in DirAccess.get_files_at(path.get_base_dir()):
		if name.begins_with(path.get_file() + ".corrupt-"):
			found.append(path.get_base_dir() + "/" + name)
	return found


func test_missing_save_returns_fresh_shop_without_creating_file() -> void:
	var store = _store()
	if store == null: return
	var sim = store.load_game()
	check_eq(sim.to_dict(), _sim().to_dict(), "missing file starts the real business simulation")
	check_eq(store.loaded_speed, 1.0, "default playback speed")
	check_eq(store.last_error, "", "missing file is not an error")
	check(not FileAccess.file_exists(_path()), "loading does not write a save")


func test_full_shop_state_and_continuation_roundtrip() -> void:
	var store = _store()
	if store == null: return
	for belts in [false, true]:
		var sim = _sim()
		sim.gold = 100000
		sim.revenue = 10000
		check_eq(sim.unlock_station("lemonade"), "", "open lemonade")
		check_eq(sim.unlock_station("boil"), "", "open black tea line")
		check_eq(sim.unlock_station("mix"), "", "open milk machine")
		check_eq(sim.unlock_station("topping"), "", "open topping")
		check(sim.hire() and sim.hire(), "own two additional employees")
		for employee in sim.all_workers():
			if employee.id != sim.workers[0].id:
				check_eq(sim.deploy_worker(employee.id), "", "deploy owned employee")
		check(sim.train(sim.workers[0].id), "training included in save")
		sim.set_belts(belts)
		var saw_machine := false
		var saw_transport := false
		for tick in 12000:
			sim.advance(0.1)
			for station in sim.stations.values():
				saw_machine = saw_machine or station.processing > 0
			for worker in sim.workers:
				saw_transport = saw_transport or worker.carry_count > 0
			if saw_machine and (not sim.belt_items.is_empty() if belts else saw_transport): break
		check(saw_machine and saw_transport, "save after real machine and transport activity")
		if belts: check(not sim.belt_items.is_empty(), "save contains a pending belt shipment")
		sim.advance(0.037)
		var before: Dictionary = sim.to_dict()
		check_eq(store.save_game(sim, 2.0), OK, "atomic write succeeds")
		check(not FileAccess.file_exists(_path() + ".tmp"), "temporary file replaced")
		var resumed = store.load_game()
		check_eq(store.last_error, "", "saved state accepted")
		check_eq(store.loaded_speed, 2.0, "playback speed restored")
		check_eq(var_to_bytes(resumed.to_dict()), var_to_bytes(before), "all types and exact values restored")
		for tick in 300:
			sim.advance(0.1)
			resumed.advance(0.1)
		check_eq(var_to_bytes(resumed.to_dict()), var_to_bytes(sim.to_dict()), "resumed production and randomness continue identically")
		check(resumed.audit().valid, "reload preserves stock and reservations")


func test_save_paths_remain_independent() -> void:
	var first = _store(_path("first.json"))
	if first == null: return
	var second = _store(_path("second.json"))
	var sim = _sim()
	check_eq(first.save_game(sim, 0.5), OK, "first path saved")
	sim.gold += 123
	check_eq(second.save_game(sim, 3.0), OK, "second path saved")
	check_eq(first.load_game().gold, 50, "first path retains its own state")
	check_eq(second.load_game().gold, 173, "second path retains its own state")
	check_eq(first.loaded_speed, 0.5, "first path retains speed")
	check_eq(second.loaded_speed, 3.0, "second path retains speed")


func test_bench_training_and_deployed_roster_reference_survive_reload() -> void:
	var store = _store()
	if store == null: return
	var sim = _sim()
	sim.gold = 500
	check(sim.hire(), "hire creates an owned bench employee")
	var bench_id: int = sim.all_workers()[1].id
	check(sim.train(bench_id), "train while on bench")
	var original: Dictionary = sim.to_dict()
	check_eq(store.save_game(sim), OK, "save roster with bench employee")
	var resumed = store.load_game()
	check_eq(var_to_bytes(resumed.to_dict()), var_to_bytes(original), "bench record and training restored")
	check_eq(resumed.workers.size(), 1, "bench employee remains undeployed")
	check_eq(resumed.worker_by_id(bench_id).level, 2, "bench level retained")
	var deployed_id: int = resumed.workers[0].id
	resumed.worker_by_id(deployed_id).fatigue = 0.123
	check_eq(resumed.workers[0].fatigue, 0.123, "deployed record still refers to its owned roster dictionary")


func test_malformed_files_are_backed_up_before_recovery() -> void:
	var store = _store()
	if store == null: return
	var bad_base64 := _envelope({})
	bad_base64.state = "%%%invalid-base64%%%"
	var bad_checksum := _envelope({})
	bad_checksum.state_sha256 = "0".repeat(64)
	var bad_speed := _envelope({})
	bad_speed.speed = "f64:broken"
	var bad_binary := _envelope({})
	var truncated := PackedByteArray([TYPE_DICTIONARY, 0, 0, 0, 12, 0, 0, 0])
	bad_binary.state = Marshalls.raw_to_base64(truncated)
	bad_binary.state_sha256 = truncated.hex_encode().sha256_text()
	var bad_version := _envelope({})
	bad_version.version = 1.5
	var bad_utf8 := _envelope({})
	var invalid_text := PackedByteArray([TYPE_DICTIONARY, 0, 0, 0, 1, 0, 0, 0,
		TYPE_STRING, 0, 0, 0, 1, 0, 0, 0, 255, 0, 0, 0, TYPE_NIL, 0, 0, 0])
	bad_utf8.state = Marshalls.raw_to_base64(invalid_text)
	bad_utf8.state_sha256 = invalid_text.hex_encode().sha256_text()
	var cases := ["{ broken JSON", "[]", "{}", JSON.stringify(bad_base64),
		JSON.stringify(bad_checksum), JSON.stringify(bad_speed), JSON.stringify(bad_binary),
		JSON.stringify(bad_version), JSON.stringify(bad_utf8),
		JSON.stringify(_envelope({"object": RefCounted.new()})),
		JSON.stringify(_envelope([])), JSON.stringify(_envelope({}))]
	for index in cases.size():
		var path := _path("corrupt_%d.json" % index)
		_write(path, cases[index])
		store = _store(path)
		check_eq(store.load_game().gold, 50, "invalid state returns fresh shop")
		check(not store.last_error.is_empty(), "invalid state reports an error")
		var backups := _backups(path)
		check_eq(backups.size(), 1, "exactly one corrupt backup")
		if not backups.is_empty(): check_eq(FileAccess.get_file_as_string(backups[0]), cases[index], "backup preserves exact original bytes")
		check_eq(store.save_game(_sim()), OK, "recovery can save after backup")
		check_eq(_backups(path).size(), 1, "recovery leaves backup untouched")


func test_direct_save_protects_existing_corrupt_file() -> void:
	var path := _path()
	var store = _store(path)
	if store == null: return
	_write(path, "{ broken before first load")
	check_eq(store.save_game(_sim()), OK, "direct save can recover after backup")
	var backups := _backups(path)
	check_eq(backups.size(), 1, "direct write keeps corrupt original")
	if not backups.is_empty(): check_eq(FileAccess.get_file_as_string(backups[0]), "{ broken before first load", "original content retained")


func test_future_version_stays_read_only_even_before_loading() -> void:
	var path := _path()
	var store = _store(path)
	if store == null: return
	var original := JSON.stringify(_envelope({}, 999))
	_write(path, original)
	check_eq(store.save_game(_sim()), ERR_UNAVAILABLE, "direct write cannot downgrade future save")
	check_eq(FileAccess.get_file_as_string(path), original, "future save untouched")
	check_eq(store.load_game().gold, 50, "unknown version can still open a fresh shop")
	check(not store.last_error.is_empty(), "version failure is visible")
	check_eq(store.save_game(_sim()), ERR_UNAVAILABLE, "autosave remains blocked")
	check_eq(FileAccess.get_file_as_string(path), original, "future bytes remain intact")
	check(_backups(path).is_empty(), "future file is not labeled corrupt")


func test_failed_write_and_invalid_speed_report_errors_without_overwrite() -> void:
	var store = _store(_path("missing/child.json"))
	if store == null: return
	check(store.save_game(_sim()) != OK, "missing parent write fails")
	check(not store.last_error.is_empty(), "write failure visible")
	store = _store()
	check_eq(store.save_game(_sim()), OK, "baseline write")
	var original := FileAccess.get_file_as_string(_path())
	for speed in [0.0, -1.0, INF, NAN]:
		check_eq(store.save_game(_sim(), speed), ERR_INVALID_PARAMETER, "invalid playback speed rejected")
		check(not store.last_error.is_empty(), "invalid input error visible")
		check_eq(FileAccess.get_file_as_string(_path()), original, "invalid input leaves existing save intact")
	var invalid = _sim()
	invalid.gold = -1
	check_eq(store.save_game(invalid), ERR_INVALID_DATA, "invalid simulation cannot overwrite good save")
	check(not store.last_error.is_empty(), "invalid simulation error visible")
	check_eq(FileAccess.get_file_as_string(_path()), original, "invalid simulation preserves existing bytes")


func cleanup() -> void:
	if not _test_dir.is_empty():
		for name in DirAccess.get_files_at(_test_dir):
			DirAccess.remove_absolute(_test_dir + "/" + name)
		DirAccess.remove_absolute(_test_dir)
	super.cleanup()
