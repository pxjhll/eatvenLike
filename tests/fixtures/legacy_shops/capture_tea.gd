extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const LegacySave := preload("res://tests/fixtures/legacy_shops/reference_save.gd")
## Frozen before extracting shared staff. Never overwrite an existing baseline.

const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/tea.tres")
const Content := preload("res://game/rules/shop_content_contract.gd")
const BASELINE := "res://tests/baselines/tea_modularity.json"
const FIXTURES := "res://tests/fixtures/tea_modularity/"

func _initialize() -> void:
	var errors := preload("res://tests/error_counter.gd").new()
	OS.add_logger(errors)
	var failed := false
	if "--write-baseline" in OS.get_cmdline_user_args():
		if FileAccess.file_exists(BASELINE):
			print("Refusing to overwrite the frozen tea baseline")
			failed = true
		else:
			var data := capture()
			failed = data.sold <= 0 or data.walking_samples <= 0
			if not failed:
				_write_json(BASELINE,data)
				print("Frozen tea: %d sales, %d walking samples, %d events" % [data.sold,data.walking_samples,data.events.size()])
	elif "--write-save-fixtures" in OS.get_cmdline_user_args():
		failed = not write_save_fixtures()
	else:
		if not FileAccess.file_exists(BASELINE):
			print("Missing frozen tea baseline")
			failed = true
		else:
			var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
			failed = capture() != expected
			print("TEA TRACE: " + ("FAIL" if failed else "matches frozen original"))
	for error in errors.take():
		failed = true
		print("RUNTIME: " + error)
	OS.remove_logger(errors)
	quit(1 if failed else 0)

static func opened() -> ShopRules:
	var rules := LegacyRules.new(TEA)
	assert(rules.unlock("lemonade").is_empty())
	rules.gold = 20000.0
	assert(rules.unlock("boil").is_empty())
	assert(rules.unlock_box("tea_leaf").is_empty())
	assert(rules.unlock("seal").is_empty())
	assert(rules.unlock("mix").is_empty())
	assert(rules.unlock_box("milk").is_empty())
	assert(rules.unlock("press").is_empty())
	assert(rules.unlock("topping").is_empty())
	for unused in 3: assert(rules.upgrade("topping").is_empty())
	assert(rules.hire().is_empty())
	assert(rules.hire().is_empty())
	for worker in rules.roster:
		if not worker.deployed: assert(rules.deploy_worker(worker.id).is_empty())
	return rules

static func digest(value: Variant) -> String:
	return var_to_bytes(value).hex_encode().sha256_text()

static func capture() -> Dictionary:
	var rules := opened()
	var data := trajectory(rules,600)
	data["sample_seconds"] = 10
	data["duration"] = 600
	data["content"] = Content.describe(TEA)
	return _json_record(data)

static func trajectory(rules: ShopRules, seconds: int) -> Dictionary:
	var events: Array = []
	var listener := func(e: Dictionary) -> void:
		if not String(e.name).begins_with("tick_"):
			events.append({"clock":rules.clock,"name":String(e.name),"data_sha256":digest(e.data)})
	rules.events.on("*",listener)
	var snapshots: Array = []
	var walking_samples := 0
	for i in int(seconds / ShopRules.STEP):
		rules.step(ShopRules.STEP)
		if rules.workers.any(func(w: Dictionary) -> bool: return w.walking): walking_samples += 1
		if (i+1) % 100 == 0:
			snapshots.append({"clock":rules.clock,"state_sha256":digest(rules.to_dict())})
	rules.events.off("*",listener)
	return _json_record({"snapshots":snapshots,"events":events,"sold":rules.sold,"walking_samples":walking_samples})

static func _json_record(data: Dictionary) -> Dictionary:
	# Compare the published JSON representation. Full simulation bytes remain
	# exact in the hashes; JSON clocks and integer types otherwise round-trip.
	return JSON.parse_string(JSON.stringify(data,"\t",false))

static func write_save_fixtures() -> bool:
	for name in ["unopened.json","active.json","continuations.json"]:
		if FileAccess.file_exists(FIXTURES+name):
			print("Refusing to overwrite old-save fixture: "+name)
			return false
	assert(DirAccess.make_dir_recursive_absolute(FIXTURES) == OK)
	var unopened := LegacyRules.new(TEA)
	assert(LegacySave.new(TEA,FIXTURES+"unopened.json").save_game(unopened,1.5,["opening"]) == OK)
	var active := opened()
	var seen := false
	for unused in 1200:
		active.step(ShopRules.STEP)
		if not active.orders.is_empty() and active.workers.any(func(w: Dictionary) -> bool: return w.walking):
			seen = true
			break
	assert(seen,"Old-save fixture must include an order and moving worker")
	assert(LegacySave.new(TEA,FIXTURES+"active.json").save_game(active,2.0,["opening","boil"]) == OK)
	_write_json(FIXTURES+"continuations.json",{
		"source":"9bc1b20364e239e8719e0511be2c1a4d824e3601",
		"content":Content.describe(TEA),
		"unopened":trajectory(unopened,60),
		"active":trajectory(active,60),
	})
	print("Frozen original unopened/active ShopSave files and 60-second continuations")
	return true

static func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	assert(file != null, "Cannot write "+path)
	file.store_string(JSON.stringify(data,"\t",false)+"\n")
