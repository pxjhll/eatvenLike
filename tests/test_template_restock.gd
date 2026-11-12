extends "res://tests/test_case.gd"
const Schema := preload("res://content/rules/spec_shop_template.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Actors := preload("res://tests/fixtures/movement_shop.gd")

func _definition() -> Resource:
	var template := Schema.new()
	# Use set() for the initial missing-capability test without a parse error.
	check(template.get("restocks") != null, "shared batch replenishment is a template capability")
	if template.get("restocks") == null: return null
	template.places = {"pantry":{"port":Vector2(100,100),"infinite":["raw"]},
		"pot_in":{"port":Vector2(300,100),"capacity":4}, "pot_out":{"port":Vector2(300,100),"capacity":4}}
	template.machines = {"pot":{"input":"pot_in","output":"pot_out","profile":{
		"load_seconds":0.2,"unload_seconds":0.2,"stir_points":[0.5],"stir_seconds":0.2}}}
	template.recipes = {"cup":{"nodes":[{"id":"stock","capability":"source","place":"pot_out","item":"tea","seconds":0.2}],"output":{"node":"stock","item":"tea","count":1}}}
	template.set("restocks", {"pot_stock":{"machine":"pot","consumes":{"raw":2},"produces":{"tea":2},"sources":{"raw":"pantry"},"seconds":1.0,"fetch_seconds":0.2,"stock_limit":4}})
	return template

func _runtime(template: Resource) -> RefCounted:
	var shop := Actors.definition("handoff")
	shop.staff.starting_posts.assign([""])
	var rules := ShopRules.new(shop,42)
	rules.workers[0].pos = Vector2(100,100)
	return Runtime.new(rules, template)

func test_shared_restock_uses_real_carry_loading_stirring_and_unloading_then_stops_at_limit() -> void:
	var template := _definition()
	if template == null: return
	var runtime := _runtime(template)
	check_eq(runtime.last_error, "", "valid shared restock definition")
	var request: Dictionary = runtime.request_production("cup")
	for tick in 500: runtime.step(0.1)
	check(runtime.ready(request.id), "source-only recipe waits for shared production")
	check_eq(runtime.runner.inventory.quantity("pot_out", "tea"), 4, "two batches fill the configured limit")
	check_eq(runtime.runner.inventory.quantity("pot_in", "raw"), 0, "no unnecessary third batch of raw ingredients")
	check_eq(runtime.runner.machines.snapshot().runs.size(), 2, "full stock stops further production")
	check_eq(runtime.runner.inventory.audit(), [], "real supply chain conserves stock")

func test_automatic_stock_source_needs_no_employee_or_fictional_material_trip() -> void:
	var template := _definition()
	if template == null: return
	template.machines.pot.profile = {}
	template.get("restocks").pot_stock.consumes = {}
	template.get("restocks").pot_stock.sources = {}
	var runtime := _runtime(template)
	runtime.runner.owner.workers[0].deployed = false
	for tick in 30: runtime.step(0.1)
	check_eq(runtime.runner.inventory.quantity("pot_out", "tea"), 4, "automatic batch source can replenish by itself")
	check_eq(runtime.runner.inventory.quantity("pantry", "raw"), 0, "no artificial raw pile created")
	check_eq(runtime.runner.tasks, {}, "no employee task invented for automatic supply")

func test_saved_restock_stage_resumes_and_never_starts_a_second_copy_of_the_batch() -> void:
	var template := _definition()
	if template == null: return
	var runtime := _runtime(template)
	for tick in 35: runtime.step(0.1)
	var saved: Dictionary = runtime.snapshot()
	var reopened := _runtime(template)
	check_eq(reopened.restore(saved), "", "shared replenishment links restore with machine claims")
	for tick in 300:
		runtime.step(0.1)
		reopened.step(0.1)
	check_eq(reopened.snapshot(), runtime.snapshot(), "restock clocks, actors, stock and batch count replay exactly")
	check_eq(reopened.runner.inventory.quantity("pot_out", "tea"), 4, "no duplicate batch after reopening")

func test_restock_rejects_unbound_material_and_unknown_capability_parameters() -> void:
	var template := _definition()
	if template == null: return
	template.get("restocks").pot_stock.sources = {}
	var runtime := _runtime(template)
	check(not runtime.last_error.is_empty(), "finite raw inputs require a declared source")
	template = _definition()
	template.get("restocks").pot_stock.custom_refill_script = "private"
	runtime = _runtime(template)
	check(not runtime.last_error.is_empty(), "restock behavior cannot be overridden by a shop")
	template = _definition()
	template.get("restocks").pot_stock.produces = {"tea":RefCounted.new()}
	runtime = _runtime(template)
	check(not runtime.last_error.is_empty(), "invalid quantity objects are content errors rather than runtime exceptions")

func test_same_container_restock_counts_the_space_freed_by_its_actual_inputs() -> void:
	var template := _definition()
	if template == null: return
	template.machines.pot.input = "pot_out"
	var runtime := _runtime(template)
	for tick in 500: runtime.step(0.1)
	check_eq(runtime.runner.inventory.quantity("pot_out", "tea"), 4, "shared input/output container can transform its full second batch")
	check_eq(runtime.runner.inventory.quantity("pot_out", "raw"), 0, "full input container does not deadlock a space-neutral recipe")
	check_eq(runtime.runner.inventory.audit(), [], "same-container transformation conserves quantities and capacity")

func test_cooking_modifier_changes_the_public_restock_clock() -> void:
	var template := _definition()
	if template == null: return
	var runtime := _runtime(template)
	runtime.runner.owner.apply_effect("event", "template_pot_speed", SpecEffect.make("speed", "mul", 2.0, "pot"))
	for tick in 200:
		runtime.step(0.1)
		if not runtime.runner.machines.snapshot().runs.is_empty(): break
	check_eq(runtime.runner.machines.snapshot().runs[0].duration, 0.5, "cooking speed modifiers affect the real automatic clock")
