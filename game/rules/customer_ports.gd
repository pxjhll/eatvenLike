extends RefCounted
## Shared named geometry queries, independent of business state.
static func port(rules: ShopRules, name: String) -> Vector2:
	return rules.shop.layout.customer_points.get(name,Vector2.ZERO)

static func queue_point(rules: ShopRules, slot: int) -> Vector2:
	var points := rules.shop.layout.customer_queue
	if points.is_empty(): return Vector2.ZERO
	if slot < points.size(): return points[slot]
	var step := points[-1]-points[-2] if points.size()>1 else Vector2(0,40)*rules.shop.layout.motion_units
	return points[-1]+step*float(slot-points.size()+1)

static func seat_target(rules: ShopRules, seat: int, purpose := "dine") -> String:
	for group in rules.shop.seat_groups:
		if group.purpose == purpose: return ("wait:" if purpose=="wait" else "seat:")+"%s/%d"%[group.id,seat]
	return ""
