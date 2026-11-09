extends RefCounted
## Detached numeric snapshot. SpecShop is shared as an immutable definition.

const Numbers := preload("res://game/rules/rule_numbers.gd")
const Upgrades := preload("res://game/rules/upgrade_modifiers.gd")

var shop: SpecShop
var levels: Dictionary
var mods := RuleModifiers.new()
var tune: Dictionary


func _init(definition: SpecShop, source_levels: Dictionary, source_mods: RuleModifiers, source_tune: Dictionary, level_overrides: Dictionary = {}) -> void:
	shop = definition
	levels = source_levels.duplicate(true)
	mods.entries = source_mods.entries.duplicate(true)
	tune = source_tune.duplicate(true)
	for key in level_overrides:
		if Upgrades.track_of(shop, key) == null: continue
		levels[key] = int(level_overrides[key])
		Upgrades.refresh_key(shop, levels, mods, key)


func query_context(level_overrides: Dictionary = {}) -> RefCounted:
	return get_script().new(shop, levels, mods, tune, level_overrides)


func preview(key: String, evaluator: Callable) -> Variant:
	var overrides := {}
	if Upgrades.track_of(shop, key) != null: overrides[key] = int(levels[key]) + 1
	return evaluator.call(query_context(overrides))


func level(id: String) -> int:
	return int(levels.get(id, 1))


func tuned(key: String) -> float:
	return Numbers.tuned(tune, key)


func speed(id: String) -> float:
	return Numbers.speed(mods, id)


func duration_mult(id: String) -> float:
	return Numbers.duration_mult(mods, id)


func pot_batch(id: String) -> int:
	return Numbers.pot_batch(shop, mods, id)


func process_slots(id: String) -> int:
	return Numbers.process_slots(shop, mods, id)


func raw_price(dish_id: String) -> float:
	return Numbers.raw_price(shop, mods, tune, dish_id)


func dish_price(dish_id: String) -> float:
	return Numbers.dish_price(shop, mods, tune, dish_id)


func dish_quote(dish_id: String) -> Dictionary:
	return Numbers.dish_quote(shop, mods, tune, dish_id)


func order_price_single(c: Dictionary) -> int:
	return Numbers.order_price_single(shop, mods, tune, c)


func side_of(worker: Dictionary) -> String:
	return Numbers.side_of(shop, worker)


func stat(worker: Dictionary, name: String) -> float:
	return Numbers.stat(shop, mods, tune, worker, name)


func walk_speed(worker: Dictionary) -> float:
	return Numbers.walk_speed(shop, mods, tune, worker)


func skill(worker: Dictionary) -> float:
	return Numbers.skill(shop, mods, tune, worker)


func carry(worker: Dictionary) -> int:
	return Numbers.carry(shop, mods, tune, worker)


func effective_worker_stats(worker: Dictionary) -> Dictionary:
	return Numbers.effective_worker_stats(shop, mods, tune, worker)


func manual_operation_seconds(id: String, base_seconds: float, worker: Dictionary = {}, fixed := false) -> float:
	return Numbers.manual_operation_seconds(shop, mods, tune, id, base_seconds, worker, fixed)


func station_timing(id: String) -> Dictionary:
	return Numbers.station_timing(shop, mods, tune, id)


func pot_seconds(id: String) -> float:
	return Numbers.pot_seconds(shop, mods, tune, id)


func machine_seconds(id: String) -> float:
	return Numbers.machine_seconds(shop, mods, tune, id)


func flyer_customers() -> int:
	return Numbers.flyer_customers(mods)


func flyer_cooldown() -> float:
	return Numbers.flyer_cooldown(mods)
