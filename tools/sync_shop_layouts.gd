extends SceneTree
## Export authored coordinates; --check never writes. Validate all before saving any.
## --shop=<resource> selects one shop; --campaign=<resource> selects a campaign.
const CAMPAIGN := "res://content/campaign/campaign.tres"
const Contract := preload("res://presentation/shop/shop_scene_contract.gd")
const Schema := preload("res://game/rules/shop_spec_validator.gd")
const Layout := preload("res://presentation/shop/modules/module_layout.gd")

func _initialize() -> void:
	var check := false
	var shop_path := ""
	var campaign_path := ""
	var invalid := false
	for arg in OS.get_cmdline_user_args():
		if arg=="--check": check = true
		elif arg.begins_with("--shop=") and shop_path.is_empty():
			shop_path = arg.substr(7)
			if shop_path.is_empty(): invalid = true
		elif arg.begins_with("--campaign=") and campaign_path.is_empty():
			campaign_path = arg.substr(11)
			if campaign_path.is_empty(): invalid = true
		else: invalid = true
	if invalid or (not shop_path.is_empty() and not campaign_path.is_empty()):
		print("FAIL arguments: use --check, --shop=<path> or --campaign=<path>")
		quit(1)
		return
	var paths: Array[String] = []
	if not shop_path.is_empty(): paths.append(shop_path)
	else:
		var target := campaign_path if not campaign_path.is_empty() else CAMPAIGN
		var resource: Resource = load(target) if ResourceLoader.exists(target) else null
		if not resource is SpecCampaign:
			print("FAIL campaign resource")
			quit(1)
			return
		for city in resource.cities:
			if city==null: invalid = true; continue
			for entry in city.shops:
				if entry==null: invalid = true; continue
				if not entry.shop_path.is_empty() and entry.shop_path not in paths: paths.append(entry.shop_path)
	var candidates: Array = []
	for path in paths:
		var resource: Resource = load(path) if ResourceLoader.exists(path) else null
		var shop := resource as SpecShop
		var result := inspect(shop)
		if not result.errors.is_empty():
			invalid = true
			print("FAIL "+path+" "+Schema.summary(result.errors))
			continue
		if result.layout==null: continue
		var same := _same(result.layout,shop.layout)
		if check:
			print(("一致 " if same else "不一致 ")+path)
			invalid = invalid or not same
		elif same: print("不用改 "+path)
		else: candidates.append({"shop":shop,"path":path,"layout":result.layout})
	if invalid:
		quit(1)
		return
	for candidate: Dictionary in candidates:
		candidate.shop.layout = candidate.layout
		var error := ResourceSaver.save(candidate.shop,candidate.path)
		print(("写出 " if error==OK else "失败 ")+candidate.path)
		if error!=OK: invalid = true
	quit(1 if invalid else 0)

static func inspect(shop: SpecShop) -> Dictionary:
	if shop==null or shop.layout==null or shop.scene_path.is_empty() or not ResourceLoader.exists(shop.scene_path):
		return {"layout":null,"errors":[{"code":"scene_resource","path":"scene_path","message":"A shop and existing art scene are required."}]}
	var packed: Resource = load(shop.scene_path)
	if not packed is PackedScene or not packed.can_instantiate():
		return {"layout":null,"errors":[{"code":"scene_resource","path":"scene_path","message":"An instantiable PackedScene is required."}]}
	var art: Node = packed.instantiate()
	# Only stale exported coordinates may be repaired. Other authoring errors stop writes.
	var anchors := ShopAnchors.new(art.get_node_or_null("Anchors"))
	var repairable := ["layout_mismatch"]
	if anchors.has("Nav"): repairable.append("movement_units")
	var errors: Array = Contract.validate(shop,art).filter(func(e: Dictionary) -> bool: return e.code not in repairable)
	var result := {"layout":null,"errors":errors}
	if errors.is_empty() and anchors.has("Nav"):
		result = anchors.export_layout(shop.layout)
		if result.layout!=null:
			var candidate := shop.copy_for_editing()
			candidate.layout = result.layout
			result.errors.append_array(Schema.validate(candidate))
			result.errors.append_array(Contract.validate(candidate,art))
			if not result.errors.is_empty(): result.layout = null
	art.free()
	return result

static func synced_layout(shop: SpecShop) -> SpecLayout:
	return inspect(shop).layout

static func _same(a: SpecLayout, b: SpecLayout) -> bool:
	for key in Layout.FIELDS:
		if a.get(key)!=b.get(key): return false
	return true
