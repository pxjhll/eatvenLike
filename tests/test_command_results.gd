extends "res://tests/test_case.gd"

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")

class PoisonRules extends ShopRules:
	var legacy_calls := 0
	func role_room(_post: String, _exclude_id := -1) -> String:
		legacy_calls += 1
		return "poison"
	func upgrade_error(_key: String) -> String:
		legacy_calls += 1
		return "poison"
	func placement_error(_id: int, _post: String, _point := Vector2.INF) -> String:
		legacy_calls += 1
		return "poison"

func _ready(shop: SpecShop = TEA) -> ShopRules:
	var rules := ShopRules.new(shop, 17)
	rules.gold = 1e8
	for stage in shop.stages: rules.call("execute_command", "unlock", {"id": stage.stations[0]})
	return rules

func _execute_checked(rules: ShopRules, command: String, arguments: Dictionary = {}) -> Dictionary:
	var bytes := var_to_bytes(rules.to_dict())
	var status: Dictionary = rules.call("command_status", command, arguments)
	check_eq(status.code, "ok", command + " successful check")
	check_eq(var_to_bytes(rules.to_dict()), bytes, command + " successful check is read only")
	var names := {"unlock": "unlocked", "unlock_box": "box", "upgrade": "upgraded", "buy_seat": "seat", "send_flyers": "flyer",
		"hire": "hired", "deploy_worker": "deployed", "place_worker": "placed", "recall_worker": "recalled", "buy_connection": "connection", "answer_event": "event_answered"}
	var received: Array = []
	var listener := func(data: Dictionary) -> void: received.append(data)
	rules.events.on(names[command], listener)
	var result: Dictionary = rules.call("execute_command", command, arguments)
	rules.events.off(names[command], listener)
	check_eq(received.size(), 1, command + " emits its main event exactly once")
	return result

func _reject(rules: ShopRules, command: String, arguments: Dictionary, code: String, params: Dictionary = {}) -> void:
	var bytes := var_to_bytes(rules.to_dict())
	var aliases := [rules.workers, rules.roster, rules.stations, rules.levels, rules.boxes, rules.unlocked,
		rules.events, rules.events.log, rules.rng, rules.event_rng, rules.mods, rules.mods.entries, rules.pending_events]
	for method in ["command_status", "execute_command"]:
		var status: Dictionary = rules.call(method, command, arguments)
		check_eq(status.code, code, command + " explicit rejection")
		check_eq(status.params.command, command, "Command metadata")
		for key in params: check_eq(status.params.get(key), params[key], command + " parameter " + key)
		check_eq(var_to_bytes(rules.to_dict()), bytes, command + " rejection preserves bytes")
	var after := [rules.workers, rules.roster, rules.stations, rules.levels, rules.boxes, rules.unlocked,
		rules.events, rules.events.log, rules.rng, rules.event_rng, rules.mods, rules.mods.entries, rules.pending_events]
	for index in aliases.size(): check(is_same(aliases[index], after[index]), command + " rejected identity %d" % index)

func _api(rules: ShopRules) -> bool:
	var exists := rules.has_method("command_status") and rules.has_method("execute_command")
	check(exists, "ShopRules exposes canonical command_status and execute_command")
	return exists

func test_canonical_gold_stage_and_atomic_requests() -> void:
	var rules := ShopRules.new(TEA, 17)
	if not _api(rules): return
	rules.gold = 0.0
	var before := var_to_bytes(rules.to_dict())
	check_eq(rules.call("command_status", "unlock", {"id": "lemonade"}),
		{"code": "insufficient_gold", "params": {"command": "unlock", "id": "lemonade", "required": TEA.stages[0].cost}}, "Gold has explicit required amount")
	check_eq(rules.call("command_status", "unlock", {"id": "boil"}).code, "shop_not_open", "Opening precedes later stage checks")
	for request in [["unknown", {}], ["unlock", {}], ["unlock", {"id": 2}], ["unlock", {"id": "lemonade", "extra": true}]]:
		check(rules.call("execute_command", request[0], request[1]).code != "ok", "Malformed request fails")
	check_eq(var_to_bytes(rules.to_dict()), before, "Checks and rejected execution leave exact state")

