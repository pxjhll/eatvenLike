extends ShopSave
## Historical fixtures run the frozen reference engine; formal saves never do.
const Reference := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
func make_rules() -> ShopRules:
	return Reference.new(shop)

func requires_shared_runtime() -> bool:
	return false
