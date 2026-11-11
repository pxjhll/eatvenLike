extends SceneTree
## Real production scenes, explicit disposable sessions, and fatal runtime errors.

const Suite := preload("res://tests/test_command_ui.gd")
const TestSession := preload("res://tests/shop_test_session.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
var suite := Suite.new()
var errors := preload("res://tests/error_counter.gd").new()
var paths: Array[String] = []
var prefix := "user://command-ui-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]

class CountingStore extends ShopSave:
	var writes := 0
	func save_game(rules: ShopRules, speed := 1.0, guides: Array = []) -> Error:
		writes += 1
		return super.save_game(rules, speed, guides)

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _open(spec: SpecShop, label: String) -> Node2D:
	var rules := Suite.PoisonRules.new(spec)
	var store := CountingStore.new(spec, prefix + label + "-shop.json")
	var campaign: SpecCampaign = load("res://tests/fixtures/noodle/campaign.tres") if spec.id == "noodle" else load("res://content/campaign/campaign.tres")
	var session := TestSession.make(spec, prefix + label, rules, store, null, campaign)
	for path in [store.path, session.profile.path, session.tuning_path, session.recording_path]: paths.append(path)
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = session
	root.add_child(scene)
	# Freeze immediately, before the first await or saved-state readback.
	scene.set_process(false)
	return scene

func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void:
		print("COMMAND UI: timed out")
		quit(1))
	if not OS.get_user_data_dir().replace("\\", "/").split("/").has("session-lifecycle-userdata"):
		print("COMMAND UI: requires disposable session-lifecycle-userdata APPDATA/XDG_DATA_HOME")
		quit(1)
		return
	root.size = Vector2i(720, 1280)
	root.get_node("ShopAudio")._can_play = false
	for method in suite.get_method_list():
		if String(method.name).begins_with("test_"): suite.call(method.name)
	for translated in ["localized unrelated", ""]:
		var scene := _open(TEA, "-tea-" + str(translated.length()))
		scene.view.message_formatter = func(status: Dictionary, _shop: SpecShop) -> String:
			return "nonempty success" if status.code == "ok" else translated
		await process_frame
		await _test_tea(scene, translated)
		suite.check_eq(scene.rules.legacy_calls, 0, "all tea production paths avoid String adapters")
		scene.free()
	for spec in [load("res://content/shops/pancake/shop.tres"), load("res://tests/fixtures/noodle/shop.tres")]:
		var scene := _open(spec, "-" + spec.id)
		scene.view.message_formatter = func(_status: Dictionary, _shop: SpecShop) -> String: return ""
		await process_frame
		var opening: String = spec.stages[0].stations[0]
		scene.ui.open_station(opening)
		var button: Button = scene.ui.page_node("station").unlock_button
		_success(scene, func() -> void: button.pressed.emit(), "unlocked", "opening " + spec.id)
		suite.check(scene.rules.is_open(), "actual opening succeeds for " + spec.id)
		scene.ui.open_page("staff")
		scene._refresh(0.0)
		suite.check_eq(scene.rules.legacy_calls, 0, "third/pancake UI avoids String adapters")
		scene.free()
	await process_frame
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for error in errors.take(): suite.failures.append("runtime error: " + error)
	OS.remove_logger(errors)
	for failure in suite.failures: print("FAIL: " + failure)
	print("COMMAND UI: %d failures" % suite.failures.size())
	quit(0 if suite.failures.is_empty() else 1)

func _reject(scene: Node2D, action: Callable, label: String) -> void:
	var bytes := var_to_bytes(scene.rules.to_dict())
	var events := var_to_bytes(scene.rules.events.log)
	var pending: Array = scene.rules.pending_events.duplicate()
	var writes: int = scene.store.writes
	var saved := FileAccess.get_file_as_bytes(scene.store.path) if FileAccess.file_exists(scene.store.path) else PackedByteArray()
	action.call()
	suite.check_eq(var_to_bytes(scene.rules.to_dict()), bytes, label + " rejection preserves business state including gold")
	suite.check_eq(var_to_bytes(scene.rules.events.log), events, label + " rejection emits no events")
	suite.check_eq(scene.rules.pending_events, pending, label + " rejection preserves pending cards")
	suite.check_eq(scene.store.writes, writes, label + " rejection never saves")
	suite.check_eq(FileAccess.get_file_as_bytes(scene.store.path) if FileAccess.file_exists(scene.store.path) else PackedByteArray(), saved, label + " rejection preserves saved bytes")

