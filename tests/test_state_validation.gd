extends "res://tests/test_case.gd"

const TEA = preload("res://tests/fixtures/legacy_shops/tea.tres")
const PANCAKE = preload("res://tests/fixtures/legacy_shops/pancake.tres")
const NOODLE = preload("res://tests/fixtures/noodle/shop.tres")
var _paths: Array[String] = []

class FailedBackup extends ShopSave:
	func _backup_corrupt() -> Error:
		last_error += "；测试：备份失败"
		return ERR_CANT_CREATE

func cleanup() -> void:
	for path in _paths:
		for file in DirAccess.get_files_at(path.get_base_dir()):
			if file.begins_with(path.get_file()): DirAccess.remove_absolute(path.get_base_dir().path_join(file))

func _path() -> String:
	var path := "user://test_state_validation_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	_paths.append(path)
	return path

func _write_payload(path: String, data: Dictionary) -> String:
	var bytes := var_to_bytes(data)
	var text := JSON.stringify({"format": ShopSave.FORMAT, "version": ShopSave.VERSION, "shop": data.shop,
		"content": preload("res://game/rules/shop_content_contract.gd").describe(TEA), "speed": 1.0, "state": Marshalls.raw_to_base64(bytes), "state_sha256": bytes.hex_encode().sha256_text()})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return text

func _rejected(rules: ShopRules, data: Dictionary, label: String) -> void:
	var before := var_to_bytes(rules.to_dict())
	var nav := rules.nav
	var events := rules.events
	var mods := rules.mods
	var random := rules.rng
	var calls := [0]
	var listener := func(_data: Dictionary) -> void: calls[0] += 1
	events.on("validation_probe", listener)
	var errors := preload("res://tests/error_counter.gd").new()
	OS.add_logger(errors)
	var error := rules.load_dict(data)
	OS.remove_logger(errors)
	check(not error.is_empty(), label + " 返回明确错误")
	check_eq(errors.take().size(), 0, label + " 没有运行时错误")
	check(var_to_bytes(rules.to_dict()) == before, label + " 状态原子保留")
	check(rules.nav == nav and rules.events == events and rules.mods == mods and rules.rng == random, label + " 保留对象和订阅")
	rules.events.emit("validation_probe")
	check_eq(calls[0], 1, label + " 外部订阅继续工作")
	events.off("validation_probe", listener)

func test_empty_rng_does_not_partially_reset_live_rules() -> void:
	var rules := ShopRules.new(TEA)
	rules.unlock(rules.next_unlock())
	rules.run(12.0)
	var data := rules.to_dict()
	data.gold += 900.0
	data.rng = []
	_rejected(rules, data, "rng=[]")

func test_fractional_frame_accumulator_roundtrips_with_guides() -> void:
	var rules := ShopRules.new(TEA)
	rules.unlock(rules.next_unlock())
	# GUI advances by fractional frame deltas, unlike the baseline's exact STEP.
	for unused in 2: rules.step(0.25)
	check(rules._accumulator < 0.0, "真实分帧会产生极小负余数，覆盖引导回归")
	var before := rules.to_dict()
	var path := _path()
	var store := ShopSave.new(TEA, path)
	check_eq(store.save_game(rules, 1.0, ["opening", "lost_machine"]), OK, "保存分帧状态")
	var resumed := store.load_game()
	check_eq(store.last_error, "", "有限浮点余数合法，不隔离正常存档")
	check_eq(store.loaded_guides, ["opening", "lost_machine"], "重开保留引导状态")
	check(var_to_bytes(resumed.to_dict()) == var_to_bytes(before), "余数原样恢复，不改变逐帧状态")
	rules.step(0.25)
	resumed.step(0.25)
	check(var_to_bytes(resumed.to_dict()) == var_to_bytes(rules.to_dict()), "恢复后逐帧一致")
	var invalid := rules.to_dict()
	invalid._accumulator = -0.01
	_rejected(rules, invalid, "超过步进浮点容差的负余数")

