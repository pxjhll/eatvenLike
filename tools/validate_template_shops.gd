extends SceneTree
## Release authoring gate: declarations, global staff, geometry and runtime context.
const Schema := preload("res://game/rules/shop_spec_validator.gd")
const SceneContract := preload("res://presentation/shop/shop_scene_contract.gd")
const Characters := preload("res://presentation/characters/character_library.gd")
const Authoring := preload("res://game/rules/template/authoring.gd")
func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/template_shops.json"))
	var declared := {}; var failures := []
	for row in catalog.shops: declared["res://"+row.path] = true
	for file in ["res://content/campaign/campaign.tres","res://content/examples/campaign.tres"]:
		var campaign: SpecCampaign = load(file)
		for city in campaign.cities:
			for entry in city.shops:
				if not entry.shop_path.is_empty() and not declared.has(entry.shop_path): failures.append(entry.shop_path+": missing from template catalog")
	for row in catalog.shops:
		var path: String = "res://"+row.path
		var shop: SpecShop = load(path)
		var campaign: SpecCampaign = load("res://content/campaign/campaign.tres" if row.kind=="campaign" else "res://content/examples/campaign.tres")
		var errors := Schema.validate(shop,campaign)
		if shop.get_script()!=load("res://content/rules/spec_shop.gd"): errors.append({"path":"script","message":"Use the shared data schema."})
		if shop.runtime_template==null: errors.append({"path":"runtime_template","message":"A formal template is required."})
		errors.append_array(Authoring.validate_global_staff(shop))
		for kind in shop.staff.kinds:
			if kind==null: continue
			if Characters.portrait(kind.id)==null: errors.append({"path":"staff.kinds."+kind.id,"message":"Employee has no registered visual resource."})
		if errors.is_empty():
			var prepared := SceneContract.prepare(shop)
			errors.append_array(prepared.errors)
			if prepared.art!=null: prepared.art.free()
		if errors.is_empty():
			var owner := ShopRules.new(shop,42)
			if owner.runtime==null or not owner.runtime_error.is_empty(): errors.append({"path":"runtime_template.context","message":owner.runtime_error})
		for error in errors: failures.append(path+":"+str(error.path)+": "+str(error.message))
		print("TEMPLATE AUTHORING ",path," ","passed" if errors.is_empty() else "failed")
	for failure in failures: print("FAIL ",failure)
	print("TEMPLATE AUTHORING: %d shops, %d failures"%[catalog.shops.size(),failures.size()])
	quit(1 if not failures.is_empty() else 0)
