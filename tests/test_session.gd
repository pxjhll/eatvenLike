extends "res://tests/test_case.gd"

const Profile := preload("res://game/app/profile.gd")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const SESSION_PATH := "res://game/app/shop_session.gd"

class FailingProfile extends "res://game/app/profile.gd":
	var fail_write := false
	func _write_candidate(candidate: Dictionary) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._write_candidate(candidate)

class FailingStore extends ShopSave:
	var fail_write := false
	func save_game(rules: ShopRules, speed := 1.0, guides: Array = []) -> Error:
		if fail_write:
			last_error = "injected shop write failure"
			return ERR_FILE_CANT_WRITE
		return super.save_game(rules, speed, guides)

var paths: Array[String] = []

func _path(label: String) -> String:
	var result := "user://session-core-%d-%d-%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	paths.append(result)
	return result

func _session(profile: RefCounted, store: ShopSave, rules: ShopRules = null) -> RefCounted:
	check(ResourceLoader.exists(SESSION_PATH), "explicit session lifecycle exists")
	return load(SESSION_PATH).new(profile, store, rules) if ResourceLoader.exists(SESSION_PATH) else null

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func cleanup() -> void:
	for path in paths:
		for name in DirAccess.get_files_at(path.get_base_dir()):
			if name == path.get_file() or name.begins_with(path.get_file() + "."):
				DirAccess.remove_absolute(path.get_base_dir().path_join(name))

func test_duplicate_listener_registration_is_idempotent_and_off_removes_it() -> void:
	var bus := RuleEvents.new()
	var seen: Array = []
	var listener := func(data: Dictionary) -> void: seen.append(data)
	bus.on("sale", listener)
	bus.on("sale", listener)
	bus.emit("sale", {"amount": 4})
	check_eq(seen, [{"amount": 4}], "one logical subscription fires once")
	bus.off("sale", listener)
	bus.emit("sale")
	check_eq(seen.size(), 1, "off removes the subscription")

func test_reset_preserves_live_bus_and_clears_only_history() -> void:
	var rules := ShopRules.new(PANCAKE)
	var bus := rules.events
	var seen: Array = []
	bus.on("sale", func(data: Dictionary) -> void: seen.append(data))
	bus.clock = 90.0
	bus.emit("old")
	rules.reset()
	rules.reset()
	check(rules.events == bus, "reset keeps live bus identity")
	check_eq(bus.log, [], "reset clears history")
	check_eq(bus.clock, 0.0, "reset clears event clock")
	rules.events.emit("sale", {"amount": 4})
	check_eq(seen, [{"amount": 4}], "external listener survives repeated reset exactly once")
	check_eq(rules.events.log.size(), 1, "reset does not create lifecycle log records")

func test_restore_preserves_live_bus_and_single_internal_dispatch() -> void:
	var rules := ShopRules.new(PANCAKE)
	var bus := rules.events
	var seen: Array = []
	bus.on("unlocked", func(data: Dictionary) -> void: seen.append(data))
	var ev := SpecEvent.new()
	ev.id = "core_probe"
	ev.trigger = "unlocked"
	ev.chance = 1.0
	ev.choices = [{"label": "probe"}]
	for index in 3:
		rules.reset()
		rules.add_event(ev)
		var data := rules.to_dict()
		data.clock = 7.25
		data.log = [{"name": "sale", "time": 6.0, "data": {"amount": 2}}]
		check_eq(rules.load_dict(data), "", "valid restore accepted")
		check(rules.events == bus, "restore keeps live bus identity")
		check_eq(bus.clock, 7.25, "restore adopts event clock")
		check_eq(bus.log, data.log, "restore adopts exact log without new records")
		rules.events.emit("unlocked", {"id": "probe"})
		check_eq(rules.pending_events.size(), 1, "only live internal dispatch runs once")
	check_eq(seen.size(), 3, "external subscription survives all restores")
	var before := rules.to_dict()
	var invalid := before.duplicate(true)
	invalid.clock = -1.0
	check(not rules.load_dict(invalid).is_empty(), "invalid restore rejected")
	check_eq(rules.to_dict(), before, "rejected restore leaves live state atomic")
	check(rules.events == bus, "rejected restore retains live bus")
	rules.events.emit("unlocked", {"id": "probe"})
	check_eq(seen.size(), 4, "rejected restore retains subscription")
	check_eq(rules.pending_events.size(), 2, "rejected restore retains one internal handler")

