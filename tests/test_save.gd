extends "res://tests/test_case.gd"
## 存档文件与 Profile。

const TEST_PATH := "user://test_save.json"


func test_save_file_roundtrip() -> void:
	var sim := make_sim()
	sim.run_seconds(77.7)
	var profile := Profile.create(load(CATALOG))
	profile.record_shop("bakery", 300, 412.5)
	var service := SaveService.new(TEST_PATH)
	check_eq(service.save({"profile": profile.to_dict(), "shop": sim.to_dict()}), OK, "写入成功")
	check(not FileAccess.file_exists(TEST_PATH + ".tmp"), "临时文件已替换")
	var data := service.load_data()
	check_eq(int(data.schema_version), SaveService.SCHEMA_VERSION, "带 schema_version")
	var loaded := Profile.from_dict(data.profile)
	check_eq(loaded.to_dict(), profile.to_dict(), "Profile 读回一致")
	var resumed := make_sim()
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
