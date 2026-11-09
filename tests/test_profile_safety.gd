extends "res://tests/test_case.gd"

const Profile := preload("res://game/app/profile.gd")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")

class FailingProfile extends "res://game/app/profile.gd":
	var fail_write := false
	func _write_candidate(candidate: Dictionary) -> Error:
		if fail_write: return ERR_FILE_CANT_WRITE
		return super._write_candidate(candidate)

class FailingStore extends ShopSave:
	var fail_write := false
	var keep_deleted := false
	func save_game(rules: ShopRules, speed := 1.0, guides: Array = []) -> Error:
		if fail_write:
			last_error = "injected shop write failure"
			return ERR_FILE_CANT_WRITE
		return super.save_game(rules, speed, guides)
	func delete() -> void:
		if not keep_deleted: super.delete()

var paths: Array[String] = []

func _path(label: String) -> String:
	var result := "user://profile-safety-%d-%d-%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	paths.append(result)
	return result

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func cleanup() -> void:
	for path in paths:
		for suffix in ["", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func test_finish_failure_preserves_profile_memory_and_bytes() -> void:
	var profile := FailingProfile.new(_path("profile"))
	check_eq(profile.save(), OK, "initial profile saved")
	var before := profile.to_dict()
	var bytes := FileAccess.get_file_as_bytes(profile.path)
	profile.fail_write = true
	var result: Variant = profile.call("finish_shop", {"shop": "pancake", "seconds": 1.25})
	check(result != null and result != OK, "finish reports write failure")
	check_eq(profile.to_dict(), before, "failed finish does not mutate profile")
	check_eq(FileAccess.get_file_as_bytes(profile.path), bytes, "failed finish preserves bytes")
	profile.fail_write = false
	check_eq(profile.call("finish_shop", {"shop": "pancake", "seconds": 1.25}), OK, "retry commits")
	check_eq(profile.records.size(), 1, "retry adds only one record")
	check_eq(Profile.new(profile.path).to_dict(), profile.to_dict(), "accepted profile durable")

func test_future_and_malformed_profiles_block_all_writes() -> void:
	for text in ['{"version":99,"shop":"tea","trophies":100}', '{"version":"1"}', '{"version":1.5}', '{"version":0}', '{"version":true}', '{"version":1,"records":{}}', '{broken']:
		var path := _path("invalid")
		_write(path, text)
		var profile := Profile.new(path)
		var before := profile.to_dict()
		check(profile.save() != OK, "unsupported or malformed profile blocks save")
		check(profile.call("reset_all") != OK, "unsupported profile blocks reset")
		check(profile.call("finish_shop", {"shop": "pancake"}) != OK, "unsupported profile blocks finish")
		check(profile.call("select_shop", "tea") != OK, "unsupported profile blocks jump")
		check(profile.call("acknowledge_fresh_shop") != OK, "unsupported profile blocks acknowledgement")
		check_eq(profile.to_dict(), before, "blocked operations preserve memory")
		check_eq(FileAccess.get_file_as_string(path), text, "blocked operations preserve original")

func test_missing_version_compatibility_and_external_replacement() -> void:
	var path := _path("legacy")
	_write(path, '{"shop":"tea","trophies":7,"records":[{"seconds":1.25}]}')
	var profile := Profile.new(path)
	check_eq(profile.shop, "tea", "missing version is legacy version 1")
	check_eq(profile.save(), OK, "legacy profile may save")
	check_eq(Profile.new(path).trophies, 7, "version 1 profile retained")
	var before := profile.to_dict()
	var future := '{"version":99,"shop":"tea","trophies":999}'
	_write(path, future)
	check(profile.call("reset_all") != OK, "external future replacement blocks reset")
	check_eq(profile.to_dict(), before, "failed reset does not mutate memory")
	check_eq(FileAccess.get_file_as_string(path), future, "external future bytes preserved")

func test_unknown_shop_id_falls_back_to_first_shop() -> void:
	# 改名或删掉的店不能把存档卡死在重试界面：和旧版一样退回第一家店，其余进度保留
	var path := _path("unknown_shop")
	_write(path, '{"version":1,"shop":"removed_shop","fresh_shop":true,"trophies":5,"records":[{"seconds":2.0}]}')
	var profile := Profile.new(path)
	check_eq(profile.load_error, OK, "unknown shop id does not block startup")
	check_eq(profile.shop, Profile.shops()[0], "no finished shop: falls back to the first shop")
	check_eq(profile.fresh_shop, false, "fallback does not wipe the first shop's save")
	check_eq(profile.trophies, 5, "other progress kept")
	check_eq(profile.records.size(), 1, "records kept")
	check_eq(profile.save(), OK, "fallback profile can save")
	check_eq(Profile.new(path).shop, Profile.shops()[0], "fallback persisted")
	# 打过的店不白玩：退到结店纪录里最远那家的下一家
	var ids := Profile.shops()
	_write(path, JSON.stringify({"version": 1, "shop": "removed_shop", "records": [{"shop": ids[0]}, {"shop": "gone"}]}))
	check_eq(Profile.new(path).shop, ids[1] if ids.size() > 1 else ids[0], "falls back to the shop after the furthest finished one")
	_write(path, JSON.stringify({"version": 1, "shop": "removed_shop", "records": [{"shop": ids[ids.size() - 1]}, {"shop": ids[0]}]}))
	check_eq(Profile.new(path).shop, ids[ids.size() - 1], "furthest finished shop wins; last shop stays")
	_write(path, '{"version":1,"shop":7}')
	check(Profile.new(path).load_error != OK, "non-string shop id is still invalid")


func test_actual_scene_finish_failure_preserves_signals_and_shop_save() -> void:
	var profile := FailingProfile.new(_path("scene-profile"))
	profile.save()
	var store := FailingStore.new(PANCAKE, _path("scene-shop"))
	var rules := ShopRules.new(PANCAKE)
	rules.completed_at = 1.0
	store.save_game(rules)
	var before := profile.to_dict()
	var bytes := FileAccess.get_file_as_bytes(store.path)
	profile.fail_write = true
	var scene: Node2D = load("res://presentation/shop/shop_play.gd").new()
	scene.profile = profile
	scene.store = store
	scene.rules = rules
	scene.shop = PANCAKE
	scene.view = ShopView.new(rules)
	scene._toast = Label.new()
	scene.change_scene_on_leave = false
	var signals: Array = []
	scene.shop_left.connect(func(id: String) -> void: signals.append(id))
	scene.leave_shop()
	check_eq(profile.to_dict(), before, "failed scene transition keeps profile")
	check_eq(FileAccess.get_file_as_bytes(store.path), bytes, "failed scene transition keeps shop file")
	check(signals.is_empty(), "failed transition emits no signal")
	profile.fail_write = false
	scene.leave_shop()
	scene.leave_shop()
	check_eq(profile.records.size(), 1, "scene retry records once")
	check_eq(signals, ["tea"], "scene transitions once")
	scene._toast.free()
	scene.rules = null
	scene.free()

func test_progress_coordinator_fresh_and_jump_order() -> void:
	var service_path := "res://game/app/progress_service.gd"
	check(ResourceLoader.exists(service_path), "progress coordinator exists")
	if not ResourceLoader.exists(service_path): return
	var service: RefCounted = load(service_path).new()
	var profile := FailingProfile.new(_path("coordinator"))
	profile.save()
	var old_store := FailingStore.new(PANCAKE, _path("old-shop"))
	var old_rules := ShopRules.new(PANCAKE)
	old_store.save_game(old_rules)
	old_store.fail_write = true
	check(service.jump_shop(profile, old_store, old_rules, "tea") != OK, "jump requires current save")
	check_eq(profile.shop, "pancake", "failed jump stays in old shop")
	old_store.fail_write = false
	profile.fail_write = true
	check(service.jump_shop(profile, old_store, old_rules, "tea") != OK, "jump requires profile commit")
	check_eq(profile.shop, "pancake", "failed profile jump stays")
	profile.fail_write = false
	old_store.keep_deleted = true
	check_eq(service.finish_shop(profile, old_store, {"shop": "pancake"}), OK, "cleanup failure still committed")
	check_eq(service.finish_shop(profile, old_store, {"shop": "pancake"}), ERR_INVALID_PARAMETER, "old shop cannot finish twice")
	check_eq(profile.records.size(), 1, "cleanup retry does not duplicate")
	var store := FailingStore.new(TEA, _path("new-shop"))
	store.fail_write = true
	check(service.initialize_fresh(profile, store).error != OK, "empty shop save failure blocks init")
	check(profile.fresh_shop and Profile.new(profile.path).fresh_shop, "failed empty save retains marker")
	store.fail_write = false
	profile.fail_write = true
	check(service.initialize_fresh(profile, store).error != OK, "marker acknowledgement failure blocks init")
	check(profile.fresh_shop and Profile.new(profile.path).fresh_shop, "failed acknowledgement retains marker")
	check_eq(ShopSave.new(TEA, store.path).load_game().clock, 0.0, "empty target saved first")
	profile.fail_write = false
	var result: Dictionary = service.initialize_fresh(profile, store)
	check_eq(result.error, OK, "initialization retry succeeds")
	check(not profile.fresh_shop and not Profile.new(profile.path).fresh_shop, "successful init clears durable marker")
	check_eq(result.rules.clock, 0.0, "new rules start empty")

func test_startup_failure_blocks_play_and_autosave_until_retry() -> void:
	var profile := FailingProfile.new(_path("startup-profile"))
	profile.finish_shop({"shop": "pancake"})
	var store := FailingStore.new(TEA, _path("startup-shop"))
	var previous := ShopRules.new(TEA)
	previous.gold = 4321.0
	store.save_game(previous)
	var bytes := FileAccess.get_file_as_bytes(store.path)
	store.fail_write = true
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.profile = profile
	scene.store = store
	Engine.get_main_loop().root.add_child(scene)
	if not scene.is_node_ready(): scene._ready()
	check(profile.fresh_shop, "failed startup retains fresh marker")
	check(scene.rules == null, "failed startup exposes no playable rules")
	check(not scene.is_processing(), "failed startup disables scene processing")
	check(scene.save_now(false) != OK, "failed startup rejects autosave")
	check_eq(FileAccess.get_file_as_bytes(store.path), bytes, "failed startup retains previous file")
	check(scene.has_method("retry_startup"), "failed startup offers retry")
	if scene.has_method("retry_startup"):
		store.fail_write = false
		profile.fail_write = true
		scene.retry_startup()
		check(scene.rules == null and profile.fresh_shop, "acknowledgement failure remains blocked")
		var empty_bytes := FileAccess.get_file_as_bytes(store.path)
		scene.save_now(false)
		check_eq(FileAccess.get_file_as_bytes(store.path), empty_bytes, "blocked acknowledgement cannot autosave")
		scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check_eq(FileAccess.get_file_as_bytes(store.path), empty_bytes, "blocked focus notification cannot autosave")
		# run_all invokes synchronous suites before the tree enters. The deferred
		# focused runner additionally exercises full HUD initialization on retry.
		if scene.is_inside_tree():
			profile.fail_write = false
			scene.retry_startup()
			check(scene.rules != null and not profile.fresh_shop, "retry initializes before play")
			check_eq(scene.rules.clock, 0.0, "retry uses empty target rules")
			check(scene.is_processing(), "successful retry enables processing")
		scene.rules = null
	scene.free()

func test_external_future_profile_blocks_fresh_target_overwrite() -> void:
	var profile := Profile.new(_path("external-future"))
	profile.finish_shop({"shop": "pancake"})
	var store := ShopSave.new(TEA, _path("future-target"))
	var previous := ShopRules.new(TEA)
	previous.gold = 9876.0
	store.save_game(previous)
	var before := FileAccess.get_file_as_bytes(store.path)
	_write(profile.path, '{"version":99,"shop":"tea","trophies":123}')
	var service: RefCounted = load("res://game/app/progress_service.gd").new()
	check(service.initialize_fresh(profile, store).error != OK, "external future profile blocks initialization")
	check_eq(FileAccess.get_file_as_bytes(store.path), before, "future profile does not clear target shop")

func test_actual_scene_jump_requires_both_saves_before_signal() -> void:
	var profile := FailingProfile.new(_path("jump-profile"))
	profile.save()
	var store := FailingStore.new(PANCAKE, _path("jump-shop"))
	var rules := ShopRules.new(PANCAKE)
	store.save_game(rules)
	var bytes := FileAccess.get_file_as_bytes(store.path)
	var before := profile.to_dict()
	var scene: Node2D = load("res://presentation/shop/shop_play.gd").new()
	scene.profile = profile
	scene.store = store
	scene.rules = rules
	scene.shop = PANCAKE
	scene._toast = Label.new()
	scene.change_scene_on_leave = false
	var signals: Array = []
	scene.shop_left.connect(func(id: String) -> void: signals.append(id))
	store.fail_write = true
	check_eq(scene.jump_shop(1), "", "shop save failure blocks actual jump")
	check_eq(FileAccess.get_file_as_bytes(store.path), bytes, "failed jump preserves shop bytes")
	check_eq(profile.to_dict(), before, "failed shop save preserves profile")
	check(signals.is_empty(), "failed shop save emits no jump signal")
	store.fail_write = false
	profile.fail_write = true
	check_eq(scene.jump_shop(1), "", "profile failure blocks actual jump")
	check_eq(profile.to_dict(), before, "failed profile save preserves profile")
	check(signals.is_empty(), "failed profile save emits no jump signal")
	profile.fail_write = false
	check_eq(scene.jump_shop(1), "tea", "actual jump retries successfully")
	check_eq(signals, ["tea"], "successful jump emits once")
	check_eq(Profile.new(profile.path).shop, "tea", "jump durable before signal")
	scene._toast.free()
	scene.rules = null
	scene.free()