func test_start_loads_explicit_store_once_and_defaults_services_off() -> void:
	var profile := Profile.new(_path("profile"))
	var store := ShopSave.new(PANCAKE, _path("shop"))
	var saved := ShopRules.new(PANCAKE)
	saved.gold = 4321.0
	check_eq(store.save_game(saved, 2.0, ["opening"]), OK, "seed isolated shop")
	var session := _session(profile, store)
	if session == null: return
	check(not session.guide_enabled and not session.persist_tuning and not session.recording_enabled, "services default independently disabled")
	check_eq(session.start(), OK, "explicit session starts")
	check_eq(session.rules.gold, 4321.0, "start restores explicit store")
	check_eq(session.speed, 2.0, "start restores speed")
	check_eq(session.guides_seen, ["opening"], "start restores guide history")
	var live: ShopRules = session.rules
	live.gold = 9876.0
	check_eq(session.start(), OK, "start is idempotent")
	check(session.rules == live, "idempotent start keeps rules")
	check_eq(session.rules.gold, 9876.0, "idempotent start does not reload saved values")
	check(not FileAccess.file_exists(profile.path), "ordinary session start does not write profile")

func test_injected_rules_skip_load_and_restart_resumes_without_writes() -> void:
	var profile := Profile.new(_path("restart-profile"))
	profile.save()
	var store := ShopSave.new(PANCAKE, _path("restart-shop"))
	store.save_game(ShopRules.new(PANCAKE), 1.0, ["on_disk"])
	var rules := ShopRules.new(PANCAKE)
	rules.gold = 1234.0
	rules.tune = {"work": 1.5}
	rules.paused = true
	var bus := rules.events
	var session := _session(profile, store, rules)
	if session == null: return
	var signals: Array = []
	session.restarted.connect(func() -> void: signals.append("restart"))
	check(session.restart() != OK, "restart requires started session")
	session.speed = 3.0
	session.guides_seen = ["opening"]
	session.guide_enabled = true
	check_eq(session.start(), OK, "injected session starts")
	check(session.rules == rules and rules.gold == 1234.0, "injected rules are never reloaded")
	check_eq(session.guides_seen, ["opening"], "injected session guide history retained")
	var bytes := FileAccess.get_file_as_bytes(store.path)
	var profile_bytes := FileAccess.get_file_as_bytes(profile.path)
	var profile_state := profile.to_dict()
	check_eq(session.restart(), OK, "restart succeeds")
	check(not rules.paused, "restart resumes business immediately")
	check_eq(rules.gold, float(PANCAKE.start_gold), "restart resets business")
	check_eq(rules.tune, {"work": 1.5}, "restart retains tuning")
	check_eq(session.speed, 3.0, "restart retains speed")
	check_eq(session.guides_seen, ["opening"], "restart retains seen guides")
	check(session.guide_enabled, "restart retains guide setting")
	check(rules.events == bus, "restart retains event bus")
	check_eq(signals, ["restart"], "successful restart signals once")
	check_eq(FileAccess.get_file_as_bytes(store.path), bytes, "restart does not save implicitly")
	check_eq(FileAccess.get_file_as_bytes(profile.path), profile_bytes, "restart preserves profile bytes")
	check_eq(profile.to_dict(), profile_state, "restart preserves profile memory")

