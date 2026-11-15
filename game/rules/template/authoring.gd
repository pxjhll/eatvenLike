extends RefCounted
## Pure formal metadata checks over compiled capabilities; no legacy executor.
static func validate_global_staff(shop: SpecShop) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if shop.staff==null: return [{"code":"required","path":"staff","message":"Declare global employee resources."}]
	for kind in shop.staff.kinds:
		if kind==null:
			errors.append({"code":"required","path":"staff.kinds","message":"Employee reference is missing."})
			continue
		var canonical := "res://content/characters/staff/"+kind.id+".tres"
		if not ResourceLoader.exists(canonical) or not is_same(kind,load(canonical)):
			errors.append({"code":"reference","path":"staff.kinds."+kind.id,"message":"Reference the global employee resource; no shop-local copy."})
	return errors

static func validate(shop: SpecShop, definition: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if definition.is_empty(): return errors
	var service: Dictionary = definition.service
	for id in service.menu:
		var dish := shop.dish(id)
		if dish==null:
			errors.append({"code":"reference","path":"runtime_template.service.menu."+id,"message":"Menu dish has no shared price/art catalog definition."})
		elif definition.recipes[service.menu[id]].output.item!=dish.item:
			errors.append({"code":"reference","path":"runtime_template.service.menu."+id,"message":"Public recipe output differs from its catalog item."})
	if service.has("selection") and service.selection.stages.size()!=shop.stages.size():
		errors.append({"code":"reference","path":"runtime_template.service.selection.stages","message":"Declare one menu stage for every outer purchase stage."})
	var counters := 0
	for station in shop.stations:
		if station!=null and station.block=="counter": counters += 1
	if counters!=1: errors.append({"code":"required","path":"stations","message":"Exactly one outer counter metadata entry is required."})
	return errors
