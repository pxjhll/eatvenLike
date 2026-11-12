extends RefCounted
## Read-only shortages derived from production facts and the authoritative
## ledger. There is no second stock/order counter and no shop-specific hook.
static func build(definition: Dictionary, units: Array, stock: RefCounted, machines: RefCounted) -> Dictionary:
	var result := {}
	var outgoing := {}
	for claim in stock.snapshot().claims:
		if claim.kind != "transfer" or claim.state == "cancelled" or claim.allocate_owner < 0: continue
		if not outgoing.has(claim.allocate_owner): outgoing[claim.allocate_owner] = []
		outgoing[claim.allocate_owner].append(claim)
	for unit in units:
		var recipe: Dictionary = definition.recipes[unit.recipe]
		for node in recipe.nodes.values():
			if node.capability == "source" or node.id in unit.done: continue
			if unit.running.has(node.id):
				if node.capability == "process" and machines.run(unit.running[node.id]).get("phase", "") != "cancelled": continue
				if node.capability == "transfer":
					var group: Dictionary = stock.bundle(unit.running[node.id])
					if stock.claim(group.claims[0]).state != "cancelled": continue
			var input: String = node.place if node.capability == "transfer" else definition.machines[node.machine].input
			for item in node.consumes:
				if item in definition.places[input].infinite: continue
				var source: Dictionary = recipe.nodes[node.inputs[item]]
				if source.capability != "source": continue
				var need: int = int(node.consumes[item]) - int(stock.quantity(input, item, unit.id)) - int(stock.incoming(input, item, unit.id))
				_add(result, definition, source.place, item, need)
		var output: Dictionary = recipe.output
		var source: Dictionary = recipe.nodes[output.node]
		if source.capability != "source": continue
		var process_inputs := {}
		for node in recipe.nodes.values():
			var binding: Variant = node.inputs.get(output.item, "")
			if node.capability != "source" and binding is String and binding == source.id:
				process_inputs[node.place if node.capability == "transfer" else definition.machines[node.machine].input] = true
		var covered := 0
		for claim in outgoing.get(unit.id, []):
			if claim.from != source.place or claim.item != output.item or process_inputs.has(claim.to): continue
			covered += int(claim.count)
		_add(result, definition, source.place, output.item, int(output.count) - covered)
	return result

static func _add(result: Dictionary, definition: Dictionary, place: String, item: String, count: int) -> void:
	if count <= 0 or item in definition.places[place].infinite: return
	if not result.has(place): result[place] = {}
	result[place][item] = int(result[place].get(item, 0)) + count