func test_service_configuration_is_validated_before_fresh_shop_writes() -> void:
	for feature in ["persist_tuning", "recording_enabled"]:
		var profile := Profile.new(_path(feature + "-profile"))
		profile.finish_shop({"shop": "pancake"})
		var store := ShopSave.new(TEA, _path(feature + "-shop"))
		var previous := ShopRules.new(TEA)
		previous.gold = 7777.0
		store.save_game(previous)
		var before := FileAccess.get_file_as_bytes(store.path)
		var profile_bytes := FileAccess.get_file_as_bytes(profile.path)
		var session := _session(profile, store)
		if session == null: return
		session.set(feature, true)
		check(session.start() != OK, "enabled service requires explicit destination")
		check(not session.started and session.rules == null, "invalid configuration exposes no rules")
		check_eq(FileAccess.get_file_as_bytes(store.path), before, "configuration failure precedes empty shop write")
		check_eq(FileAccess.get_file_as_bytes(profile.path), profile_bytes, "configuration failure precedes acknowledgement")
		session.set("tuning_path" if feature == "persist_tuning" else "recording_path", _path(feature))
		check_eq(session.start(), OK, "explicit destination allows retry")
		check(not profile.fresh_shop, "successful retry acknowledges fresh marker")
		check_eq(session.rules.clock, 0.0, "retry starts empty shop")

func test_fresh_shop_failures_retry_without_play_or_duplicate_profile_commit() -> void:
	var profile := FailingProfile.new(_path("fresh-profile"))
	profile.finish_shop({"shop": "pancake"})
	var store := FailingStore.new(TEA, _path("fresh-shop"))
	var previous := ShopRules.new(TEA)
	previous.gold = 5555.0
	store.save_game(previous)
	var bytes := FileAccess.get_file_as_bytes(store.path)
	var session := _session(profile, store)
	if session == null: return
	store.fail_write = true
	check_eq(session.start(), ERR_FILE_CANT_WRITE, "shop write failure propagates")
	check(not session.started and session.rules == null, "failed start exposes no rules")
	check(session.save() != OK and session.restart() != OK, "failed start cannot save or restart")
	check_eq(FileAccess.get_file_as_bytes(store.path), bytes, "failed initial write preserves old shop")
	store.fail_write = false
	profile.fail_write = true
	check_eq(session.start(), ERR_FILE_CANT_WRITE, "acknowledgement failure propagates")
	check(profile.fresh_shop and session.rules == null, "failed acknowledgement remains blocked")
	profile.fail_write = false
	check_eq(session.start(), OK, "start retries after both failures")
	check(not profile.fresh_shop and not Profile.new(profile.path).fresh_shop, "successful start durably acknowledges")
	check_eq(profile.records.size(), 1, "startup retry never duplicates prior finish")
	check_eq(session.start(), OK, "successful start remains idempotent")

func test_save_failure_preserves_file_and_retry_uses_session_options() -> void:
	var profile := Profile.new(_path("save-profile"))
	var store := FailingStore.new(PANCAKE, _path("save-shop"))
	var session := _session(profile, store, ShopRules.new(PANCAKE))
	if session == null: return
	check_eq(session.start(), OK, "start")
	session.speed = 2.0
	check_eq(session.save(["opening"]), OK, "save explicit speed and guides")
	var bytes := FileAccess.get_file_as_bytes(store.path)
	store.fail_write = true
	session.rules.gold = 9999.0
	check_eq(session.save(["opening", "next"]), ERR_FILE_CANT_WRITE, "save propagates failure")
	check(not session.last_error.is_empty(), "save exposes actionable error")
	check_eq(FileAccess.get_file_as_bytes(store.path), bytes, "failed save preserves old bytes")
	store.fail_write = false
	check_eq(session.save(["opening", "next"]), OK, "save can retry")
	var reader := ShopSave.new(PANCAKE, store.path)
	check_eq(reader.load_game().gold, 9999.0, "retry durably stores latest rules")
	check_eq(reader.loaded_speed, 2.0, "save uses session speed")
	check_eq(reader.loaded_guides, ["opening", "next"], "save uses supplied guide history")

