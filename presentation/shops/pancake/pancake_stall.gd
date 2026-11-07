@tool
extends Node2D
## 煎饼摊原画（v04，源坐标 937×1678）。玩法状态由通用店铺场景按节点上的标记刷新（ArtGroups）：
## 功能台的分组带 unlock_key（= 机器 id），坐垫按批次随等位数显示，接触阴影和台面文字跟着各自的物件。
## 这里只管这张图自己的事：哪些分组是哪台机器、哪些物件会挡住人物（z = 落地的 y）。

## 坐垫三批，每批到店里有这么多等位时摆出来（累计 2 / 5 / 9 个）
const CUSHION_GROUPS := {165: 2, 164: 5, 163: 9}
## 会挡住人物的物件：z = 物件落地的 y（源坐标）。人物的 z = 脚底 y，谁更靠前谁画在上面。
## 没列出的（天空、地砖、靠墙的桌子和后排设备、坐垫、野餐毯）都在人物下面。
## 摆在台面上的东西跟着台子走：豆浆机、台面文字用柜台的值。
const DEPTH := {
	41: 734, 42: 734, 43: 734,
	46: 976, 161: 976, 144: 976, 145: 976, 146: 976, 147: 976, 148: 976,
	63: 1118,
}

var _by_id := {}


func _ready() -> void:
	# 编辑器里打开场景时全部显示，方便摆图
	if Engine.is_editor_hint(): return
	for id in DEPTH:
		var node := source_node(id)
		if node != null: node.z_index = DEPTH[id]
	for node in find_children("*", "CanvasItem", true, false):
		if node.has_meta("unlock_key"):
			node.set_meta("layout_group", "station:" + String(node.get_meta("unlock_key")))
			node.set_meta("unlock_rule", String(node.get_meta("unlock_key")))
		# 阴影、文字画在别的层里，跟着它的主人显示
		if node.has_meta("owner_figcraft_id"):
			var owner := source_node(int(node.get_meta("owner_figcraft_id")))
			if owner != null: node.set_meta("follows", owner)
	for id in CUSHION_GROUPS:
		var group := source_node(id)
		if group == null: continue
		group.set_meta("layout_group", "cushions:%d" % id)
		group.set_meta("unlock_rule", "wait_seats:%d" % CUSHION_GROUPS[id])


func source_node(id: int) -> CanvasItem:
	if _by_id.is_empty():
		for node in find_children("*", "CanvasItem", true, false):
			if node.has_meta("figcraft_id"):
				_by_id[int(node.get_meta("figcraft_id"))] = node
	return _by_id.get(id)
