extends RefCounted
## Definition-only dependencies. Running state stays in unit.done and goods.
const WORK := ["hand","combine"]
const SOURCE := ["supply","batch_pot"]

static func work_steps(shop: SpecShop, dish_id: String) -> Array[int]:
	var result: Array[int] = []
	var dish := shop.dish(dish_id)
	for index in dish.steps.size():
		var station := shop.station(dish.steps[index].station)
		if station!=null and station.block in WORK: result.append(index)
	return result

static func producer(shop: SpecShop, dish_id: String, item: String) -> int:
	var dish := shop.dish(dish_id)
	for index in dish.steps.size():
		if dish.steps[index].produces.has(item): return index
	return -1

static func blocked_inputs(shop: SpecShop, dish_id: String, index: int, done: Array) -> bool:
	for item in shop.dish(dish_id).steps[index].consumes:
		var source := producer(shop,dish_id,item)
		if source>=0 and source in work_steps(shop,dish_id) and source not in done: return true
	return false

static func pending_input(shop: SpecShop, dish_id: String, done: Array, station: String, item: String) -> int:
	var needed := 0
	for index in work_steps(shop,dish_id):
		var step: SpecStep = shop.dish(dish_id).steps[index]
		if index not in done and step.station==station: needed += int(step.consumes.get(item,0))
	return needed

static func _error(errors: Array, code: String, path: String) -> void:
	errors.append({"code":code,"path":path,"message":code.replace("_"," ")})

static func _counts(values: Dictionary) -> Array:
	var keys := values.keys()
	keys.sort()
	var out: Array = []
	for key in keys: out.append([key,int(values[key])])
	return out

static func compile(shop: SpecShop, dish_id: String) -> Dictionary:
	var nodes: Array = []
	var producers := {}
	var errors: Array = []
	var signature_data: Array = []
	var dish := shop.dish(dish_id)
	if dish==null: return {"nodes":[],"order":[],"producers":{},"errors":[{"code":"missing_recipe","path":dish_id,"message":"missing recipe"}],"signature":""}
	for index in dish.steps.size():
		var step := dish.steps[index]
		var node := {"index":index,"station":"","kind":"","dependencies":[]}
		nodes.append(node)
		if step==null:
			_error(errors,"missing_step","steps[%d]"%index)
			continue
		node.station = step.station
		var station := shop.station(step.station)
		node.kind = "source" if station!=null and station.block in SOURCE else "work"
		if station==null or station.block not in SOURCE+WORK: _error(errors,"unsupported_station","steps[%d].station"%index)
		signature_data.append([step.station,step.action,_counts(step.consumes),_counts(step.produces)])
		for item in step.produces:
			if producers.has(item): _error(errors,"ambiguous_producer","steps[%d].produces.%s"%[index,item])
			else: producers[item] = index
	var demand := {}
	for index in dish.steps.size():
		var step := dish.steps[index]
		if step==null: continue
		for item in step.consumes:
			demand[item] = int(demand.get(item,0))+int(step.consumes[item])
			if not producers.has(item):
				_error(errors,"missing_input","steps[%d].consumes.%s"%[index,item])
				continue
			var dependency := int(producers[item])
			if dependency not in nodes[index].dependencies: nodes[index].dependencies.append(dependency)
		nodes[index].dependencies.sort()
	if not producers.has(dish.item): _error(errors,"missing_output","item")
	else:
		var final: SpecStep = dish.steps[int(producers[dish.item])]
		if int(final.produces[dish.item])!=1: _error(errors,"final_quantity","item")
	for item in demand:
		if not producers.has(item): continue
		var index := int(producers[item])
		if nodes[index].kind=="work" and int(dish.steps[index].produces[item])<int(demand[item]):
			_error(errors,"insufficient_output","steps[%d].produces.%s"%[index,item])
	for item in producers:
		var index := int(producers[item])
		if nodes[index].kind!="work": continue
		var needed := int(demand.get(item,0))+(1 if item==dish.item else 0)
		if int(dish.steps[index].produces[item])>needed: _error(errors,"unconsumed_output","steps[%d].produces.%s"%[index,item])
	var order: Array = []
	while order.size()<nodes.size():
		var next := -1
		for index in nodes.size():
			if index in order: continue
			var ready := true
			for dependency in nodes[index].dependencies:
				if dependency not in order: ready = false; break
			if ready: next = index; break
		if next<0:
			_error(errors,"cycle","steps")
			break
		order.append(next)
	return {"nodes":nodes,"order":order,"producers":producers,"errors":errors,
		"signature":var_to_bytes([dish.item,signature_data]).hex_encode().sha256_text()}
