extends RefCounted
const Production := preload("res://tests/fixtures/template_shop.gd")
const Actors := preload("res://tests/fixtures/movement_shop.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")

static func definition(delivery := "counter", admission := "automatic") -> Resource:
	var template := Production.linear()
	template.places["front"] = {"port":Vector2(180,480)}
	template.places["pass"] = {"port":Vector2(300,480), "capacity":8}
	template.places["table"] = {"port":Vector2(500,680)}
	var side: Dictionary = template.recipes.drink.duplicate(true)
	side.nodes[1].produces = {"side":1}
	side.nodes[1].seconds = 3.0
	side.output.item = "side"
	template.recipes["side"] = side
	template.set("service", {"menu":{"lemonade":"drink", "black_tea":"side"},
		"admission":admission, "admission_port":"front" if admission == "employee" else "", "admission_seconds":0.6,
		"delivery":delivery, "handoff_port":"pass" if delivery == "counter" else "",
		"pickup":"pass" if delivery == "self_pickup" else "", "customer_capacity":2,
		"seats":{} if delivery == "counter" else {"seat:dine/0":"table"}, "eat_seconds":2.0,
		"orders":{"pay_at":"on_deliver", "queue_release":"after_take"}})
	return template

static func owner() -> ShopRules:
	var shop := Actors.definition("handoff")
	shop.staff.starting.assign(["gray_cat", "gray_cat"])
	shop.staff.starting_posts.assign(["", ""])
	shop.layout.customer_points["seat:dine/0"] = Vector2(500,700)
	var rules := ShopRules.new(shop,42)
	for worker in rules.workers: worker.pos = Vector2(100,100)
	return rules

static func runtime(delivery := "counter", admission := "automatic") -> RefCounted:
	return Runtime.new(owner(), definition(delivery, admission))

static func request() -> Array:
	return [{"dish":"lemonade", "qty":1}, {"dish":"black_tea", "qty":1}]
