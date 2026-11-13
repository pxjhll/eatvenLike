extends "res://tests/test_case.gd"
const Schema := preload("res://game/rules/shop_spec_validator.gd")
const Authoring := preload("res://game/rules/template/authoring.gd")
func test_authoring_rejects_shop_local_employee_copies_even_with_the_same_id() -> void:
	var authoring: RefCounted = Authoring.new()
	check(authoring.has_method("validate_global_staff"),"shared authoring gate validates canonical employee resources")
	if not authoring.has_method("validate_global_staff"): return
	var original: SpecShop = load("res://content/examples/onboarding/table.tres")
	check_eq(authoring.call("validate_global_staff",original),[],"canonical employees accepted")
	var shop: SpecShop = original.copy_for_editing()
	shop.staff.kinds[0].stats.walk += 10.0
	var errors: Array = authoring.call("validate_global_staff",shop)
	check(errors.any(func(row: Dictionary) -> bool: return row.path=="staff.kinds."+shop.staff.kinds[0].id),"same id cannot hide per-shop employee stats")
	check_eq(authoring.call("validate_global_staff",original),[],"rejected copy never edits the global resource")

func test_formal_authoring_is_driven_by_declared_capabilities_instead_of_legacy_mode() -> void:
	var shop: SpecShop = load("res://content/shops/tea/shop.tres").copy_for_editing()
	shop.fulfillment.handoff = "single"
	for dish in shop.dishes: dish.steps.clear()
	check_eq(Schema.validate(shop),[],"explicit public recipes require no duplicated legacy recipe/mode engine")
	var owner := ShopRules.new(shop,42)
	owner.gold = 1000000.0
	check_eq(owner.unlock(shop.sold_at(0)),"","normal outer command")
	owner.run(45.0)
	check(owner.sold>0 and owner.runtime_error.is_empty(),"same declared service actually produces and sells")
	check_eq(owner.load_dict(owner.to_dict()),"","same public save protocol with metadata-only legacy mode")

func test_public_metadata_references_and_stage_coverage_are_authoring_errors() -> void:
	var shop: SpecShop = load("res://content/shops/tea/shop.tres").copy_for_editing()
	shop.runtime_template.service.menu["not_a_dish"] = "black_tea"
	check(Schema.validate(shop).any(func(row: Dictionary) -> bool: return row.path=="runtime_template.service.menu.not_a_dish"),"public menu requires an actual price/art catalog dish")
	shop = load("res://content/shops/tea/shop.tres").copy_for_editing()
	shop.runtime_template.service.selection.stages.pop_back()
	check(Schema.validate(shop).any(func(row: Dictionary) -> bool: return row.path=="runtime_template.service.selection.stages"),"every purchasable stage requires an explicit menu stage")

func test_public_template_rejects_scripts_that_can_override_the_declarative_schema() -> void:
	var shop: SpecShop = load("res://content/shops/tea/shop.tres").copy_for_editing()
	var definition := PrivateTemplate.new()
	for key in ["places","machines","restocks","recipes","service","dispatch","presentation","transports"]: definition.set(key,shop.runtime_template.get(key))
	shop.runtime_template = definition
	check(Schema.validate(shop).any(func(row: Dictionary) -> bool: return row.path=="runtime_template.script"),"shop data cannot supply private capability implementation")
class PrivateTemplate extends SpecShopTemplate:
	func private_executor() -> void: pass
func test_formal_save_and_session_reject_missing_template_without_touching_old_bytes() -> void:
	var shop: SpecShop = load("res://content/shops/tea/shop.tres").copy_for_editing()
	shop.runtime_template = null
	var prefix := "user://u07-missing-template-"+str(Time.get_ticks_usec())
	var file := FileAccess.open(prefix+"-shop.json",FileAccess.WRITE); file.store_string("protected old bytes"); file.close()
	var store := ShopSave.new(shop,prefix+"-shop.json")
	var owner := ShopRules.new(shop,42)
	check_eq(store.save_game(owner),ERR_INVALID_DATA,"production storage cannot write a historical engine state")
	check(FileAccess.get_file_as_string(store.path)=="protected old bytes","configuration failure cannot quarantine or replace existing player state")
	var session: RefCounted = load("res://tests/shop_test_session.gd").make(shop,prefix,owner,store)
	check_eq(session.start(),ERR_INVALID_DATA,"formal session requires an explicit runtime before save access")
	check(FileAccess.get_file_as_string(store.path)=="protected old bytes","failed startup is read-only")
	for path in [store.path,session.profile.path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