func test_finish_commits_once_and_blocks_all_old_session_writes() -> void:
	var profile := FailingProfile.new(_path("finish-profile"))
	profile.save()
	var store := ShopSave.new(PANCAKE, _path("finish-shop"))
	var session := _session(profile, store, ShopRules.new(PANCAKE))
	if session == null: return
	session.start()
	session.save()
	var before := FileAccess.get_file_as_bytes(profile.path)
	var shop_bytes := FileAccess.get_file_as_bytes(store.path)
	profile.fail_write = true
	check_eq(session.finish({"shop": "pancake", "seconds": 1.25}), ERR_FILE_CANT_WRITE, "finish failure propagates")
	check(not session.transition_committed, "failed finish remains retryable")
	check_eq(FileAccess.get_file_as_bytes(profile.path), before, "failed finish preserves profile bytes")
	check_eq(FileAccess.get_file_as_bytes(store.path), shop_bytes, "failed finish keeps shop save")
	profile.fail_write = false
	check_eq(session.finish({"shop": "pancake", "seconds": 1.25}), OK, "finish retries successfully")
	check(session.transition_committed, "successful finish seals old session")
	check(not FileAccess.file_exists(store.path), "successful finish cleans old save")
	check(session.finish({"shop": "pancake"}) != OK, "old session cannot finish again")
	check(session.jump("tea") != OK, "old session cannot jump after finish")
	check(session.save() != OK and session.restart() != OK, "old session cannot save or restart")
	check(session.start() != OK, "departed session cannot be started by another scene")
	check(not FileAccess.file_exists(store.path), "sealed session cannot recreate old shop save")
	check_eq(profile.records.size(), 1, "only one durable finish record")

func test_finish_retains_protected_replacement_and_commits_profile_once() -> void:
	for mode in ["future", "future_content"]:
		var profile := Profile.new(_path(mode + "-finish-profile"))
		check_eq(profile.save(), OK, mode + " profile seeded")
		var store := ShopSave.new(PANCAKE, _path(mode + "-finish-shop"))
		var session := _session(profile, store)
		check_eq(session.start(), OK, mode + " session starts")
		check_eq(session.save(), OK, mode + " active save")
		var replacement: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
		if mode == "future": replacement.version = 99
		else: replacement.content.version = 99
		_write(store.path, JSON.stringify(replacement))
		var original := FileAccess.get_file_as_bytes(store.path)
		check_eq(session.save(), ERR_UNAVAILABLE, mode + " replacement blocks save")
		check_eq(session.finish({"shop": "pancake", "seconds": 1.25}), OK, mode + " profile committed despite retained cleanup")
		check(session.transition_committed, mode + " finish seals session")
		check(FileAccess.file_exists(store.path), mode + " finish retains protected replacement")
		if FileAccess.file_exists(store.path): check(FileAccess.get_file_as_bytes(store.path) == original, mode + " finish retains exact bytes")
		var persisted := Profile.new(profile.path)
		check_eq(persisted.shop, "tea", mode + " profile advanced durably")
		check_eq(persisted.records.size(), 1, mode + " one durable finish record")
		check_eq(persisted.records[0].seconds, 1.25, mode + " finish record retained")
		check(session.finish({"shop": "pancake"}) != OK, mode + " finish cannot replay")
		check(session.save() != OK and session.restart() != OK and session.start() != OK, mode + " old session cannot mutate")
		check_eq(Profile.new(profile.path).records.size(), 1, mode + " retry cannot duplicate durable records")
		if FileAccess.file_exists(store.path): check(FileAccess.get_file_as_bytes(store.path) == original, mode + " sealed session retains replacement")

func test_jump_requires_both_commits_and_seals_successful_session() -> void:
	var profile := FailingProfile.new(_path("jump-profile"))
	profile.save()
	var store := FailingStore.new(PANCAKE, _path("jump-shop"))
	var session := _session(profile, store, ShopRules.new(PANCAKE))
	if session == null: return
	session.start()
	session.save()
	var profile_bytes := FileAccess.get_file_as_bytes(profile.path)
	var shop_bytes := FileAccess.get_file_as_bytes(store.path)
	store.fail_write = true
	check_eq(session.jump("tea", ["opening"]), ERR_FILE_CANT_WRITE, "jump first requires shop save")
	check_eq(FileAccess.get_file_as_bytes(profile.path), profile_bytes, "failed shop save leaves profile bytes")
	check_eq(FileAccess.get_file_as_bytes(store.path), shop_bytes, "failed shop save preserves old file")
	store.fail_write = false
	profile.fail_write = true
	check_eq(session.jump("tea", ["opening"]), ERR_FILE_CANT_WRITE, "jump also requires profile commit")
	check(not session.transition_committed and profile.shop == "pancake", "failed profile commit remains retryable")
	profile.fail_write = false
	check_eq(session.jump("tea", ["opening"]), OK, "jump retries")
	check(session.transition_committed, "successful jump seals session")
	check_eq(Profile.new(profile.path).shop, "tea", "jump is durable")
	check(session.jump("pancake") != OK and session.finish({}) != OK, "sealed jump cannot replay transitions")
	check(session.save() != OK and session.restart() != OK, "sealed jump cannot mutate old store")
	check(session.start() != OK, "sealed jump cannot be replayed through start")

