extends "res://tests/test_case.gd"
const SPEC := "res://content/rules/spec_shop_template.gd"
const COMPILER := "res://game/rules/template/compiler.gd"

func _template() -> Resource:
	check(ResourceLoader.exists(SPEC) and ResourceLoader.exists(COMPILER), "public capability templates need a data compiler")
	if not ResourceLoader.exists(SPEC) or not ResourceLoader.exists(COMPILER): return null
	var template: Resource = load(SPEC).new()
	template.places = {
		"pantry":{"port":Vector2(100,100),"infinite":["raw_a","raw_b"]},
		"a_in":{"port":Vector2(200,100),"capacity":4},
		"a_out":{"port":Vector2(200,100),"capacity":4},
		"b_in":{"port":Vector2(300,100),"capacity":4},
		"b_out":{"port":Vector2(300,100),"capacity":4},
		"join_in":{"port":Vector2(400,100),"capacity":4},
		"join_out":{"port":Vector2(400,100),"capacity":4}}
	template.machines = {
		"a":{"input":"a_in","output":"a_out","profile":{"manual":true}},
		"b":{"input":"b_in","output":"b_out","profile":{"manual":true}},
		"join":{"input":"join_in","output":"join_out","profile":{"manual":true}}}
	template.recipes = {"meal":{"nodes":[
		{"id":"merge","capability":"process","machine":"join","consumes":{"a":1,"b":1},"produces":{"meal":1},"inputs":{"a":"a","b":"b"},"seconds":1.0},
		{"id":"a","capability":"process","machine":"a","consumes":{"raw_a":1},"produces":{"a":1},"inputs":{"raw_a":"raw_a"},"seconds":2.0},
		{"id":"raw_a","capability":"source","place":"pantry","item":"raw_a","seconds":0.6},
		{"id":"b","capability":"process","machine":"b","consumes":{"raw_b":1},"produces":{"b":1},"inputs":{"raw_b":"raw_b"},"seconds":2.0},
		{"id":"raw_b","capability":"source","place":"pantry","item":"raw_b","seconds":0.6}],
		"output":{"node":"merge","item":"meal","count":1}}}
	return template

func _compile(template: Resource) -> Dictionary:
	return load(COMPILER).compile(template)

func _has(result: Dictionary, code: String) -> bool:
	return result.errors.any(func(error: Dictionary) -> bool: return error.code == code)

func test_parallel_branches_and_join_compile_from_explicit_public_capabilities() -> void:
	var template := _template()
	if template == null: return
	var result := _compile(template)
	check_eq(result.errors, [], "valid parallel recipe")
	if not result.errors.is_empty(): return
	var recipe: Dictionary = result.definition.recipes.meal
	check_eq(recipe.nodes.merge.dependencies, ["a", "b"], "merge waits for both producers")
	check(recipe.order.find("a") < recipe.order.find("merge") and recipe.order.find("b") < recipe.order.find("merge"), "dependency order is independent of authoring order")
	check_eq(recipe.nodes.a.input_places.raw_a, "pantry", "source resolves to a declared container")
	check_eq(recipe.nodes.merge.input_places.a, "a_out", "work output resolves through the same binding rule")
	check_eq(result.definition.machines.join.profile.manual, true, "machine capability data is retained")

func test_missing_input_and_unknown_behavior_are_rejected_with_configuration_paths() -> void:
	var template := _template()
	if template == null: return
	template.recipes.meal.nodes[0].inputs.erase("b")
	var result := _compile(template)
	check(_has(result, "missing_input_binding"), "a consumed item needs an explicit producer")
	check(result.errors.any(func(error: Dictionary) -> bool: return String(error.path).contains("recipes.meal.nodes.merge.inputs.b")), "error points to the broken input")
	template = _template()
	template.recipes.meal.nodes[0].capability = "custom_shop_tick"
	check(_has(_compile(template), "unsupported_capability"), "a shop cannot attach a private behavior")

func test_cycle_and_insufficient_branch_output_are_rejected() -> void:
	var template := _template()
	if template == null: return
	template.recipes.meal.nodes[1].after = ["merge"]
	check(_has(_compile(template), "cycle"), "an explicit ordering dependency cannot make a cycle")
	template = _template()
	template.recipes.meal.nodes[0].consumes.a = 2
	check(_has(_compile(template), "insufficient_output"), "one produced item cannot satisfy a two-item merge")

func test_unknown_machine_parameter_and_missing_port_cannot_silently_fall_back() -> void:
	var template := _template()
	if template == null: return
	template.machines.join.profile.custom_callback = "shop_specific"
	check(_has(_compile(template), "invalid_machine_capability"), "device profiles use the public machine capability validator")
	template = _template()
	template.places.join_in.erase("port")
	check(_has(_compile(template), "missing_port"), "missing interaction position is a content error")

func test_compiled_definition_is_detached_and_signature_changes_with_behavior() -> void:
	var template := _template()
	if template == null: return
	var first := _compile(template)
	check_eq(first.errors, [], "valid source")
	var fingerprint: String = first.definition.signature
	first.definition.recipes.meal.nodes.a.seconds = 99.0
	check_eq(template.recipes.meal.nodes[1].seconds, 2.0, "editing a read model cannot mutate resource definitions")
	check_eq(_compile(template).definition.signature, fingerprint, "same content has stable signature")
	template.recipes.meal.nodes[1].seconds = 3.0
	check(_compile(template).definition.signature != fingerprint, "timing changes are part of the behavior signature")

func test_same_placeholders_can_compile_a_different_recipe_without_changing_code() -> void:
	var template := _template()
	if template == null: return
	template.recipes = {"drink":{"nodes":[
		{"id":"raw","capability":"source","place":"pantry","item":"raw_a","seconds":0.6},
		{"id":"drink","capability":"process","machine":"a","consumes":{"raw_a":1},"produces":{"drink":1},"inputs":{"raw_a":"raw"},"seconds":2.0}],
		"output":{"node":"drink","item":"drink","count":1}}}
	var result := _compile(template)
	check_eq(result.errors, [], "linear direct-sale recipe uses the same compiler as the two-line merge")
	if result.errors.is_empty(): check_eq(result.definition.recipes.drink.order, ["raw","drink"], "source and work order")
