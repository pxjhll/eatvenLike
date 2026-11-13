extends RefCounted
## Historical read-only query boundary; never advances or mutates a business state.

static func dish_open(owner: RefCounted, dish_id: String, needs_kitchen_hand := true) -> bool:
	var dish: SpecDish = owner.shop.dish(dish_id)
	for s in dish.steps:
		var st: SpecStation = owner.shop.station(s.station)
		if st == null: continue
		if st.block == "pickup": continue
		if not owner.station_unlocked(s.station) and st.companion_of.is_empty(): return false
		if not st.companion_of.is_empty() and not owner.station_unlocked(st.companion_of): return false
		for item in s.consumes:
			if not owner._box_ready(item): return false
		if st.block == "supply":
			for item in s.produces:
				if not owner._box_ready(item): return false
	if not owner.flavor_open(dish): return false
	if owner.shop.recipe_stage_of(dish_id) > owner.stage_index: return false
	if owner.shop.fulfillment.handoff == "handoff" and needs_kitchen_hand and not dish.front and owner.kitchen_staff() <= 0: return false
	return true

static func serving(owner: RefCounted) -> bool:
	return owner.shop.fulfillment.handoff=="serve"

static func queued(owner: RefCounted) -> bool:
	return owner.shop.fulfillment.handoff in ["single","serve"]

const SHARED := -1
const SEAT := "seat:"

static func pickup_of(shop: SpecShop) -> String:
	for st in shop.stations:
		if st.block == "pickup": return st.id
	return ""

static func seat_point(shop: SpecShop, seat: int) -> String:
	for g in shop.seat_groups:
		if g.purpose == "dine": return "%s/%d" % [g.id, seat]
	return ""

static func self_pickup(shop: SpecShop) -> bool:
	return shop.fulfillment.dine_rule == "self_pickup"
