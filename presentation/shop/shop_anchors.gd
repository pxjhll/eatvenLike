class_name ShopAnchors
extends RefCounted
## 读美术场景里的锚点（规格 §6.1）。代码里不写坐标：机器在哪、点哪里打开面板、虚线框、排队位、座位、
## 出餐口、员工坐班区，全都摆在场景的 Anchors 节点下。
##
## Anchors/
##   Stations/<机器 id>/Tap        点按打开面板的区域（矩形）
##                     /Frame      没解锁时的虚线框（矩形）
##                     /Badge      进度条和“待操作”气泡（点）
##                     /Buffer     做好等人取的那一杯摆在哪（点，meta host = 压在哪件家具上）
##                     /Post       坐班区（矩形）+ /PostPoint（点）
##   Drops/<n>                     拖员工的落点规则，按顺序判断（矩形，meta post = 落到哪个岗位 / invalid = 原因）
##   Connections/<连接 id>/Frame   传送带虚线框；/Path/0..n 带上的杯子走的路
##   Shelf/<分区>/0..n             货架上摆杯子的位置（meta host）
##   Chips/Shelf、Chips/Seats      货架、堂食的数字牌
##   Counter/Sale、Counter/Pickup、Counter/Dining
##   Queue/0..n、Seats/<组>/0..n、Tables/<组>/0..n
##   Entrance、Aisle、Lanes/0..n   客人进门、过道、座位行前的走道
##   Nav/Areas/<n>、Nav/Obstacles/<n>、Nav/Points/<名>、Nav/Posts/<名>   员工寻路（导出到店铺数据的 layout）

var root: Node
var _cache := {}


func _init(anchors: Node) -> void:
	root = anchors


func has(path: String) -> bool:
	return root != null and root.has_node(path)


func node(path: String) -> Node:
	return root.get_node_or_null(path) if root != null else null


## 相对 Anchors 的位置（Anchors 和它下面的分组都放在原点）
func point(path: String, fallback := Vector2.INF) -> Vector2:
	var n := node(path)
	if n == null: return fallback
	return _offset(n)


func rect(path: String) -> Rect2:
	var n := node(path)
	if n == null or not n is AnchorRect: return Rect2()
	return Rect2(_offset(n), (n as AnchorRect).size)


func meta(path: String, key: String, fallback: Variant = null) -> Variant:
	var n := node(path)
	return n.get_meta(key, fallback) if n != null else fallback


## 一组按序号排的点（Queue/0、Queue/1 …）
func points(path: String) -> Array[Vector2]:
	var key := "points:" + path
	if _cache.has(key): return _cache[key]
	var out: Array[Vector2] = []
	var n := node(path)
	if n != null:
		var children := n.get_children()
		children.sort_custom(func(a: Node, b: Node) -> bool: return _order(a) < _order(b))
		for child in children:
			if child is Node2D: out.append(_offset(child))
	_cache[key] = out
	return out


func children(path: String) -> Array[String]:
	var out: Array[String] = []
	var n := node(path)
	if n != null:
		for child in n.get_children(): out.append(String(child.name))
	return out


## 机器的点按区域：{id: Rect2}
func station_rects(part := "Tap") -> Dictionary:
	var out := {}
	for id in children("Stations"):
		var r := rect("Stations/%s/%s" % [id, part])
		if r.has_area(): out[id] = r
	return out


func _order(n: Node) -> int:
	return int(String(n.name)) if String(n.name).is_valid_int() else 0


func _offset(n: Node) -> Vector2:
	var total := Vector2.ZERO
	var current := n
	while current != null and current != root:
		if current is Node2D: total += (current as Node2D).position
		current = current.get_parent()
	return total


## 导出寻路数据（构建店铺数据时用）：和规则层的 SpecLayout 同一份
func layout(base: SpecLayout) -> SpecLayout:
	var out: SpecLayout = base.duplicate(true)
	if not has("Nav"): return out
	var cell: float = float(meta("Nav", "cell", out.cell))
	out.cell = cell
	out.nav = String(meta("Nav", "nav", out.nav))
	out.grid_size = meta("Nav", "grid_size", out.grid_size)
	out.areas.clear()
	for name in children("Nav/Areas"):
		var r := rect("Nav/Areas/" + name)
		out.areas.append(Rect2i(roundi(r.position.x / cell), roundi(r.position.y / cell), roundi(r.size.x / cell), roundi(r.size.y / cell)))
	out.obstacles.clear()
	for name in children("Nav/Obstacles"): out.obstacles.append(rect("Nav/Obstacles/" + name))
	out.points.clear()
	for name in children("Nav/Points"): out.points[name] = point("Nav/Points/" + name)
	out.posts.clear()
	for name in children("Nav/Posts"): out.posts[name] = point("Nav/Posts/" + name)
	return out
