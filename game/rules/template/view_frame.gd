extends RefCounted
const Inventory := preload("res://game/rules/template/inventory.gd")
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
	for id in machines.snapshot().definitions: frame.machines[id] = machines.status(id)
	var shown := {}
	for binding in displays:
		var error := _binding_error(binding, source.places, shown)
		if not error.is_empty():
			frame.error = error
			frame.draws = []
			return frame
		shown[binding.place] = true
		var index := 0
		for lot in source.lots:
			if lot.place != binding.place: continue
			for unused in mini(int(lot.count), binding.points.size() - index):
				frame.draws.append({"item":lot.item, "pos":binding.points[index], "host":String(binding.get("host", ""))})
				index += 1
	return frame

static func _binding_error(binding: Variant, places: Dictionary, shown: Dictionary) -> String:
	if not binding is Dictionary: return "invalid display binding"
	for key in binding:
		if key not in ["capability", "place", "points", "host"]: return "unsupported display parameter: " + str(key)
	if binding.get("capability", "") != "stock_showcase": return "unsupported display capability"
	var place: Variant = binding.get("place")
	if not place is String or not places.has(place) or Inventory.is_hand_place(place) or shown.has(place): return "invalid display container"
	var points: Variant = binding.get("points")
	if not points is Array or points.is_empty(): return "display capability requires explicit ports"
	for point in points:
		if not point is Vector2 or not point.is_finite(): return "invalid display port"
	if binding.has("host") and not binding.host is String: return "invalid display host"
	return ""
