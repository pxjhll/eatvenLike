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

const MachineWorkSprite := preload("res://presentation/shop/machine_work_sprite.gd")
var _machine_sprites: Array[MachineWorkSprite] = []
var _modules: Array[Node] = []
var _groups := {}
var _rules := {}
var _followers: Array[CanvasItem] = []


func _init(art: Node2D) -> void:
	for node in art.find_children("*", "CanvasItem", true, false):
		if node is MachineWorkSprite: _machine_sprites.append(node)
		if node.get_script() == Module: _modules.append(node)
		if node.has_meta("follows"): _followers.append(node)
		if not node.has_meta("layout_group"): continue
		var group: String = node.get_meta("layout_group")
		if not _groups.has(group):
			_groups[group] = []
			_rules[group] = node.get_meta("unlock_rule", "always")
		_groups[group].append(node)


func update_machines(machines: Dictionary, clock: float) -> void:
	for sprite in _machine_sprites:
		sprite.show_machine_state(machines, clock)


func update(view: ShopView) -> void:
	for node in _modules: node.refresh_visual(view)
	for group in _groups:
		var visible := view.art_visible(_rules[group])
		for node: CanvasItem in _groups[group]:
			if node.visible != visible: node.visible = visible
	for node in _followers:
		var owner: Variant = node.get_meta("follows")
		node.visible = owner is CanvasItem and is_instance_valid(owner) and (owner as CanvasItem).is_visible_in_tree()

## One-shot projection for callers that assemble and inspect a scene.
static func refresh(art: Node2D, view: ShopView) -> void:
	new(art).update(view)
