extends RefCounted
## Test-only definitions. Arbitrary IDs deliberately exercise data-driven dispatch.


static func config(slots: Array, connections: Array = []) -> ShopConfig:
	var cfg := ShopConfig.new()
	cfg.id = "production_validation"
	cfg.slots.assign(slots)
	cfg.connections.assign(connections)
	cfg.zones.assign(["kitchen", "front"])
	cfg.staff_start_zones["operator"] = "kitchen"
	cfg.walk_seconds["kitchen>front"] = 2.0
	cfg.belt_speed = 4.0
	cfg.shelf_capacity = 4
	cfg.queue_capacity = 4
	cfg.customer_patience = 20.0
	cfg.starting_gold = 1000
	cfg.random_seed = 20261024
	cfg.progression = ShopProgressionDef.new()
	var stage := ShopStageDef.new()
	stage.dish_id = "validation_dish"
	stage.customer_interval = 1000000.0
	stage.order_weights["validation_dish"] = 1.0
	cfg.progression.stages.append(stage)
	return cfg


static func slot(id: String, mode: int, inputs: Dictionary, outputs: Dictionary, seconds: float = 2.0) -> SlotDef:
	var def := StationDef.new()
	def.id = id + "_definition"
	def.mode = mode
	def.zone = "kitchen"
	def.cycle_seconds = seconds
	def.manual_seconds = 1.0
	def.output_capacity = 8
	def.recipe = RecipeDef.new()
	def.recipe.id = id + "_recipe"
	def.recipe.inputs.assign(inputs)
	def.recipe.outputs.assign(outputs)
	for item in inputs:
		def.input_capacity[item] = 8
	var result := SlotDef.new()
	result.id = id
	result.station = def
	return result


static func connection(id: String, from_slot: String, to_slot: String) -> ConnectionDef:
	var conn := ConnectionDef.new()
	conn.id = id
	conn.from_slot = from_slot
	conn.to_slot = to_slot
	conn.length_cells = 2.0
	return conn


static func worker(efficiency: float = 1.0) -> StaffDef:
	var def := StaffDef.new()
	def.id = "operator"
	def.zone_efficiency["kitchen"] = efficiency
	return def


static func state(sim: GameSim, slot_id: String) -> StationState:
	for st in sim.production.stations:
		if st.slot_id == slot_id:
			return st
	return null


static func produced(sim: GameSim, item: String) -> int:
	return int(sim.diagnostics.item_flow.get(item, {}).get("produced", 0))
