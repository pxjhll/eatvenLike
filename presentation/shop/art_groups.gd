extends RefCounted
## 美术场景里按玩法状态显示的分组（通用）：节点上的 layout_group / unlock_rule 标记，同一组用同一条规则。
##   always              一直显示
##   <机器 id>           这台机器开了才显示
##   belt:<连接 id>      这段传送带买了才显示
##   ingredient_box      买过任意一个原料箱
##   wait_seats:<N>      当前阶段至少有 N 个等位
## 另外，带 follows 标记（指向另一个节点）的阴影、文字跟着那个节点显示。

static func refresh(art: Node2D, sim: RefCounted) -> void:
	var visibility := {}
	var followers: Array[CanvasItem] = []
	for node in art.find_children("*", "CanvasItem", true, false):
		if node.has_meta("follows"): followers.append(node)
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
			elif rule.begins_with("wait_seats:"):
				visibility[group] = sim.has_method("current_stage") and sim.current_stage().wait_seats >= int(rule.get_slice(":", 1))
			else:
				visibility[group] = sim.station_unlocked(rule)
		node.visible = visibility[group]
	for node in followers:
		var owner: Variant = node.get_meta("follows")
		node.visible = owner is CanvasItem and is_instance_valid(owner) and (owner as CanvasItem).is_visible_in_tree()
