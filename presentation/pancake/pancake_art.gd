@tool
extends Node2D
## Approved v04 coordinates remain source-space units. Gameplay supplies unlock state.

const STATIONS := {
	"rear_equipment": 21, "raw_ingredients": 26, "fryer": 31,
	"packing": 34, "topping": 40, "front_counter": 46,
	"soy_milk": 161, "rack": 166,
}
const CUSHION_GROUPS := [165, 164, 163]
## 会挡住人物的物件：z = 物件落地的 y（源坐标）。人物的 z = 脚底 y，谁更靠前谁画在上面。
## 没列出的（天空、地砖、靠墙的桌子和后排设备、坐垫、野餐毯）都在人物下面。
## 摆在台面上的东西跟着台子走：豆浆机、台面文字用柜台的值。
const DEPTH := {
	41: 734, 42: 734, 43: 734,
	46: 976, 161: 976, 144: 976, 145: 976, 146: 976, 147: 976, 148: 976,
	63: 1118,
}
## 解锁虚线框等交互物件放在所有人物上面。
const TOP_Z := 2000

@export var review_all_unlocked := false
@export var opening_stations: PackedStringArray = []
@export_range(0, 3) var opening_cushion_stage := 0
var _by_id := {}
var _unlocked := {}
var _cushion_stage := 0

func _ready() -> void:
	# 编辑器里打开场景时全部显示，方便摆图；玩法状态只在运行时生效。
	if Engine.is_editor_hint():
		show_complete_layout()
		return
	apply_depth()
	reset_layout()
	for key in opening_stations:
		set_station_unlocked(key, true)
	set_cushion_stage(opening_cushion_stage)
	if review_all_unlocked: show_complete_layout()

func apply_depth() -> void:
	for id in DEPTH:
		var node := source_node(id)
		if node != null: node.z_index = DEPTH[id]

func source_node(id: int) -> CanvasItem:
	if _by_id.is_empty():
		for node in find_children("*", "CanvasItem", true, false):
			if node.has_meta("figcraft_id"):
				_by_id[int(node.get_meta("figcraft_id"))] = node
	return _by_id.get(id)

func reset_layout() -> void:
	_unlocked.clear()
	_cushion_stage = 0
	_refresh_visibility()

func set_station_unlocked(key: String, enabled: bool) -> bool:
	if not STATIONS.has(key): return false
	_unlocked[key] = enabled
	_refresh_visibility()
	return true

func set_cushion_stage(stage: int) -> void:
	_cushion_stage = clampi(stage, 0, 3)
	_refresh_visibility()

func show_complete_layout() -> void:
	for key in STATIONS: _unlocked[key] = true
	_cushion_stage = 3
	_refresh_visibility()

func _refresh_visibility() -> void:
	for key in STATIONS:
		var group := source_node(STATIONS[key])
		if group != null: group.visible = _unlocked.get(key, false)
	for i in CUSHION_GROUPS.size():
		var group := source_node(CUSHION_GROUPS[i])
		if group != null: group.visible = i < _cushion_stage
	# Procedural layers can be siblings of their owner, at a different draw depth.
	for node in _by_id.values():
		if not node.has_meta("owner_figcraft_id"): continue
		var owner := source_node(int(node.get_meta("owner_figcraft_id")))
		var show := owner != null
		var cursor: Node = owner
		while show and cursor != self:
			if cursor is CanvasItem and not cursor.visible: show = false
			cursor = cursor.get_parent()
			if cursor == null: break
		node.visible = show