func _success(scene: Node2D, action: Callable, event: String, label: String) -> void:
	var received: Array = []
	var callback := func(data: Dictionary) -> void: received.append(data)
	scene.rules.events.on(event, callback)
	var writes: int = scene.store.writes
	action.call()
	scene.rules.events.off(event, callback)
	suite.check_eq(received.size(), 1, label + " emits its business event once")
	suite.check_eq(scene.store.writes, writes + 1, label + " persists once")
	var reloaded: ShopRules = scene.store.load_game()
	suite.check_eq(reloaded.gold, scene.rules.gold, label + " saves actual gold")
	suite.check_eq(reloaded.to_dict(), scene.rules.to_dict(), label + " saves actual progress")

func _test_tea(scene: Node2D, translated: String) -> void:
	var rules: ShopRules = scene.rules
	var opening_cost := rules.shop.stages[0].cost
	rules.gold = 0.0
	scene.ui.open_station("lemonade")
	scene._refresh(0.0)
	var station: Control = scene.ui.page_node("station")
	suite.check(station.unlock_button.disabled, "empty or translated failure disables real unlock button")
	suite.check_eq(station.unlock_button.text, "金币不足 · %d 金币"%opening_cost, "real gold failure caption shows current price")
	suite.check(not scene._station_buttons.lemonade.can_unlock, "failure has no world-frame affordability marker")
	suite.check(not scene.guide._holds("affordable:lemonade"), "failure never satisfies guide affordability")
	_reject(scene, func() -> void: station.unlock_button.pressed.emit(), "opening funds")
	rules.gold = 100000.0
	scene._refresh(0.0)
	suite.check(not station.unlock_button.disabled and scene._station_buttons.lemonade.can_unlock, "nonempty success display enables button and frame")
	suite.check(scene.guide._holds("affordable:lemonade"), "nonempty success display permits guide")
	_success(scene, func() -> void: station.unlock_button.pressed.emit(), "unlocked", "opening")
	suite.check_eq(rules.gold, 100000.0-opening_cost, "opening debits exactly one displayed cost")
	_reject(scene, func() -> void: scene.station_action("unlock", "lemonade"), "repeat opening")
	scene.ui.open_station(rules.supply_id)
	var supply := TEA.station(rules.supply_id)
	for material in supply.materials:
		if not rules.boxes.has(material.id): continue
		var row: Dictionary = scene.view.material_row(supply, material)
		suite.check_eq(row.state, "box_closed", "actual material state ignores localized prefix")
		suite.check_eq(row.error, translated, "actual material uses injected text")
		suite.check(station.material_buttons[material.id].disabled, "locked material button stays disabled")
	_success(scene, func() -> void: scene.station_action("unlock", "boil"), "unlocked", "boil")
	suite.check(scene.guide._holds("box_affordable"), "box guide follows canonical check")
	var box := rules.pending_box()
	_success(scene, func() -> void: scene.station_action("box", rules.supply_id, box), "box", "box")
	_success(scene, func() -> void: scene.station_action("upgrade", "lemonade"), "upgraded", "station upgrade")
	_success(scene, func() -> void: scene.station_action("material", rules.supply_id, box), "upgraded", "material upgrade")
	_success(scene, func() -> void: scene.station_action("seat", rules.counter_id), "seat", "seat")
	_success(scene, func() -> void: scene.station_action("flyers", rules.counter_id), "flyer", "flyers")
	_reject(scene, func() -> void: scene.station_action("flyers", rules.counter_id), "active flyers")
	_success(scene, func() -> void: scene.station_action("flyer_upgrade", rules.counter_id), "upgraded", "flyer upgrade")
	scene.ui.open_page("staff")
	_success(scene, scene.hire_worker, "hired", "hire")
	_success(scene, scene.toggle_deployment, "recalled", "recall")
	_success(scene, scene.toggle_deployment, "deployed", "deployment")
	_success(scene, func() -> void: scene.buy_staff_upgrade("front"), "upgraded", "staff upgrade")
	for stage in TEA.stages:
		if not rules.station_unlocked(stage.stations[0]): scene.station_action("unlock", stage.stations[0])
	var connection: SpecConnection = TEA.connections[0]
	_success(scene, func() -> void: scene.buy_connection(connection.id), "connection", "connection")
	_reject(scene, func() -> void: scene.buy_connection(connection.id), "repeat connection")
	var event := SpecEvent.new()
	event.id = "localized"
	event.choices.assign([{"label": "yes", "cost": 9}])
	event.effects.assign([SpecEffect.make("grant_gold", "add", 20.0)])
	rules.pending_events.append(event)
	scene._refresh(0.0)
	rules.gold = 0.0
	_reject(scene, func() -> void: scene.answer_event(0, event.id), "event funds")
	suite.check(scene.ui.popups.has_card("event:" + event.id), "failure keeps actual popup")
	rules.gold = 10000.0
	_success(scene, func() -> void: scene.ui.popups.button(0).pressed.emit(), "event_answered", "event answer")
	suite.check_eq(rules.gold, 10011.0, "event cost and effect happen once")
	suite.check(not scene.ui.popups.has_card("event:" + event.id) and rules.pending_events.is_empty(), "success consumes actual card")
	await _test_drag(scene)
	rules.gold = 0.0
	scene._refresh(0.0)
	var staff: Control = scene.ui.page_node("staff")
	suite.check(staff.hire_button.disabled, "empty failure cannot enable hire")
	for button in staff.upgrade_buttons.values(): suite.check(button.disabled, "empty failure cannot enable staff upgrade")
	_reject(scene, scene.hire_worker, "hire funds")
	_reject(scene, func() -> void: scene.buy_staff_upgrade("front"), "staff upgrade funds")

