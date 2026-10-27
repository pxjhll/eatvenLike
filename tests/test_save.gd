extends "res://tests/test_case.gd"
## 存档文件与 Profile。

const TEST_PATH := "user://test_save.json"


func test_save_file_roundtrip() -> void:
	var sim := running_tea()
	sim.run_seconds(77.7)
	var profile := Profile.create(load(CATALOG))
	profile.record_shop("tea", 300, 412.5)
	var service := SaveService.new(TEST_PATH)
	check_eq(service.save({"profile": profile.to_dict(), "shop": sim.to_dict()}), OK, "写入成功")
	check(not FileAccess.file_exists(TEST_PATH + ".tmp"), "临时文件已替换")
	var data := service.load_data()
	check_eq(int(data.schema_version), SaveService.SCHEMA_VERSION, "带 schema_version")
	var loaded := Profile.from_dict(data.profile)
	check_eq(loaded.to_dict(), profile.to_dict(), "Profile 读回一致")
	var resumed := make_sim(kitchen_copy())
	resumed.load_dict(data.shop)
	check_eq(state_json(resumed), state_json(sim), "店内状态读回一致")
	service.delete()


func test_missing_save_is_empty() -> void:
	var service := SaveService.new("user://no_such_save.json")
	check(service.load_data().is_empty(), "没有存档时返回空")


func test_corrupt_save_is_kept() -> void:
	var dir := "user://corrupt_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var service := SaveService.new(dir + "/save.json")
	var f := FileAccess.open(service.path, FileAccess.WRITE)
	f.store_string("{ 不是 JSON")
	f.close()
	check(service.load_data().is_empty(), "坏档读出来是空")
	check(not FileAccess.file_exists(service.path), "坏档已从原位置移走")
	var backups := DirAccess.get_files_at(dir)
	check_eq(backups.size(), 1, "坏档留了一份底")
	check_eq(service.save({"profile": {}}), OK, "之后正常存档")
	check_eq(DirAccess.get_files_at(dir).size(), 2, "新存档没有盖掉坏档")
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + name)
	DirAccess.remove_absolute(dir)


func test_tea_save_from_before_empty_shop_restarts_the_shop() -> void:
	# PXJ-46 之前的奶茶店存档：前厅还是封口柜台，读回来会指向已经不存在的工位
	var profile := Profile.create(load(CATALOG))
	var old := {"schema_version": 1, "profile": profile.to_dict(), "shop": {"shop_id": "tea", "front_hall": {"counters": [{"slot": "seal_counter"}]}}}
	var data := SaveService.migrate(old)
	check_eq(int(data.schema_version), SaveService.SCHEMA_VERSION, "迁移到当前版本")
	check(not data.has("shop"), "旧奶茶店的店内状态丢掉，从空店重开")
	check_eq(data.profile, profile.to_dict(), "Profile 原样保留")



# PXJ-47 之前的存档：后厨是固定机位，还有老面包店。店内状态全丢，回到奶茶店空店。
func test_save_from_before_layout_mode_restarts_in_tea() -> void:
	var profile := Profile.create(load(CATALOG))
	profile.current_shop = 1
	profile.record_shop("bakery", 600, 300.0)
	profile.roster.append("cat")
	var old := {"schema_version": 2, "profile": profile.to_dict(), "shop": {"shop_id": "tea", "production": {"stations": [{"slot": "pearl_pot"}]}}}
	var data := SaveService.migrate(old)
	check_eq(int(data.schema_version), 3, "迁移到第 3 版")
	check(not data.has("shop"), "旧的店内状态丢掉")
	var loaded := Profile.from_dict(data.profile)
	check_eq(loaded.current_shop, 0, "当前店回到奶茶店")
	check(not "bakery" in loaded.completed_shops, "完成列表里去掉了已删除的面包店")
	check("cat" in loaded.roster, "名册照留")
	var catalog: GameCatalog = load(CATALOG)
	check_eq(catalog.shops[loaded.current_shop].id, "tea", "读回来开的是奶茶店")
