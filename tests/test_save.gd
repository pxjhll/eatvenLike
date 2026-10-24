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