func test_nested_invalid_states_are_rejected() -> void:
	var rules := ShopRules.new(PANCAKE)
	rules.unlock(rules.next_unlock())
	rules.run(12.0)
	var base := rules.to_dict()
	var cases: Array = []
	var data := base.duplicate(true)
	data.event_rng = ["seed", 3]
	cases.append(data)
	data = base.duplicate(true)
	data.workers = [999999]
	cases.append(data)
	data = base.duplicate(true)
	data.roster[0].path_index = -1
	cases.append(data)
	data = base.duplicate(true)
	data.roster[0].step = 999999
	cases.append(data)
	data = base.duplicate(true)
	data.stations[data.stations.keys()[0]].reserved_in = -1
	cases.append(data)
	data = base.duplicate(true)
	data.orders = [42]
	cases.append(data)
	data = base.duplicate(true)
	data.queue = [999999]
	cases.append(data)
	data = base.duplicate(true)
	data.mods[0].value = NAN
	cases.append(data)
	for index in cases.size(): _rejected(rules, cases[index], "nested %d" % index)

func test_valid_midgame_states_resume_for_all_shop_specs() -> void:
	for shop in [TEA, PANCAKE, NOODLE]:
		var source := ShopRules.new(shop)
		source.unlock(source.next_unlock())
		source.run(45.0)
		var target := ShopRules.new(shop)
		check_eq(target.load_dict(source.to_dict()), "", shop.id + " 恢复")
		check(var_to_bytes(target.to_dict()) == var_to_bytes(source.to_dict()), shop.id + " 精确恢复")
		source.run(20.0)
		target.run(20.0)
		check(var_to_bytes(target.to_dict()) == var_to_bytes(source.to_dict()), shop.id + " 继续逐帧一致")
		if not target.workers.is_empty():
			target.workers[0].name = "alias check"
			check_eq(target.roster[0].name, "alias check", "在岗员工和名册共用对象")

func test_valid_envelope_invalid_semantics_is_quarantined() -> void:
	var path := _path()
	var data := ShopRules.new(TEA).to_dict()
	data.gold = 900000.0
	data.rng = []
	var original := _write_payload(path, data)
	var store := ShopSave.new(TEA, path)
	var errors := preload("res://tests/error_counter.gd").new()
	OS.add_logger(errors)
	var restored := store.load_game()
	OS.remove_logger(errors)
	check_eq(errors.take().size(), 0, "真实二进制损坏状态不报运行时错误")
	check(store.last_error.contains("rng"), "业务状态错误包含字段路径")
	check_eq(restored.gold, float(TEA.start_gold), "只返回安全新店")
	var backups := []
	for file in DirAccess.get_files_at("user://"):
		if file.begins_with(path.get_file() + ".corrupt-"): backups.append("user://" + file)
	check_eq(backups.size(), 1, "原件隔离一次")
	if not backups.is_empty(): check_eq(FileAccess.get_file_as_string(backups[0]), original, "隔离文件字节完全保留")
	check_eq(store.save_game(restored), OK, "隔离成功后可保存新店")

func test_failed_quarantine_blocks_later_blind_save() -> void:
	var path := _path()
	var data := ShopRules.new(TEA).to_dict()
	data.rng = []
	var original := _write_payload(path, data)
	var store := FailedBackup.new(TEA, path)
	var restored := store.load_game()
	check(store.last_error.contains("备份失败"), "备份失败明确报告")
	check_eq(store.save_game(restored), ERR_UNAVAILABLE, "备份失败阻止自动写入")
	check_eq(FileAccess.get_file_as_string(path), original, "原始损坏文件保留")

func test_direct_save_also_preserves_existing_semantic_corruption() -> void:
	var data := ShopRules.new(TEA).to_dict()
	data.rng = []
	for fail_backup in [false, true]:
		var path := _path()
		var original := _write_payload(path, data)
		var store: ShopSave = FailedBackup.new(TEA, path) if fail_backup else ShopSave.new(TEA, path)
		var error := store.save_game(ShopRules.new(TEA))
		if fail_backup:
			check_eq(error, ERR_CANT_CREATE, "直接保存先隔离损坏状态，报告隔离错误")
			check_eq(FileAccess.get_file_as_string(path), original, "直接保存不覆盖无法隔离的原件")
			check_eq(store.save_game(ShopRules.new(TEA)), ERR_UNAVAILABLE, "后续保存仍被阻止")
		else:
			check_eq(error, OK, "隔离后直接保存成功")
			var found := false
			for file in DirAccess.get_files_at("user://"):
				if file.begins_with(path.get_file() + ".corrupt-"):
					found = FileAccess.get_file_as_string("user://" + file) == original
			check(found, "直接保存也完整保留损坏原件")

