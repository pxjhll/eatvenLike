extends "res://game/tea_playtest/tea_shop_sim.gd"
## Bench-only variant: machine levels add price (percent of base) and optional brew batch milestones.
static var V: Dictionary = {}

func _dish_machines(dish: String) -> Array:
	if dish == "lemonade": return [["lemonade", ""]]
	if dish == "black_tea": return [["boil", ""], ["supply", "tea_leaf"]]
	return [["boil", ""], ["mix", ""], ["supply", "tea_leaf"], ["supply", "milk"]]

func _dish_price(dish: String) -> int:
	if not V.get("price", false): return super._dish_price(dish)
	var base := 0
	for definition in CONFIG.dishes:
		if definition.id == dish: base = definition.price
	var bonus := 0.0
	for pair in _dish_machines(dish):
		var level: int = station_levels[pair[0]] if pair[1] == "" else material_levels[pair[0]][pair[1]]
		bonus += V.pct.get(pair[1] if pair[1] != "" else pair[0], 0.0) * (level - 1)
	var flavor := 1.0
	for material in _definition("topping").materials:
		if material.item_id == dish: flavor = _material_bonus("topping", material.id)
	return roundi(base * (1.0 + bonus) * flavor)

func _brew_batch() -> int:
	var steps: Array = V.get("batch", [])
	var batch := 3
	for level in steps:
		if station_levels.boil >= level: batch += 1
	return batch

func _initialize_shop() -> void:
	super._initialize_shop()
	if V.get("batch", []).size() > 0: stations.boil.capacity = 10