func test_canonical_commit_once_and_detached_results() -> void:
	var rules := ShopRules.new(TEA, 17)
	if not _api(rules): return
	var gold := rules.gold
	var observed: Array = []
	rules.events.on("unlocked", func(data: Dictionary) -> void: observed.append(data))
	var status: Dictionary = rules.call("command_status", "unlock", {"id": "lemonade"})
	check_eq(status.code, "ok", "Opening succeeds")
	status.params.id = "poison"
	var result: Dictionary = rules.call("execute_command", "unlock", {"id": "lemonade"})
	check_eq(result.code, "ok", "Execution succeeds")
	check_eq(rules.gold, gold - TEA.stages[0].cost, "Opening debits exactly once")
	check_eq(observed.size(), 1, "Opening broadcasts once")
	result.params.id = "poison"
	check(rules.station_unlocked("lemonade"), "Caller cannot mutate unlocked state")
	check_eq(rules.call("execute_command", "unlock", {"id": "lemonade"}).code, "station_already_unlocked", "Repeat rejects")
	check_eq(observed.size(), 1, "Reject never broadcasts")

func test_all_commands_validate_schema_and_preserve_live_aliases() -> void:
	var rules := ShopRules.new(TEA, 17)
	if not _api(rules): return
	var commands := {"unlock": {"id": "missing"}, "unlock_box": {"material": "missing"}, "upgrade": {"key": "missing"},
		"buy_seat": {}, "send_flyers": {}, "hire": {}, "deploy_worker": {"id": -1},
		"place_worker": {"id": -1, "post": ""}, "recall_worker": {"id": -1}, "buy_connection": {"id": "missing"}, "answer_event": {"choice": -1}}
	var before := var_to_bytes(rules.to_dict())
	var identities := [rules.workers, rules.roster, rules.workers[0], rules.levels, rules.mods, rules.mods.entries,
		rules.events, rules.events.log, rules.rng, rules.event_rng, rules.pending_events, rules.stations]
	for command in commands:
		var arguments: Dictionary = commands[command].duplicate()
		arguments.extra = true
		for method in ["command_status", "execute_command"]:
			var status: Dictionary = rules.call(method, command, arguments)
			check_eq(status, {"code": "invalid_argument", "params": {"command": command, "argument": "extra"}}, "Extra argument for " + command)
			for argument in commands[command]:
				var missing: Dictionary = commands[command].duplicate()
				missing.erase(argument)
				check_eq(rules.call(method, command, missing).code, "invalid_argument", "Missing required argument " + argument)
				var wrong: Dictionary = commands[command].duplicate()
				wrong[argument] = false
				check_eq(rules.call(method, command, wrong).code, "invalid_argument", "Wrong type " + argument)
	check_eq(var_to_bytes(rules.to_dict()), before, "All invalid requests preserve serialized bytes")
	var after := [rules.workers, rules.roster, rules.workers[0], rules.levels, rules.mods, rules.mods.entries,
		rules.events, rules.events.log, rules.rng, rules.event_rng, rules.pending_events, rules.stations]
	for index in identities.size(): check(is_same(identities[index], after[index]), "Preserve live identity %d" % index)