func test_invalid_profile_and_external_future_replacement_preserve_fresh_shop() -> void:
	var profile := Profile.new(_path("future-profile"))
	profile.finish_shop({"shop": "pancake"})
	var store := ShopSave.new(TEA, _path("future-shop"))
	store.save_game(ShopRules.new(TEA))
	var bytes := FileAccess.get_file_as_bytes(store.path)
	var future := '{"version":99,"shop":"tea","trophies":123}'
	_write(profile.path, future)
	var session := _session(profile, store)
	if session == null: return
	check(session.start() != OK, "external future profile blocks fresh initialization")
	check(session.rules == null and not session.started, "future profile offers no playable rules")
	check_eq(FileAccess.get_file_as_bytes(store.path), bytes, "future profile cannot overwrite old target")
	check_eq(FileAccess.get_file_as_string(profile.path), future, "future profile bytes retained")
	var blocked := _session(Profile.new(profile.path), store, ShopRules.new(TEA))
	check(blocked.start() != OK, "invalid profile also blocks injected rules")

func test_dependency_mismatch_is_rejected_before_start_or_transition() -> void:
	var profile := Profile.new(_path("mismatch-profile"))
	profile.save()
	var store := ShopSave.new(TEA, _path("mismatch-shop"))
	store.save_game(ShopRules.new(TEA))
	var bytes := FileAccess.get_file_as_bytes(store.path)
	var profile_bytes := FileAccess.get_file_as_bytes(profile.path)
	var session := _session(profile, store, ShopRules.new(TEA))
	if session == null: return
	check(session.start() != OK, "profile and store must agree on current shop")
	check(session.finish({"shop": "pancake"}) != OK, "mismatched store cannot be deleted by another shop finish")
	check(FileAccess.get_file_as_bytes(store.path) == bytes, "mismatch preserves store bytes")
	check(FileAccess.get_file_as_bytes(profile.path) == profile_bytes, "mismatch preserves profile bytes")
	var wrong_rules := _session(profile, ShopSave.new(PANCAKE, _path("wrong-rules")), ShopRules.new(TEA))
	check(wrong_rules.start() != OK, "rules and store must agree on shop")
	var absent := _session(null, null)
	check(absent.start() != OK, "explicit dependencies cannot fall back to App")

func test_app_is_lazy_and_factory_explicitly_configures_production_services() -> void:
	var app: Node = load("res://game/app/app.gd").new()
	check(app.has_method("create_session"), "App exposes production session factory")
	if not app.has_method("create_session"):
		app.free()
		return
	check(app.get("_profile") == null, "App construction leaves default profile unread")
	var profile := Profile.new(_path("app-profile"))
	profile.shop = "tea"
	app.profile = profile
	var session: RefCounted = app.create_session()
	check(session.profile == profile, "factory uses explicitly assigned lazy profile")
	check_eq(session.store.shop.id, "tea", "factory derives shop from campaign")
	check(session.guide_enabled and session.persist_tuning and session.recording_enabled, "production opts into all services explicitly")
	check_eq(session.tuning_path, "user://tuning.cfg", "production tuning destination explicit")
	check_eq(session.recording_path, "user://playlog.txt", "production recording destination explicit")
	check(not session.started, "factory assembles without loading shop or writing files")
	app.free()
