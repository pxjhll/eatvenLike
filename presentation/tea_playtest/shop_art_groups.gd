extends RefCounted
## Individual sprites keep their sort hosts; FigCraft groups share one unlock rule.

static func refresh(art: Node2D, sim: RefCounted) -> void:
	var visibility := {}
	for node in art.find_children("*", "CanvasItem", true, false):
		if not node.has_meta("layout_group"): continue
		var group: String = node.get_meta("layout_group")
		if not visibility.has(group):
			var rule: String = node.get_meta("unlock_rule", "always")
			if rule == "always" or not sim.has_method("station_unlocked"):
				visibility[group] = true
			elif rule.begins_with("belt:"):
				# A conveyor shows once bought (old sims without belts never show it).
				visibility[group] = "belts" in sim and sim.belts.has(rule.trim_prefix("belt:"))
			elif rule == "ingredient_box":
				visibility[group] = sim.boxes.values().has(true)
			else:
				visibility[group] = sim.station_unlocked(rule)
		node.visible = visibility[group]