func test_all_commands_success_independent_business_outcomes() -> void:
	var rules := ShopRules.new(TEA, 17)
	if not _api(rules): return
	rules.gold = 1e8
	for stage in TEA.stages:
		check_eq(_execute_checked(rules, "unlock", {"id": stage.stations[0]}).code, "ok", "Canonical unlock")
	check_eq(rules.stage_index, TEA.stages.size() - 1, "All stages actually opened")
	check_eq(_execute_checked(rules, "unlock_box", {"material": "tea_leaf"}).code, "ok", "Canonical box")
	check(rules.boxes.tea_leaf, "Box actually owned")
	var gold := rules.gold
	var cost := rules.upgrade_cost("boil")
	check_eq(_execute_checked(rules, "upgrade", {"key": "boil"}).code, "ok", "Canonical upgrade")
	check_eq(rules.level("boil"), 2, "Actual upgraded level")
	check_eq(rules.gold, gold - cost, "Actual upgrade cost")
	var seats := rules.seats.duplicate()
	check_eq(_execute_checked(rules, "buy_seat").code, "ok", "Canonical seats")
	check(rules.seats != seats, "Seat count grows")
	check_eq(_execute_checked(rules, "send_flyers").code, "ok", "Canonical flyers")
	check(rules.flyer_wave > 0 and rules.flyer_pending > 0, "Flyer state set")
	check_eq(_execute_checked(rules, "hire").code, "ok", "Canonical hire")
	var worker: Dictionary = rules.roster[-1]
	check(not worker.deployed, "Zoned hire waits in roster")
	check_eq(_execute_checked(rules, "deploy_worker", {"id": worker.id, "post": "boil"}).code, "ok", "Canonical deploy")
	check(worker.deployed and worker.post == "boil", "Deploy seats actual worker")
	var count := rules.events.log.size()
	check_eq(rules.call("execute_command", "deploy_worker", {"id": worker.id, "post": "invalid"}).code, "ok", "Deployed no-op precedes post check")
	check_eq(rules.events.log.size(), count, "No-op emits nothing")
	check_eq(_execute_checked(rules, "place_worker", {"id": worker.id, "post": ""}).code, "ok", "Canonical place")
	check_eq(worker.post, "", "Placement removes seat")
	check_eq(_execute_checked(rules, "recall_worker", {"id": worker.id}).code, "ok", "Canonical recall")
	check(not worker.deployed and not worker in rules.workers, "Recall updates actual deployment")
	var connection: SpecConnection = TEA.connections[0]
	check_eq(_execute_checked(rules, "buy_connection", {"id": connection.id}).code, "ok", "Canonical connection")
	check(rules.belts.has(connection.id) and rules.belt_clock[connection.id] == 0.0, "Belt state committed")
	var event := SpecEvent.new()
	event.id = "canonical"
	event.choices.assign([{"label": "yes", "cost": 9}])
	event.effects.assign([SpecEffect.make("grant_gold", "add", 20.0)])
	rules.pending_events.append(event)
	gold = rules.gold
	check_eq(_execute_checked(rules, "answer_event", {"choice": 0}).code, "ok", "Canonical event")
	check_eq(rules.gold, gold + 11.0, "Event cost/effect exactly once")
	check(rules.pending_events.is_empty(), "Event consumed")

