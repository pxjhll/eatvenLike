extends RefCounted
## Explicit dependencies and destinations; only App opts into production services.

const ProgressService := preload("res://game/app/progress_service.gd")
const SpecValidator := preload("res://game/rules/shop_spec_validator.gd")
const TUNING_PATH := "user://tuning.cfg"
const RECORDING_PATH := "user://playlog.txt"

signal restarted

var profile: RefCounted
var store: ShopSave
var rules: ShopRules
var guide_enabled := false
var persist_tuning := false
var recording_enabled := false
var tuning_path := ""
var recording_path := ""
var speed := 1.0
var guides_seen: Array = []
var last_error := ""
var transition_committed := false
var started := false
var _progress := ProgressService.new()


func _init(profile_: RefCounted, store_: ShopSave, rules_: ShopRules = null) -> void:
	profile = profile_
	store = store_
	rules = rules_


static func shop_for(profile_: RefCounted, target_id: String = "") -> SpecShop:
	if profile_ == null or profile_.campaign == null: return null
	for city in profile_.campaign.cities:
		if city == null: return null
		for entry in city.shops:
			if entry == null: return null
			if entry.id == (profile_.shop if target_id.is_empty() else target_id) and not entry.shop_path.is_empty() and ResourceLoader.exists(entry.shop_path):
				return load(entry.shop_path) as SpecShop
	return null


func start() -> Error:
	if transition_committed: return _fail(ERR_UNAVAILABLE, "Session has already departed.")
	if started: return OK
	var error := _configuration_error()
	if error != OK: return error
	if profile.load_error != OK: return _fail(profile.load_error, profile.last_error)
	var errors := SpecValidator.validate(store.shop, profile.campaign)
	if rules != null and rules.shop != store.shop:
		errors.append_array(SpecValidator.validate(rules.shop, profile.campaign))
	if not errors.is_empty(): return _fail(ERR_INVALID_DATA, SpecValidator.summary(errors))
	if rules == null:
		if profile.fresh_shop and profile.shop == store.shop.id:
			var result: Dictionary = _progress.initialize_fresh(profile, store)
			if result.error != OK: return _fail(result.error, _progress.last_error)
			rules = result.rules
			speed = 1.0
			guides_seen = []
		else:
			var candidate := store.load_game()
			if store.load_error != OK: return _fail(store.load_error, store.last_error)
			rules = candidate
			speed = store.loaded_speed
			guides_seen = store.loaded_guides.duplicate()
	started = true
	# A corrupt shop may safely start fresh while retaining its existing warning.
	last_error = store.last_error
	return OK


func restart() -> Error:
	var error := _active_error()
	if error != OK: return error
	rules.reset()
	rules.paused = false
	last_error = ""
	restarted.emit()
	return OK


func save(guides: Array = []) -> Error:
	var error := _active_error()
	if error != OK: return error
	var seen := guides_seen if guides.is_empty() else guides
	error = store.save_game(rules, speed, seen)
	if error != OK: return _fail(error, store.last_error)
	guides_seen = seen.duplicate()
	last_error = ""
	return OK


func finish(record: Dictionary) -> Error:
	var error := _active_error()
	if error != OK: return error
	error = _progress.finish_shop(profile, store, record)
	if error != OK: return _fail(error, _progress.last_error)
	transition_committed = true
	last_error = ""
	return OK


func jump(target: String, guides: Array = []) -> Error:
	var error := _active_error()
	if error != OK: return error
	var seen := guides_seen if guides.is_empty() else guides
	error = _progress.jump_shop(profile, store, rules, target, speed, seen)
	if error != OK: return _fail(error, _progress.last_error)
	guides_seen = seen.duplicate()
	transition_committed = true
	last_error = ""
	return OK


func _configuration_error() -> Error:
	if profile == null or store == null or store.shop == null or store.path.strip_edges().is_empty():
		return _fail(ERR_INVALID_PARAMETER, "Session requires explicit Profile and ShopSave dependencies.")
	if rules != null and (rules.shop == null or rules.shop.id != store.shop.id):
		return _fail(ERR_INVALID_PARAMETER, "Session rules and store must refer to the same shop.")
	if profile.shop != store.shop.id:
		return _fail(ERR_INVALID_PARAMETER, "Session profile and store must refer to the current shop.")
	if persist_tuning and tuning_path.strip_edges().is_empty():
		return _fail(ERR_INVALID_PARAMETER, "Tuning persistence requires an explicit destination.")
	if recording_enabled and recording_path.strip_edges().is_empty():
		return _fail(ERR_INVALID_PARAMETER, "Recording requires an explicit destination.")
	return OK


func _active_error() -> Error:
	if not started or transition_committed or rules == null:
		return _fail(ERR_UNAVAILABLE, "Session is not active.")
	return _configuration_error()


func _fail(error: Error, message: String) -> Error:
	last_error = message if not message.is_empty() else "Session operation failed."
	return error
