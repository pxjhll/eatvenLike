extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")

func _template() -> Resource:
	var template := Fixture.definition("self_pickup")
	check(template.get("presentation")!=null,"templates need explicit presentation configuration")
	if template.get("presentation")==null: return null
	template.presentation = {"stock":[{"places":["a_out","b_out"],"ports":["Shelf/0","Shelf/1"],"host":"Shelf","height":52.0}],
		"counters":{"shelf":["a_out","b_out"]},
		"dining":{"seat:dine/0":{"port":"Table/0","offsets":[Vector2(-20,0),Vector2(20,0)],"host":"Table","height":36.0}},
		"poses":{"seat:dine/0":{"port":"Chair/0","offset":Vector2(0,-12),"facing":2}}}
	return template

func _geometry() -> Dictionary:
	return {"ports":{"Shelf/0":Vector2(300,200),"Shelf/1":Vector2(350,200),"Table/0":Vector2(500,650),"Chair/0":Vector2(500,700)},"hosts":["Shelf","Table"]}

func test_authored_multi_container_showcase_and_counter_share_real_stock() -> void:
	var template := _template()
	if template==null: return
	var runtime := Runtime.new(Fixture.owner(),template)
	check_eq(runtime.last_error,"","valid authored presentation")
	runtime.runner.inventory.seed("a_out","drink",1)
	runtime.runner.inventory.seed("b_out","side",2)
	var view := ShopView.new(runtime.runner.owner)
	check_eq(view.call("bind_runtime",runtime,[],_geometry()),"","resolve actual scene ports")
	var frame := view.render_snapshot()
	check_eq(frame.draws.size(),2,"one shared port pool spans different stock containers")
	check_eq(frame.draws[0].pos,Vector2(300,200),"authored first point")
	check_eq(frame.draws[1].pos,Vector2(350,200),"second container cannot reuse first point")
	check_eq(frame.counters.shelf.count,3,"UI includes stock exceeding the visible port count")
	check_eq(frame.draws[0].height,52.0,"explicit display height")

func test_missing_geometry_host_or_port_rejects_binding_without_replacing_current_view() -> void:
	var template := _template()
	if template==null: return
	var runtime := Runtime.new(Fixture.owner(),template)
	var view := ShopView.new(runtime.runner.owner)
	check_eq(view.call("bind_runtime",runtime,[],_geometry()),"","valid binding first")
	var before := view.render_snapshot()
	for kind in ["missing","host","port"]:
		var geometry := _geometry()
		if kind=="missing": geometry = {}
		elif kind=="host": geometry.hosts = []
		else: geometry.ports.erase("Shelf/1")
		check(not String(view.call("bind_runtime",runtime,[],geometry)).is_empty(),"missing scene declaration rejected: "+kind)
		check_eq(view.render_snapshot(),before,"failed binding preserves current geometry")

func test_dining_displays_actual_delivered_food_only_when_customer_really_sits() -> void:
	var template := _template()
	if template==null: return
	var runtime := Runtime.new(Fixture.owner(),template)
	var view := ShopView.new(runtime.runner.owner)
	view.call("bind_runtime",runtime,[],_geometry())
	runtime.arrive(Fixture.request())
	var saw_dining := false
	for tick in 1800:
		runtime.step(0.1)
		var frame := view.render_snapshot()
		var meals: Array = frame.draws.filter(func(row: Dictionary) -> bool: return row.get("capability")=="dining_item")
		if not meals.is_empty():
			saw_dining = true
			check_eq(meals.size(),2,"main and addon draw the two real items")
			check(runtime.service.customers.ready(1,"seat:dine/0"),"never draw a meal while still carrying it to the seat")
			check_eq(frame.movement.customers["guest:1"].render_pos,Vector2(500,688),"seated pose uses explicit geometry")
		if runtime.service.orders.guest(1).state=="gone": break
	check(saw_dining,"real pickup, seating and eating reached")
	check(view.render_snapshot().draws.filter(func(row: Dictionary) -> bool: return row.get("capability")=="dining_item").is_empty(),"consumed meal vanishes without a second food ledger")

func test_unknown_presentation_parameters_containers_seats_and_heights_fail_compilation() -> void:
	for raw in [{"custom":{}},{"stock":[{"places":["missing"],"ports":["x"],"host":"","height":52.0}]},
		{"dining":{"unknown":{"port":"x","offsets":[Vector2.ZERO],"host":"","height":36.0}}},
		{"counters":{"x":["missing"]}}, {"poses":{"seat:dine/0":{"port":"x","offset":Vector2.ZERO,"facing":9}}},
		{"stock":[{"places":["a_out"],"ports":["x"],"host":"","height":-1.0}]}]:
		var template := _template()
		if template==null: return
		template.presentation = raw
		check(not Compiler.compile(template).errors.is_empty(),"invalid presentation must fail explicitly")

func test_empty_presentation_preserves_existing_compiled_template_identity() -> void:
	var template := Fixture.definition()
	var before: Dictionary = Compiler.compile(template).definition
	check(template.get("presentation")!=null,"optional declaration exists")
	if template.get("presentation")==null: return
	template.presentation = {}
	check_eq(Compiler.compile(template).definition,before,"unused presentation has no signature side effects")
