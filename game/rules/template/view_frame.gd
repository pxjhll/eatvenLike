extends RefCounted
const Inventory := preload("res://game/rules/template/inventory.gd")
const Processing := preload("res://game/rules/template/processing_display.gd")
## Detached UI and item display data from the authoritative public ledger.
## A stock lot does not create a scene sprite. Showcase ports must be explicit.

static func build(inventory: RefCounted, machines: RefCounted, displays: Array = []) -> Dictionary:
	var source: Dictionary = inventory.snapshot()
	var frame := {"error":"", "stock":{}, "held":{}, "machines":{}, "draws":[]}
	var lots := {}
	for place in source.places: frame.stock[place] = {"count":0, "reserved":0, "available":0, "items":{}}
	for lot in source.lots:
		lots[lot.id] = lot
		var stock: Dictionary = frame.stock[lot.place]
		if not stock.items.has(lot.item): stock.items[lot.item] = {"count":0, "reserved":0, "available":0}
		stock.items[lot.item].count += int(lot.count)
		stock.count += int(lot.count)
		if Inventory.is_hand_place(lot.place):
			var worker: Variant = int(String(lot.place).trim_prefix("hand:")) if String(lot.place).begins_with("hand:") else String(lot.place).trim_prefix("hand@")
			if not frame.held.has(worker): frame.held[worker] = {"items":[], "count":0}
			var found := false
			for item in frame.held[worker].items:
				if item.item != lot.item: continue
				item.count += int(lot.count)
				found = true
				break
			if not found: frame.held[worker].items.append({"item":lot.item, "count":int(lot.count)})
			frame.held[worker].count += int(lot.count)
	for task in source.claims:
		if task.state not in ["reserved", "held"]: continue
		var parts: Array = task.parts if task.state == "reserved" else task.held
		for part in parts:
			var lot: Dictionary = lots[part.lot]
			frame.stock[lot.place].items[lot.item].reserved += int(part.count)
			frame.stock[lot.place].reserved += int(part.count)
	for place in frame.stock:
		var stock: Dictionary = frame.stock[place]
		stock.available = int(stock.count) - int(stock.reserved)
		for item in stock.items.values(): item.available = int(item.count) - int(item.reserved)
	var devices: Dictionary = machines.snapshot()
	for id in devices.definitions: frame.machines[id] = machines.status(id)
	var shown := {}
	var processing := {}
	for binding in displays:
		var error := ""
		if binding is Dictionary and binding.get("capability") == "processing_item":
			error = Processing.binding_error(binding,source.places,devices.definitions,processing)
			if error.is_empty(): processing[binding.machine] = {}
		else:
			error = _binding_error(binding, source.places, shown)
			if error.is_empty():
				for place in binding.get("places",[binding.get("place","")]): shown[place] = true
		if not error.is_empty():
			frame.error = error
			frame.draws = []
			return frame
	var hidden := {}
	for binding in displays:
		if binding.capability != "processing_item": continue
		var projected := Processing.project(binding,source,devices)
		if not projected.error.is_empty():
			frame.error = projected.error
			return frame
		processing[binding.machine] = projected
		for lot in projected.hidden: hidden[lot] = int(hidden.get(lot,0)) + int(projected.hidden[lot])
	for binding in displays:
		if binding.capability == "processing_item":
			frame.draws.append_array(processing[binding.machine].draws)
			continue
		var index := 0
		for lot in source.lots:
			if lot.place not in binding.get("places",[binding.get("place","")]): continue
			for unused in mini(int(lot.count) - int(hidden.get(lot.id,0)), binding.points.size() - index):
				var draw := {"item":lot.item, "pos":binding.points[index], "host":String(binding.get("host", ""))}
				if binding.has("height"): draw.height = binding.height
				frame.draws.append(draw)
				index += 1
	return frame

static func _binding_error(binding: Variant, places: Dictionary, shown: Dictionary) -> String:
	if not binding is Dictionary: return "invalid display binding"
	for key in binding:
		if key not in ["capability", "place", "places", "points", "host", "height"]: return "unsupported display parameter: " + str(key)
	if binding.get("capability", "") != "stock_showcase": return "unsupported display capability"
	if binding.has("place")==binding.has("places"): return "showcase requires one container declaration"
	var ids: Variant = binding.get("places",[binding.get("place")])
	if not ids is Array or ids.is_empty(): return "invalid display containers"
	var seen := {}
	for place in ids:
		if not place is String or not places.has(place) or Inventory.is_hand_place(place) or shown.has(place) or seen.has(place): return "invalid display container"
		seen[place] = true
	if binding.has("height") and (not (binding.height is float or binding.height is int) or not is_finite(float(binding.height)) or binding.height<=0.0): return "invalid display height"
	var points: Variant = binding.get("points")
	if not points is Array or points.is_empty(): return "display capability requires explicit ports"
	for point in points:
		if not point is Vector2 or not point.is_finite(): return "invalid display port"
	if binding.has("host") and not binding.host is String: return "invalid display host"
	return ""