func test_unlock_box_and_upgrade_failure_priority_and_text() -> void:
	var rules := ShopRules.new(TEA)
	if not _api(rules): return
	_reject(rules, "unlock", {"id": "absent"}, "unknown_station", {"id": "absent"})
	_reject(rules, "unlock", {"id": "supply"}, "station_already_unlocked")
	rules.unlocked.supply = false
	_reject(rules, "unlock", {"id": "supply"}, "station_not_unlockable")
	_reject(rules, "unlock", {"id": "mix"}, "shop_not_open")
	_reject(rules, "unlock_box", {"material": "absent"}, "unknown_box")
	_reject(rules, "unlock_box", {"material": "tea_leaf"}, "station_required", {"station": "boil"})
	check_eq(rules.box_error("tea_leaf"), "请先解锁煮茶机", "Box dependency legacy text")
	_reject(rules, "upgrade", {"key": "absent"}, "no_upgrade")
	_reject(rules, "upgrade", {"key": "boil"}, "station_required", {"station": "boil"})
	_reject(rules, "upgrade", {"key": "flyer"}, "shop_not_open")
	rules.execute_command("unlock", {"id": "lemonade"})
	rules.gold = 0
	_reject(rules, "unlock", {"id": "mix"}, "stage_required", {"stage": 2})
	check_eq(rules.unlock_error("mix"), "请先解锁封口机", "Unlock predecessor text")
	_reject(rules, "unlock", {"id": "boil"}, "insufficient_gold", {"required": TEA.stages[1].cost})
	rules = _ready()
	rules.gold = 0
	_reject(rules, "unlock_box", {"material": "tea_leaf"}, "insufficient_gold", {"required": 20})
	rules.gold = 1e8
	rules.execute_command("unlock_box", {"material": "tea_leaf"})
	_reject(rules, "unlock_box", {"material": "tea_leaf"}, "box_already_unlocked")
	# The supply track itself has no machine track; box requirement precedes gold.
	_reject(rules, "upgrade", {"key": "supply/milk"}, "box_required", {"material": "milk"})
	var requiring := ""
	for station in TEA.stations:
		for material in station.materials:
			if material.track != null and material.track.requires_level > 1:
				requiring = station.id + "/" + material.id
				break
		if not requiring.is_empty(): break
	check(not requiring.is_empty(), "Fixture includes machine level requirement")
	if not requiring.is_empty():
		_reject(rules, "upgrade", {"key": requiring}, "station_level_required", {"station": requiring.get_slice("/", 0), "required_level": rules.track_of(requiring).requires_level})
	rules.gold = 0
	_reject(rules, "upgrade", {"key": "boil"}, "insufficient_gold", {"required": rules.upgrade_cost("boil")})
	rules.levels.boil = rules.track_of("boil").levels.size() + 1
	_reject(rules, "upgrade", {"key": "boil"}, "max_level")
	check_eq(rules.upgrade_error("boil"), "已满级", "Max beats insufficient gold")

func test_seat_flyer_hire_and_event_rejections_both_modes() -> void:
	var closed := ShopRules.new(TEA)
	if not _api(closed): return
	for command in ["buy_seat", "send_flyers"]: _reject(closed, command, {}, "shop_not_open")
	var rules := _ready()
	rules.gold = 0
	_reject(rules, "buy_seat", {}, "insufficient_gold", {"required": rules.seat_cost()})
	_reject(rules, "hire", {}, "insufficient_gold", {"required": rules.hire_cost()})
	rules.gold = 1e8
	while rules.seat_cost() >= 0: rules.execute_command("buy_seat")
	_reject(rules, "buy_seat", {}, "seats_full")
	rules = ShopRules.new(PANCAKE)
	rules.gold = 1e8
	rules.execute_command("unlock", {"id": "soy_milk"})
	while rules.command_status("buy_seat").code == "ok": rules.execute_command("buy_seat")
	_reject(rules, "buy_seat", {}, "seat_stage_required")
	rules = _ready()
	rules.execute_command("send_flyers")
	_reject(rules, "send_flyers", {}, "flyer_active", {"seconds": ceili(rules.flyer_wave)})
	rules.flyer_wave = 0
	rules.flyer_wait = 2.1
	_reject(rules, "send_flyers", {}, "flyer_cooldown", {"seconds": 3})
	var solo := ShopRules.new(PANCAKE)
	_reject(solo, "place_worker", {"id": -1, "post": "bad"}, "reassignment_disabled")
	solo.gold = 0
	_reject(solo, "hire", {}, "staff_full", {"count": 1})
	solo = _ready(PANCAKE)
	for unused in 3: check_eq(solo.execute_command("hire").code, "ok", "Solo hire succeeds")
	check_eq(solo.workers.size(), 4, "Unzoned hires deploy automatically")
	solo.gold = 0
	_reject(solo, "hire", {}, "hire_exhausted")
	solo.execute_command("send_flyers")
	_reject(solo, "send_flyers", {}, "flyer_cooldown", {"seconds": ceili(solo.flyer_ready_at - solo.clock)})
	_reject(rules, "answer_event", {"choice": -1}, "event_missing")
	var event := SpecEvent.new()
	event.id = "cost"
	event.choices.assign([{"cost": 12, "accept": false}])
	rules.pending_events.append(event)
	rules.gold = 0
	_reject(rules, "answer_event", {"choice": -1}, "invalid_event_choice")
	_reject(rules, "answer_event", {"choice": 1}, "invalid_event_choice")
	_reject(rules, "answer_event", {"choice": 0}, "insufficient_gold", {"required": 12})
	rules.gold = 12
	check_eq(rules.execute_command("answer_event", {"choice": 0}).code, "ok", "Decline consumes cost and card")
	check_eq(rules.gold, 0.0, "Decline debit")
	check(rules.pending_events.is_empty(), "Decline consumed")

