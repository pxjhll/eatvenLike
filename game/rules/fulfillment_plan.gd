extends RefCounted
## Stateless definition planning. Returned containers belong to the caller.

static func derive(shop: SpecShop) -> Dictionary:
	var counter_id: String = ""
	var supply_id: String = ""
	var pickup_id: String = ""
	var pots: Array[String] = []
	var autos: Array[String] = []
	var seatables: Array[String] = []
	var dish_ids: Array[String] = []
	var front_dishes: Array[String] = []
	var kitchen_dishes: Array[String] = []
	var chains: Dictionary = {}
	var station_output: Dictionary = {}
	var station_input: Dictionary = {}
	for st in shop.stations:
		match st.block:
			"counter": counter_id = st.id
			"supply":
				if supply_id.is_empty(): supply_id = st.id
			"pickup":
				if st.params.has("process_seconds"): pickup_id = st.id
			"batch_pot": pots.append(st.id)
			"combine":
				if not bool(st.params.get("manual", false)): autos.append(st.id)
		if st.seatable: seatables.append(st.id)
	for dish in shop.dishes:
		dish_ids.append(dish.id)
		if dish.front: front_dishes.append(dish.id)
		else: kitchen_dishes.append(dish.id)
		var chain: Array[String] = []
		# 机器的投入 = 前面工序做出来、送到这台机器的那样东西（原料箱里直接取的辅料不算）
		var made: Array = []
		for s in dish.steps:
			var st := shop.station(s.station)
			var counted: bool = st != null and not st.block in ["supply", "pickup", "counter"] and st.zone != "front"
			if counted:
				if not s.station in chain: chain.append(s.station)
				for item in s.consumes:
					if item in made and not station_input.has(s.station): station_input[s.station] = item
			made.append_array(s.produces.keys())
			if not counted: continue
			for item in s.produces:
				station_output[s.station + "|" + dish.id] = item
		chains[dish.id] = chain

	return {
		"counter_id": counter_id,
		"supply_id": supply_id,
		"pickup_id": pickup_id,
		"pots": pots,
		"autos": autos,
		"seatables": seatables,
		"dish_ids": dish_ids,
		"front_dishes": front_dishes,
		"kitchen_dishes": kitchen_dishes,
		"chains": chains,
		"station_output": station_output,
		"station_input": station_input
	}


static func single_steps(shop: SpecShop, counter_id: String, order: Dictionary) -> Array:
	var take := shop.station(counter_id).params
	var take_label := "收钱" if shop.fulfillment.pay_at == "on_take" else "接单"
	var steps := [{"point": counter_id, "action": "take", "seconds": float(take.get("take_seconds", 0.0)), "label": take_label, "station": counter_id}]
	var f := shop.fulfillment
	var dishes: Array = []
	if order.addon and order.kind != f.addon_dish and f.addon_first: dishes.append(f.addon_dish)
	dishes.append(order.kind)
	if order.addon and order.kind != f.addon_dish and not f.addon_first: dishes.append(f.addon_dish)
	for id in dishes:
		for s in shop.dish(id).steps:
			# 站位：布局里有“机器.动作”就站那儿（比如从锅里拿成品站在成品筐前），否则站机器前
			var point: String = s.station + "." + s.action
			if not shop.layout.aliases.has(point): point = s.station
			# holds：做完这一步手上拿着什么（只给界面画，不参与结算）
			var holds: String = s.produces.keys()[0] if not s.produces.is_empty() else ""
			steps.append({"point": point, "action": s.action, "seconds": s.seconds * s.repeat, "label": s.label, "station": s.station, "holds": holds, "fixed": s.fixed, "into_machine": s.into_machine, "put_down": s.put_down})
	for id in order.get("options", []):
		var option := _option(shop, String(id))
		if option == null or option.step == null: continue
		var s := option.step
		var station: String = s.station if not s.station.is_empty() else option.station
		var point: String = station + "." + s.action
		if not shop.layout.aliases.has(point): point = station
		var holds: String = s.produces.keys()[0] if not s.produces.is_empty() else ""
		steps.append({"point": point, "action": s.action, "seconds": s.seconds * s.repeat, "label": s.label, "station": station, "holds": holds, "fixed": s.fixed, "into_machine": s.into_machine, "put_down": s.put_down})
	steps.append({"point": counter_id, "action": "hand", "seconds": float(take.get("hand_seconds", 0.0)),
		"label": "递餐" if shop.fulfillment.pay_at == "on_take" else "递餐收钱", "station": counter_id})
	return steps


static func _option(shop: SpecShop, id: String) -> SpecOrderOption:
	for option in shop.order_options:
		if option.id == id: return option
	return null

