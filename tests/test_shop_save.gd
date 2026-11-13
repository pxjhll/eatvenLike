extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const LegacySave := preload("res://tests/fixtures/legacy_shops/reference_save.gd")
## 通用店内存档 ShopSave（规格 §3.12）：存档后读回来接着跑，和没存过的一局逐帧一样；旧档、坏档、未来版本的处理。

const Replay := preload("res://tests/baselines/replay_rules.gd")
const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/current/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://tests/fixtures/legacy_shops/current/pancake/shop.tres")
const PATH := "user://test_shop_save.json"


func _cleanup() -> void:
	for file in DirAccess.get_files_at("user://"):
		if file.begins_with("test_shop_save.json"): DirAccess.remove_absolute("user://" + file)


func _play(rules: ShopRules, actions: Array, from: int, until: float) -> int:
	## 跑到 until 秒，途中按时间执行机器人操作；返回下一条没执行的操作
	var next := from
	while rules.clock < until - 0.0001:
		rules.step(0.1)
		while next < actions.size() and float(actions[next][0]) <= rules.clock + 0.0001:
			Replay.run_command(rules, actions[next][1])
			next += 1
	return next


func _check_resume(shop: SpecShop, save_at: float) -> void:
	_cleanup()
	var base: Dictionary = Replay.baseline(shop.id)
	var actions: Array = base.actions
	var end: float = minf(float(base.minutes) * 60.0, save_at + 300.0)
	var straight := LegacyRules.new(shop)
	var saved := LegacyRules.new(shop)
	var next := _play(saved, actions, 0, save_at)
	_play(straight, actions, 0, save_at)
	var store := LegacySave.new(shop, PATH)
	check_eq(store.save_game(saved, 2.0, ["welcome"]), OK, "%s 存档成功" % shop.id)
	var reader := LegacySave.new(shop, PATH)
	var loaded := reader.load_game()
	check_eq(reader.last_error, "", "%s 读档没有报错" % shop.id)
	check_eq(reader.loaded_speed, 2.0, "播放速度存下来了")
	check_eq(reader.loaded_guides, ["welcome"], "看过的引导存下来了")
	check_eq(str(loaded.to_dict()), str(straight.to_dict()), "%s 读回来的状态和原来一样" % shop.id)
	_play(straight, actions, next, end)
	_play(loaded, actions, next, end)
	check(loaded.sold > 0, "%s 读档后接着卖" % shop.id)
	var a := straight.to_dict()
	var b := loaded.to_dict()
	for key in a:
		check(str(a[key]) == str(b[key]), "%s 接着跑 5 分钟后 %s 一样" % [shop.id, key])
	_cleanup()


func test_tea_save_resumes_exactly() -> void:
	_check_resume(TEA, 600.0)


func test_pancake_save_resumes_exactly() -> void:
	_check_resume(PANCAKE, 420.0)


func test_old_format_file_starts_a_fresh_shop_and_is_kept_aside() -> void:
	_cleanup()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": "tea_shop", "version": 2, "state": ""}))
	file.close()
	var store := LegacySave.new(TEA, PATH)
	var rules := store.load_game()
	check(not store.last_error.is_empty(), "旧格式报出原因")
	check_eq(rules.clock, 0.0, "从新店开始")
	check(not FileAccess.file_exists(PATH), "旧档改名留底")
	check_eq(store.save_game(rules), OK, "之后能正常存")
	_cleanup()


func test_future_version_is_never_overwritten() -> void:
	_cleanup()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	var text := JSON.stringify({"format": ShopSave.FORMAT, "version": ShopSave.VERSION + 1, "shop": "tea"})
	file.store_string(text)
	file.close()
	var store := LegacySave.new(TEA, PATH)
	var rules := store.load_game()
	check_eq(store.save_game(rules), ERR_UNAVAILABLE, "新版本存档不写")
	check_eq(FileAccess.get_file_as_string(PATH), text, "原文件没动")
	_cleanup()


func test_save_of_another_shop_is_rejected() -> void:
	_cleanup()
	var store := LegacySave.new(TEA, PATH)
	check_eq(store.save_game(LegacyRules.new(PANCAKE)), ERR_INVALID_PARAMETER, "煎饼摊的状态不能存进奶茶店的档")
	var rules := LegacyRules.new(TEA)
	check_eq(rules.load_dict(LegacyRules.new(PANCAKE).to_dict()), "不是这家店的存档", "读档也会拒绝")
	_cleanup()


func test_each_shop_has_its_own_file() -> void:
	check(ShopSave.path_for("tea") != ShopSave.path_for("pancake"), "按店铺 id 分文件")


func test_configured_save_file_leaves_the_legacy_file_untouched() -> void:
	var shop: SpecShop = PANCAKE.duplicate(true)
	shop.id = "test_shop_save_%d" % OS.get_process_id()
	shop.save_file = "test_shop_save.json.v2"
	var legacy_path := ShopSave.path_for(shop.id)
	var configured_path := "user://" + shop.save_file
	var old_rules := LegacyRules.new(shop)
	old_rules.run(5.0)
	check_eq(LegacySave.new(shop, legacy_path).save_game(old_rules), OK, "准备旧路径下的存档")
	var legacy_text := FileAccess.get_file_as_string(legacy_path)
	var store := LegacySave.new(shop)
	check_eq(store.path, configured_path, "使用店铺配置的新文件名")
	var loaded := store.load_game()
	check_eq(loaded.clock, 0.0, "新文件不存在时从空店开始，不读旧路径")
	check_eq(store.save_game(loaded), OK, "新店存入新路径")
	check(FileAccess.file_exists(configured_path), "配置的存档文件已写入")
	check_eq(FileAccess.get_file_as_string(legacy_path), legacy_text, "旧存档保留原样")
	for path in [legacy_path, configured_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)


func test_save_path_supports_an_override_and_an_empty_configuration() -> void:
	check_eq(LegacySave.new(PANCAKE, PATH).path, PATH, "显式传入的测试路径优先")
	var shop: SpecShop = PANCAKE.duplicate(true)
	shop.save_file = ""
	check_eq(LegacySave.new(shop).path, ShopSave.path_for(shop.id), "没有配置文件名时仍按店铺 id 存档")