func test_worker_post_failures_auto_choice_and_canonical_adapter_trap() -> void:
	var rules := _ready()
	if not _api(rules): return
	for command in ["deploy_worker", "place_worker", "recall_worker"]:
		var args := {"id": -9}
		if command == "place_worker": args.post = "invalid"
		_reject(rules, command, args, "unknown_worker", {"id": -9})
	rules.execute_command("hire")
	_reject(rules, "recall_worker", {"id": 2}, "worker_already_waiting", {"id": 2})
	_reject(rules, "deploy_worker", {"id": 2, "post": "invalid"}, "not_seatable")
	_reject(rules, "deploy_worker", {"id": 2, "post": "counter"}, "front_full", {"count": rules.front_slots()})
	_reject(rules, "place_worker", {"id": 2, "post": "invalid"}, "invalid_post")
	rules.unlocked.boil = false
	_reject(rules, "place_worker", {"id": 2, "post": "boil"}, "station_required", {"station": "boil"})
	rules.unlocked.boil = true
	check_eq(rules.execute_command("deploy_worker", {"id": 2, "post": "boil"}).code, "ok", "Seat worker")
	rules.execute_command("hire")
	_reject(rules, "deploy_worker", {"id": 3, "post": "boil"}, "post_occupied")
	_reject(rules, "place_worker", {"id": 3, "post": "boil"}, "post_occupied")
	check_eq(rules.deploy_worker(3, "boil"), "这里已经有人了", "Deploy occupied text")
	check_eq(rules.placement_error(3, "boil"), "岗位已有员工", "Place occupied text")
	_reject(rules, "place_worker", {"id": 2, "post": "", "point": Vector2(-1e5, -1e5)}, "position_unreachable")
	for point in [Vector2(INF, 0), Vector2(-INF, -INF), Vector2(NAN, 0)]:
		_reject(rules, "place_worker", {"id": 2, "post": "", "point": point}, "invalid_argument", {"argument": "point"})
	check_eq(rules.command_status("place_worker", {"id": 2, "post": "", "point": Vector2.INF}).code, "ok", "Infinity sentinel accepted")
	var trapped := PoisonRules.new(TEA, 17)
	trapped.gold = 1e8
	trapped.execute_command("hire")
	_reject(trapped, "deploy_worker", {"id": 2}, "kitchen_full", {"count": 0})
	trapped.execute_command("recall_worker", {"id": 1})
	check_eq(trapped.command_status("deploy_worker", {"id": 2}).params.post, "counter", "Auto deployment resolves front")
	check_eq(trapped.execute_command("deploy_worker", {"id": 2}).code, "ok", "Auto deploy uses code helpers")
	check_eq(trapped.worker_by_id(2).post, "counter", "Actual auto post")
	trapped.execute_command("unlock", {"id": "lemonade"})
	check_eq(trapped.execute_command("upgrade", {"key": "lemonade"}).code, "ok", "Upgrade ignores poisoned adapter")
	check_eq(trapped.execute_command("place_worker", {"id": 2, "post": "counter"}).code, "ok", "Placement ignores poisoned adapter")
	check_eq(trapped.legacy_calls, 0, "Canonical paths never call String adapters")

