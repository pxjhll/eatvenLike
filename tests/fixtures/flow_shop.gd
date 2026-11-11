extends RefCounted
## Copies of existing content with controlled geometry. No production assets.
const MovementShop := preload("res://tests/fixtures/movement_shop.gd")

static func definition() -> SpecShop:
	var shop := MovementShop.definition()
	if shop.fulfillment.get("flow_version")==null: return null
	shop.fulfillment.set("flow_version",1)
	shop.fulfillment.set("delivery_batch","order")
	shop.fulfillment.dine_rule = "seat_wait"
	shop.fulfillment.addon_dish = "soup"
	shop.fulfillment.addon_chance = 1.0
	shop.dispatch.action_version = 1
	var side: SpecStation = shop.station("window").duplicate(true)
	side.id = "side_window"
	side.companion_of = shop.goals.opening_station
	shop.stations.append(side)
	shop.layout.points[side.id] = Vector2(900,500)
	shop.layout.posts[side.id] = shop.layout.points[side.id]
	var points: Dictionary[String,String] = {"soup":"side_window"}
	shop.fulfillment.set("delivery_points",points)
	for kind in shop.staff.kinds: kind.stats.carry = 2.0
	for stage in shop.stages:
		stage.order_weights.clear()
		stage.order_weights["tomato_rice"] = 1.0
	return shop

static func opened(shop: SpecShop = null) -> ShopRules:
	if shop==null: shop = definition()
	if shop==null: return null
	var rules := ShopRules.new(shop,42)
	rules.gold = 1000000.0
	for guard in shop.stages.size()+1:
		var next := rules.next_unlock()
		if next.is_empty(): break
		rules.unlock(next)
	return rules

static func parallel() -> SpecShop:
	var shop := definition()
	if shop==null: return null
	shop.fulfillment.set("delivery_batch","item")
	shop.fulfillment.delivery_points.clear()
	shop.fulfillment.addon_chance = 0.0
	var branch := SpecStation.new()
	branch.id = "branch"
	branch.display_name = "Branch"
	branch.block = "hand"
	branch.zone = "kitchen"
	branch.starts_unlocked = true
	branch.params = {"users":1,"seconds":2.0}
	shop.stations.append(branch)
	shop.layout.points[branch.id] = Vector2(950,200)
	shop.layout.posts[branch.id] = shop.layout.points[branch.id]
	var dish := shop.dish("tomato_rice")
	var a: SpecStep = dish.steps[0]
	var work: SpecStep = dish.steps[2]
	var join: SpecStep = dish.steps[3]
	var b: SpecStep = a.duplicate(true)
	b.produces.clear()
	b.produces["egg_rice_raw"] = 1
	var finish := SpecStep.new()
	finish.station = branch.id
	finish.action = "mix"
	finish.seconds = 12.0
	finish.label = "制作"
	finish.consumes["egg_rice_raw"] = 1
	finish.produces["rice"] = 1
	dish.steps.assign([join,work,a,finish,b])
	shop.staff.starting.assign(["gray_cat","gray_cat","cat"])
	shop.staff.starting_posts.assign(["","","counter"])
	for stage in shop.stages: stage.staff_slots["kitchen"] = maxi(stage.staff_slots.get("kitchen",0),2)
	return shop