func _test_drag(scene: Node2D) -> void:
	scene.ui.open_page("shop")
	var drag: Node2D = scene._drag
	var id: int = scene.selected_worker
	drag._candidate(id, Vector2(300, 500), false)
	drag._start_drag()
	drag.target = {"kind": "post", "post": "missing", "point": Vector2.ZERO}
	suite.check_eq(drag._target_status().code, "station_required", "locked-post validity ignores empty failure display")
	if scene.rules.post_owner(scene.rules.counter_id, id) != -1:
		drag.target = {"kind": "post", "post": scene.rules.counter_id, "point": scene.rules.nav.post(scene.rules.counter_id)}
		var status: Dictionary = drag._target_status()
		suite.check_eq(status.code, "front_full", "occupied counter keeps stable front-capacity status")
		suite.check_eq(drag._status_text(status), scene.view.text("front_full", status.params, "前台最多 {count} 位，前台升级可以加前台位"), "rich front-capacity presentation is preserved")
	drag.target = {"kind": "invalid", "reason": "automatic_station"}
	suite.check_eq(drag._target_status().code, "ui_drop_rejected", "geometry has a stable UI status")
	suite.check_eq(drag._target_status().params.reason, "automatic_station", "geometry retains reason token")
	drag._update_ghost()
	_reject(scene, func() -> void: drag._release(Vector2(-100, -100)), "invalid drag release")
	var screen := Vector2.INF
	for x in range(120, 1100, 40):
		for y in range(160, 1200, 40):
			var candidate: Vector2 = scene.get_node("Canvas").get_global_transform_with_canvas() * Vector2(x, y)
			var target: Dictionary = drag._drop_target(candidate)
			if target.get("kind") != "mobile": continue
			if scene.rules.command_status("place_worker", {"id": id, "post": "", "point": target.point}).code != "ok": continue
			screen = candidate
			break
		if screen.is_finite(): break
	suite.check(screen.is_finite(), "real scene supplies a valid mobile drop")
	if not screen.is_finite(): return
	drag._candidate(id, screen, false)
	drag._start_drag()
	drag._motion(screen)
	suite.check_eq(drag._target_status().code, "ok", "validity ignores nonempty success message")
	drag._update_ghost()
	await process_frame
	_success(scene, func() -> void: drag._release(screen), "placed", "valid drag release")