func test_successful_restore_binds_event_callback_to_live_rules() -> void:
	var shop: SpecShop = TEA.duplicate(true)
	var event := SpecEvent.new()
	event.id = "restore_probe"
	event.trigger = "restore_probe"
	event.chance = 1.0
	event.effects.append(SpecEffect.make("grant_gold", "add", 7.0))
	shop.events.append(event)
	var source := ShopRules.new(shop)
	var target := ShopRules.new(shop)
	check_eq(target.load_dict(source.to_dict()), "", "恢复事件定义")
	var before := target.gold
	target.events.emit("restore_probe")
	check_eq(target.gold, before + 7.0, "监听修改真正 live rules，且只触发一次")
	check(target.event_ready_at.has(event.id), "冷却写入 live rules")

func test_nested_field_types_and_references_are_rejected_without_errors() -> void:
	var rules := ShopRules.new(TEA)
	rules.gold = 100000.0
	while not rules.next_unlock().is_empty(): rules.unlock(rules.next_unlock())
	for id in rules.boxes: rules.unlock_box(id)
	rules.run(20.0)
	var base := rules.to_dict()
	for field in base.roster[0]:
		var data := base.duplicate(true)
		data.roster[0][field] = null
		_rejected(rules, data, "roster." + field)
	for field in base.stations[rules.pots[0]]:
		var data := base.duplicate(true)
		data.stations[rules.pots[0]][field] = null
		_rejected(rules, data, "station." + field)
	for field in base.mods[0]:
		var data := base.duplicate(true)
		data.mods[0][field] = null
		_rejected(rules, data, "mods." + field)
	var mutations := [
		["roster", [{"id": 1}]], ["workers", [1, 1]], ["pending_events", ["missing"]],
		["stage_index", -1], ["clock", INF], ["log", [{}]], ["diners", [{}]],
		["belt_items", [{}]], ["hire_pool", ["missing"]], ["event_rng", [1, 2, 3]]]
	for mutation in mutations:
		var data := base.duplicate(true)
		data[mutation[0]] = mutation[1]
		_rejected(rules, data, str(mutation[0]))
	var data := base.duplicate(true)
	data.roster[0].job = {"kind": "serve", "src": "missing", "dst": rules.counter_id, "item": rules.dish_ids[0], "count": 1, "priority": 1.0, "belt": "", "order_id": base.orders[0].id}
	_rejected(rules, data, "job.src dangling")
	data = base.duplicate(true)
	data.roster[0].ticket = {"dish": rules.dish_ids[0], "count": 1, "at": 9999, "phase": "carry", "wait": 0.0}
	_rejected(rules, data, "ticket.at")
	data = base.duplicate(true)
	data.roster[0].pos = Vector2(INF, 0)
	_rejected(rules, data, "position nonfinite")

func test_active_job_and_belt_storage_references_must_exist() -> void:
	var rules := ShopRules.new(TEA)
	rules.unlock(rules.next_unlock())
	var base := rules.to_dict()
	var data := base.duplicate(true)
	data.roster[0].job = {"kind": "serve", "src": rules.counter_id, "dst": rules.counter_id, "item": base.orders[0].dish, "count": 1, "priority": 1.0, "belt": "", "order_id": base.orders[0].id}
	_rejected(rules, data, "job 指向没有货槽的合法站点")
	data = base.duplicate(true)
	data.belts[TEA.connections[0].id] = true
	_rejected(rules, data, "传送带缺少时钟")