func test_connection_status_codes_priority_and_legacy_rows() -> void:
	var rules := ShopRules.new(TEA)
	if not _api(rules): return
	_reject(rules, "buy_connection", {"id": "absent"}, "unknown_connection", {"id": "absent"})
	_reject(rules, "buy_connection", {"id": "seal_to_shelf"}, "stage_required", {"stage": 2})
	check_eq(rules.connection_error("absent"), "未知传送带", "Unknown connection legacy text")
	var disabled_shop: SpecShop = TEA.duplicate(true)
	disabled_shop.connections[0].enabled = false
	var disabled := ShopRules.new(disabled_shop)
	_reject(disabled, "buy_connection", {"id": disabled_shop.connections[0].id}, "unknown_connection")
	rules = _ready()
	rules.gold = 0
	_reject(rules, "buy_connection", {"id": "seal_to_shelf"}, "insufficient_gold", {"required": 250})
	rules.gold = 250
	rules.execute_command("buy_connection", {"id": "seal_to_shelf"})
	_reject(rules, "buy_connection", {"id": "seal_to_shelf"}, "connection_already_built", {"id": "seal_to_shelf"})
	check_eq(rules.connection_error("seal_to_shelf"), "这里已经装了传送带", "Owned connection legacy text")
	for row in rules.connection_rows():
		check(row.has("status") and row.has("error"), "Rows carry canonical status and legacy display text")
		if row.id == "seal_to_shelf": check_eq(row.status.code, "connection_already_built", "Owned row status")

func test_malformed_track_keys_cannot_reach_a_commit() -> void:
	var rules := _ready()
	if not _api(rules): return
	for key in ["supply/tea_leaf/extra", "boil/", "/", "staff//front", "staff/"]:
		_reject(rules, "upgrade", {"key": key}, "no_upgrade")
	# Unzoned staff uses the empty zone track as the ordinary key staff/.
	var solo := _ready(PANCAKE)
	check(solo.levels.has("staff/"), "Solo has unzoned upgrade track")
	check_eq(solo.execute_command("upgrade", {"key": "staff/"}).code, "ok", "Empty zone suffix is valid")

func test_result_factories_and_catalog_are_detached() -> void:
	if not FileAccess.file_exists("res://game/rules/rule_command_result.gd"):
		check(false, "Result helper exists")
		return
	var result: Script = load("res://game/rules/rule_command_result.gd")
	var params := {"command": "test", "nested": [{"id": "first"}]}
	var status: Dictionary = result.failure("insufficient_gold", params)
	status.params.nested[0].id = "mutated"
	check_eq(params.nested[0].id, "first", "Factory deep copies nested input")
	check(not result.is_ok(status), "Failure code is authoritative")
	check(result.is_ok(result.success()), "Only ok succeeds")
	var other: Dictionary = result.success()
	other.params.changed = true
	check(not result.success().params.has("changed"), "Fresh success data")
	var catalog: Script = load("res://content/ui/rule_command_text.gd")
	var gold := {"code": "insufficient_gold", "params": {"required": 42, "command": "hire"}}
	check_eq(catalog.format(gold, TEA), "金币不足，需要 42", "Gold catalog preserves legacy text")
	check_eq(catalog.format(gold, TEA, {"insufficient_gold": ""}), "", "Empty override is allowed")
	check(not result.is_ok(gold), "Empty failure text never means success")
	check_eq(gold.params, {"required": 42, "command": "hire"}, "Formatting does not mutate params")

func test_optional_arguments_wrong_types_and_success_status_freshness() -> void:
	var rules := _ready()
	if not _api(rules): return
	_reject(rules, "deploy_worker", {"id": 1, "post": 0}, "invalid_argument", {"argument": "post"})
	_reject(rules, "place_worker", {"id": 1, "post": "", "point": "point"}, "invalid_argument", {"argument": "point"})
	_reject(rules, "unlock", {"id": StringName("lemonade")}, "invalid_argument", {"argument": "id"})
	_reject(rules, "hire", {2: "unexpected"}, "invalid_argument", {"argument": "2"})
	_reject(rules, "unknown", {}, "unknown_command")
	var first: Dictionary = rules.command_status("deploy_worker", {"id": 1})
	first.params.post = "poison"
	check_eq(rules.command_status("deploy_worker", {"id": 1}).params.post, "", "Every status is fresh")
