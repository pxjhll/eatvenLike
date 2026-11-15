extends SceneTree
## Read-only authoring gate: production campaign plus the isolated third-shop fixture.
## godot --headless --path . -s tools/validate_shops.gd

const Schema := preload("res://game/rules/shop_spec_validator.gd")
const SceneContract := preload("res://presentation/shop/shop_scene_contract.gd")
const CAMPAIGNS := [
	preload("res://content/campaign/campaign.tres"),
	preload("res://tests/fixtures/noodle/campaign.tres"),
	preload("res://tests/fixtures/onboarding/campaign.tres"),
]

func _initialize() -> void:
	var failed := false
	var checked := 0
	for campaign: SpecCampaign in CAMPAIGNS:
		for city in campaign.cities:
			for entry in city.shops:
				if entry.shop_path.is_empty(): continue
				checked += 1
				var errors: Array = []
				var shop: SpecShop
				if ResourceLoader.exists(entry.shop_path): shop = load(entry.shop_path) as SpecShop
				errors.append_array(Schema.validate(shop, campaign))
				if errors.is_empty():
					var candidate := SceneContract.prepare(shop)
					errors.append_array(candidate.errors)
					if candidate.art != null: candidate.art.free()
				print("%s %s" % ["OK" if errors.is_empty() else "FAIL", entry.shop_path])
				if not errors.is_empty():
					failed = true
					print(Schema.summary(errors))
	print("SHOP VALIDATION: %d shops, %s" % [checked, "FAILED" if failed else "passed"])
	quit(1 if failed else 0)