func test_operation_jobs_require_matching_machine_and_worker_phase() -> void:
	var rules := ShopRules.new(TEA)
	rules.unlock(rules.next_unlock())
	var base := rules.to_dict()
	for kind in ["pot_take", "pot_start", "stir", "work"]:
		var data := base.duplicate(true)
		var worker: Dictionary = data.roster[0]
		worker.job = {"kind": kind, "src": rules.supply_id, "dst": rules.supply_id, "item": TEA.items[0].id, "count": 1, "priority": 1.0, "belt": "", "order_id": -1}
		worker.phase = "work"
		worker.walking = false
		worker.action_left = 0.0
		worker.ticket = {}
		_rejected(rules, data, kind + " cannot operate supply")
	# A legal serve job cannot be dispatched through the machine-operation branch.
	var data := base.duplicate(true)
	data.roster[0].job = {"kind": "serve", "src": rules.supply_id, "dst": rules.counter_id, "item": base.orders[0].dish, "count": 1, "priority": 1.0, "belt": "", "order_id": base.orders[0].id}
	data.roster[0].phase = "work"
	_rejected(rules, data, "serve cannot use work phase")
	# Phase/storage restrictions also apply to a genuine pot, not only wrong IDs.
	for kind in ["pot_take", "stir"]:
		data = base.duplicate(true)
		var pot_id: String = rules.pots[0]
		var pot: Dictionary = data.stations[pot_id]
		pot.processing = 1
		pot.duration = 1.0
		pot.work_reserved = true
		pot.phase = "awaiting_take" if kind == "pot_take" else "stir"
		data.roster[0].job = {"kind": kind, "src": pot_id, "dst": pot_id, "item": pot.output.keys()[0], "count": 1, "priority": 1.0, "belt": "", "order_id": -1}
		data.roster[0].phase = "work"
		check_eq(ShopRules.new(TEA).load_dict(data), "", "合法批量锅工序可恢复 " + kind)
		pot.phase = "idle"
		_rejected(rules, data, kind + " requires matching pot phase")

func test_single_steps_require_declared_actions_and_terminal_handoff() -> void:
	var rules := ShopRules.new(PANCAKE)
	rules.unlock(rules.next_unlock())
	rules.run(3.0)
	var base := rules.to_dict()
	check(not base.roster[0].steps.is_empty(), "真实顾客生成活动工序")
	if base.roster[0].steps.is_empty(): return
	var data := base.duplicate(true)
	data.roster[0].steps[0].action = "unknown_action"
	_rejected(rules, data, "unknown single action")
	data = base.duplicate(true)
	data.roster[0].steps[0].station = rules.supply_id
	_rejected(rules, data, "take action requires counter")
	data = base.duplicate(true)
	data.roster[0].steps.pop_back()
	_rejected(rules, data, "missing terminal handoff")

func test_active_manual_work_requires_real_output_slot_without_processing_count() -> void:
	var rules := ShopRules.new(TEA)
	rules.gold = 10000000.0
	while not rules.next_unlock().is_empty(): rules.unlock(rules.next_unlock())
	for id in rules.boxes: rules.unlock_box(id)
	for unused in 7: rules.hire()
	for station in TEA.stations:
		if station.block == "topping":
			while rules.upgrade_error(station.id).is_empty(): rules.upgrade(station.id)
	for worker in rules.roster:
		if not worker.deployed: rules.deploy_worker(worker.id)
	var snapshot := {}
	var station_id := ""
	for unused in 4000:
		rules.step(0.1)
		for worker in rules.workers:
			if worker.phase == "work" and worker.job.get("kind", "") == "work":
				snapshot = rules.to_dict()
				station_id = worker.job.src
				break
		if not snapshot.is_empty(): break
	check(not snapshot.is_empty(), "真实营业进入员工加料工序")
	if snapshot.is_empty(): return
	check_eq(snapshot.stations[station_id].processing, 0, "员工工序没有自动机 processing 计数")
	var restored := ShopRules.new(TEA)
	check_eq(restored.load_dict(snapshot), "", "合法员工工序存档可恢复")
	var fallback := snapshot.duplicate(true)
	fallback.stations[station_id].processing_item = ""
	var fallback_rules := ShopRules.new(TEA)
	check_eq(fallback_rules.load_dict(fallback), "", "空产出仍允许原来的输入槽回退")
	var errors := preload("res://tests/error_counter.gd").new()
	OS.add_logger(errors)
	fallback_rules.run(20.0)
	OS.remove_logger(errors)
	check_eq(errors.take().size(), 0, "空产出回退完成工序不报错")
	rules.run(20.0)
	restored.run(20.0)
	check(var_to_bytes(restored.to_dict()) == var_to_bytes(rules.to_dict()), "正常员工工序完成后精确续跑")
	var invalid := snapshot.duplicate(true)
	var wrong_item := ""
	for item in TEA.items:
		if not invalid.stations[station_id].output.has(item.id):
			wrong_item = item.id
			break
	check(not wrong_item.is_empty(), "有合法物品不属于该设备产出")
	invalid.stations[station_id].processing_item = wrong_item
	_rejected(rules, invalid, "manual processing_item missing output slot")
