extends RefCounted
const Module := preload("res://presentation/shop/modules/shop_module.gd")
## 美术场景里按玩法状态显示的分组（通用）：节点上的 layout_group / unlock_rule 标记，同一组用同一条规则。
##   always              一直显示
##   <机器 id>           这台机器开了才显示
##   belt:<连接 id>      这段传送带买了才显示
##   ingredient_box      买过任意一个原料箱
##   box:<原料 id>       买了这个原料箱
##   flavor:<菜 id>      这道口味菜开了（加料台上的料盘）
##   wait_seats:<N>      至少有 N 个等位座（买来的，或阶段直接给的）
##   dine_seats:<N>      至少有 N 个堂食座（没挂堂食组件的场景，桌椅按买到的座位数摆出来）
## 另外，带 follows 标记（指向另一个节点）的阴影、文字跟着那个节点显示。

static func refresh(art: Node2D, view: ShopView) -> void:
	var visibility := {}
	var followers: Array[CanvasItem] = []
	for node in art.find_children("*", "CanvasItem", true, false):
		if node.get_script()==Module: node.refresh_visual(view)
		if node.has_meta("follows"): followers.append(node)
		if not node.has_meta("layout_group"): continue
		var group: String = node.get_meta("layout_group")
		if not visibility.has(group):
			var rule: String = node.get_meta("unlock_rule", "always")
			visibility[group] = view.art_visible(rule)
		node.visible = visibility[group]
	for node in followers:
		var owner: Variant = node.get_meta("follows")
		node.visible = owner is CanvasItem and is_instance_valid(owner) and (owner as CanvasItem).is_visible_in_tree()
