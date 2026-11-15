extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")

const Sections := preload("res://presentation/shop/hud/station_sections.gd")
const Result := preload("res://game/rules/rule_command_result.gd")
const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/current/tea/shop.tres")

class PoisonRules extends ShopRules:
	var legacy_calls := 0
	func unlock(_id: String) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func unlock_error(_id: String) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func unlock_box(_material: String) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func box_error(_material: String) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func upgrade(_key: String) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func upgrade_error(_key: String) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func buy_seat() -> String:
		legacy_calls += 1
		return "poison legacy text"
	func seat_error() -> String:
		legacy_calls += 1
		return "poison legacy text"
	func send_flyers() -> String:
		legacy_calls += 1
		return "poison legacy text"
	func flyer_error() -> String:
		legacy_calls += 1
		return "poison legacy text"
	func hire() -> String:
		legacy_calls += 1
		return "poison legacy text"
	func hire_error() -> String:
		legacy_calls += 1
		return "poison legacy text"
	func deploy_worker(_id: int, _post := "") -> String:
		legacy_calls += 1
		return "poison legacy text"
	func place_worker(_id: int, _post: String, _point := Vector2.INF) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func placement_error(_id: int, _post: String, _point := Vector2.INF) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func recall_worker(_id: int) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func role_room(_post: String, _exclude_id := -1) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func buy_connection(_id: String) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func connection_error(_id: String) -> String:
		legacy_calls += 1
		return "poison legacy text"
	func answer_event(_choice: int) -> String:
		legacy_calls += 1
		return "poison legacy text"

class UnlockPage extends Control:
	const Icons := preload("res://presentation/ui/reference_icons.gd")
	func hud() -> Control: return self

func test_unlock_section_uses_status_for_caption_and_disabled() -> void:
	var page := UnlockPage.new()
	var section := Sections.UnlockSection.new()
	page.add_child(section)
	section.page = page
	section.icon = TextureRect.new()
	section.summary = Label.new()
	section.members = HBoxContainer.new()
	section.unlock_button = Button.new()
	for node in [section.icon, section.summary, section.members, section.unlock_button]: section.add_child(node)
	section._members = "[]"
	var info := {"status": Result.failure(Result.INSUFFICIENT_GOLD), "error": "localized unrelated", "cost": 123,
		"members": [], "note": "", "description": "", "quote": {}}
	var card := {"unlock": info, "stage": 0, "icon": "shop"}
	section.refresh(card)
	check_eq(section.unlock_button.text, "金币不足 · 123 金币", "gold caption comes from stable status")
	info.error = ""
	section.refresh(card)
	check(section.unlock_button.disabled, "empty localized failure still disables unlock")
	info.status = Result.success()
	info.error = "success translation"
	section.refresh(card)
	check(not section.unlock_button.disabled, "nonempty success text still enables unlock")
	page.free()

func test_read_model_material_states_ignore_localization_and_adapters() -> void:
	var rules := PoisonRules.new(TEA)
	for translated in ["translated dependency", ""]:
		var view := ShopView.new(rules, func(_status: Dictionary, _shop: SpecShop) -> String: return translated)
		var supply := TEA.station(rules.supply_id)
		for material in supply.materials:
			if not rules.boxes.has(material.id): continue
			var row := view.material_row(supply, material)
			check_eq(row.state, "box_closed", "station-required box is closed independent of translated prefix")
			check_eq(row.status.code, Result.STATION_REQUIRED, "box exposes station dependency")
			check_eq(row.error, translated, "box error is display-only")
		for station in TEA.stations: view.station(station.id)
		view.hire()
		view.staff_track("front")
		view.can_buy(rules.counter_id)
	check_eq(rules.legacy_calls, 0, "read models never call String adapters")

func test_formatter_receives_detached_status() -> void:
	var rules := LegacyRules.new(TEA)
	var status := rules.command_status("unlock", {"id": "lemonade"})
	var before := status.duplicate(true)
	var bytes := var_to_bytes(rules.to_dict())
	var view := ShopView.new(rules, func(value: Dictionary, _shop: SpecShop) -> String:
		value.code = "poison"
		value.params.id = "poison"
		return "translated")
	check_eq(view.command_message(status), "translated", "injected formatter is used")
	check_eq(status, before, "formatter cannot rewrite caller status")
	check_eq(var_to_bytes(rules.to_dict()), bytes, "formatting leaves live business unchanged")
