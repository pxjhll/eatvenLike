extends RefCounted
## Controlled geometry on the real three business modes; never edits shared resources.
const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/tea.tres")
const SINGLE: SpecShop = preload("res://tests/fixtures/legacy_shops/pancake.tres")
## Keep controlled protocol fixtures independent of production shop migrations.
const SERVE: SpecShop = preload("res://tests/fixtures/stirfry_modularity/legacy_shop.tres")

static func definition(mode := "serve", units := 1.0) -> SpecShop:
	var source: SpecShop = {"serve":SERVE,"single":SINGLE,"handoff":TEA}[mode]
	var shop: SpecShop = source.copy_for_editing()
	var data := SpecLayout.new()
	data.set("motion_version",1)
	data.set("motion_units",units)
	data.nav = "grid"
	data.cell = 40.0*units
	data.grid_size = Vector2i(32,32)
	data.areas = [Rect2i(0,0,32,32)]
	data.set("actor_areas",{"staff":[Rect2i(0,0,32,32)],"customer":[Rect2i(0,0,32,32)]})
	data.customer_queue.assign([Vector2(100,500)*units,Vector2(100,560)*units])
	data.spawn_point = source.layout.spawn_point
	data.aliases = source.layout.aliases.duplicate()
	var ports: Dictionary[String,Vector2] = {"entrance":Vector2(100,1100)*units,"exit":Vector2(60,1100)*units,"pickup":Vector2(300,500)*units}
	for index in shop.stations.size():
		var id := shop.stations[index].id
		data.points[id] = Vector2(200+index*70,200)*units
		data.posts[id] = data.points[id]
	if not data.points.has(shop.staff.home_anchor): data.points[shop.staff.home_anchor] = Vector2(300,300)*units
	if not data.points.has(data.spawn_point): data.points[data.spawn_point] = Vector2(300,300)*units
	for point in source.layout.points:
		if not data.points.has(point): data.points[point] = Vector2(400,300)*units
	for group in shop.seat_groups:
		var count := group.start+group.step*group.costs.size()
		if not group.steps.is_empty():
			count = group.start
			for extra in group.steps: count += extra
		for seat in count:
			var name := "%s/%d"%[group.id,seat]
			data.points[name] = Vector2(500+(seat%8)*60,700+(seat/8)*60)*units
			ports[("wait:" if group.purpose == "wait" else "seat:")+name] = data.points[name]
	data.set("customer_points",ports)
	shop.layout = data
	return shop

static func opened(mode := "serve", units := 1.0) -> ShopRules:
	var shop := definition(mode,units)
	var rules := ShopRules.new(shop,42)
	rules.gold = 100000.0
	rules.unlock(shop.goals.opening_station)
	return rules
