extends RefCounted
## Explicit command/data owner for isolated capability tests. Formal entry is
## covered by the session-state and real-session suites without this fixture.
static func owner(shop: SpecShop, seed := -1) -> ShopRules:
	var copy: SpecShop = shop.duplicate(false)
	copy.runtime_template = null
	return ShopRules.new(copy,seed)
