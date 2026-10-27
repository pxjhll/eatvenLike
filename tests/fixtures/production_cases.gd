extends RefCounted
## Test-only definitions. Arbitrary IDs deliberately exercise data-driven dispatch.
## Devices are laid out directly (no router) so production tests do not depend on grid geometry.


static func config(defs: Array) -> ShopConfig:
	var cfg := ShopConfig.new()
	cfg.id = "production_validation"
	cfg.kitchen_devices.assign(defs)
	cfg.supply_slot_limit = 99
	cfg.grid = ShopGridDef.new()
	cfg.grid.kitchen_rect = Rect2i(0, 0, 20, 20)
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


static func device(id: String, mode: int, inputs: Dictionary, outputs: Dictionary, seconds: float = 2.0) -> StationDef:
	var def := StationDef.new()
	def.id = id
	def.mode = mode
	def.zone = "kitchen"
	def.cycle_seconds = seconds
	def.manual_seconds = 1.0
	def.output_capacity = 8
	if mode == StationDef.Mode.SUPPLY:
		def.supply_items.assign(outputs.keys())
		def.supply_interval = seconds
		return def
	def.recipe = RecipeDef.new()
	def.recipe.id = id + "_recipe"
	def.recipe.inputs.assign(inputs)
	def.recipe.outputs.assign(outputs)
	for item in inputs:
		def.input_capacity[item] = 8
	return def


## 直接摆好设备和带子。devices：{实例 id: 定义 id}；belts：[[from, to, item, 格数]]
static func lay(sim: GameSim, devices: Dictionary, belts: Array) -> void:
	var x := 0
	for id in devices:
		sim.layout.devices.append({"id": id, "def": devices[id], "cell": Vector2i(x, 0)})
		x += 3
	for b in belts:
		var path: Array[Vector2i] = []
		for i in int(b[3]):
			path.append(Vector2i(i, 10))
		sim.layout.belts.append({"id": "%s>%s:%s" % [b[0], b[1], b[2]], "from": b[0], "to": b[1], "item": b[2], "path": path})
	sim.production.apply_layout(sim.layout.devices, sim.layout.belts)


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
