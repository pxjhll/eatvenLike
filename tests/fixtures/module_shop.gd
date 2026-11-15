extends RefCounted
## Existing content assembled with reusable graybox modules, never production art.
const Flow := preload("res://tests/fixtures/flow_shop.gd")
const TEMPLATE := preload("res://presentation/shop/modules/ShopTemplate.tscn")
const STATION := preload("res://presentation/shop/modules/station.tscn")
const TABLE := preload("res://presentation/shop/modules/table.tscn")

static func assemble() -> Dictionary:
	var shop := Flow.definition()
	var art: Node2D = TEMPLATE.instantiate()
	var sortables: Node2D = art.get_node("Sortables")
	for index in shop.stations.size():
		var station := shop.stations[index]
		var module: Node2D
		if station.id=="counter": module = sortables.get_node("Counter")
		else:
			module = STATION.instantiate()
			sortables.add_child(module)
		module.name = station.id
		module.module_id = "station_"+station.id
		module.station_id = station.id
		module.position = Vector2(100+(index%4)*160,220+(index/4)*160)
	for group in shop.seat_groups:
		var count := group.start+group.step*group.costs.size()
		if not group.steps.is_empty():
			count = group.start
			for amount in group.steps: count += amount
		for index in ceili(count/2.0):
			var module: Node2D = TABLE.instantiate()
			module.name = "Table%d"%index
			module.module_id = "table_%s_%d"%[group.id,index]
			module.seat_group = group.id
			module.seat_purpose = group.purpose
			module.first_seat = index*2
			module.table_index = index
			module.position = Vector2(120+(index%4)*160,680+(index/4)*200)
			sortables.add_child(module)
	var exported := ShopAnchors.new(art.get_node("Anchors")).export_layout(shop.layout)
	if exported.layout!=null: shop.layout = exported.layout
	return {"shop":shop,"art":art,"errors":exported.errors}

static func opened(shop: SpecShop) -> ShopRules:
	return Flow.opened(shop)

static func _owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if not child.scene_file_path.is_empty(): owner.set_editable_instance(child,true)
		else: _owners(child,owner)

static func persist(shop: SpecShop, art: Node2D, prefix: String) -> Dictionary:
	var packed := PackedScene.new()
	_owners(art,art)
	var result := {"shop_path":prefix+"-shop.tres","scene_path":prefix+"-art.tscn","error":packed.pack(art)}
	if result.error!=OK: return result
	result.error = ResourceSaver.save(packed,result.scene_path)
	if result.error!=OK: return result
	var copy := shop.copy_for_editing()
	copy.scene_path = result.scene_path
	result.error = ResourceSaver.save(copy,result.shop_path)
	return result
