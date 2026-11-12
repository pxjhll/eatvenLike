extends "res://tests/test_case.gd"
const Inventory := preload("res://game/rules/template/inventory.gd")
const Machines := preload("res://game/rules/template/machines.gd")
const PATH := "res://game/rules/template/view_frame.gd"

func _view() -> Script:
	check(ResourceLoader.exists(PATH), "templates need one read-only presentation projection")
	return load(PATH) if ResourceLoader.exists(PATH) else null

func _stock() -> RefCounted:
	var stock := Inventory.new()
	stock.configure("source", 6)
	stock.configure("bench", 6)
	stock.configure("ready", 6)
	stock.seed("source", "raw", 3)
	return stock

func test_waiting_materials_and_products_are_ui_stock_without_loose_scene_icons() -> void:
	var view := _view()
	if view == null: return
	var stock := _stock()
	var machines := Machines.new(stock)
	stock.seed("bench", "sauce", 1, 12)
	stock.seed("ready", "meal", 2, 12)
	var frame: Dictionary = view.build(stock, machines)
	check_eq(frame.error, "", "valid public state")
	check_eq(frame.stock.source.items.raw.count, 3, "UI records source materials")
	check_eq(frame.stock.bench.items.sauce.count, 1, "UI records order-owned ingredients")
	check_eq(frame.stock.ready.items.meal.count, 2, "UI records completed dishes")
	check_eq(frame.draws, [], "stock ownership never implies a visible world item")

func test_shared_view_shows_hands_only_after_pickup_and_clears_them_on_drop() -> void:
	var view := _view()
	if view == null: return
	var stock := _stock()
	var machines := Machines.new(stock)
	var task: Dictionary = stock.reserve_transfer(1, "source", "bench", "raw", 3, 2)
	var frame: Dictionary = view.build(stock, machines)
	check_eq(frame.held, {}, "no hand icon during planning or walking to source")
	check_eq(frame.stock.source.items.raw.available, 1, "UI separates reserved source stock")
	stock.pickup(task.id)
	frame = view.build(stock, machines)
	check_eq(frame.held[1].items, [{"item":"raw", "count":2}], "completed pickup is the only hand display source")
	check_eq(frame.stock.source.items.raw.count, 1, "source count agrees with held count")
	stock.drop(task.id)
	frame = view.build(stock, machines)
	check_eq(frame.held, {}, "completed drop removes hand display")
	check_eq(frame.stock.bench.items.raw.count, 2, "UI now records the delivered inputs")
	check_eq(frame.draws, [], "delivered inputs stay UI stock")

func test_explicit_showcase_ports_reuse_the_same_public_display_capability() -> void:
	var view := _view()
	if view == null: return
	for place in ["shelf", "dining_table"]:
		var stock := Inventory.new()
		stock.configure(place, 5)
		stock.seed(place, "product", 3)
		var machines := Machines.new(stock)
		var binding := {"capability":"stock_showcase", "place":place, "points":[Vector2(10,20),Vector2(30,20)], "host":"Table"}
		var frame: Dictionary = view.build(stock, machines, [binding])
		check_eq(frame.draws, [{"item":"product", "pos":Vector2(10,20), "host":"Table"}, {"item":"product", "pos":Vector2(30,20), "host":"Table"}], "only authored display ports show stock")
		check_eq(frame.stock[place].items.product.count, 3, "display limit does not remove undisplayed stock")

func test_machine_ui_and_scene_projection_cannot_mutate_authoritative_state() -> void:
	var view := _view()
	if view == null: return
	var stock := _stock()
	var machines := Machines.new(stock)
	machines.configure("device", "source", "ready")
	machines.start("device", {"raw":1}, {"meal":1}, 2.0)
	machines.advance(1.0)
	var before: Dictionary = stock.snapshot()
	var machine_before: Dictionary = machines.snapshot()
	var frame: Dictionary = view.build(stock, machines)
	check(is_equal_approx(float(frame.machines.device.progress), 0.5), "UI consumes authoritative operation progress")
	frame.stock.source.items.raw.count = 100
	frame.machines.device.progress = 1.0
	check_eq(stock.snapshot(), before, "UI stock edits cannot write back")
	check_eq(machines.snapshot(), machine_before, "UI progress edits cannot finish work")

func test_unknown_display_or_missing_port_cannot_fall_back_to_workstation_coordinates() -> void:
	var view := _view()
	if view == null: return
	var stock := _stock()
	var machines := Machines.new(stock)
	for binding in [{"capability":"custom_shop_draw", "place":"bench", "points":[Vector2.ZERO]}, {"capability":"stock_showcase", "place":"bench", "points":[]}]:
		var frame: Dictionary = view.build(stock, machines, [binding])
		check(not String(frame.error).is_empty(), "unsupported capability or absent display port must be reported")
		check_eq(frame.draws, [], "invalid binding cannot scatter inventory in the scene")
