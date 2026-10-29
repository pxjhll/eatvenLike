class_name BeltSegmentState
extends RefCounted
## 一条连接上的传送带。物料按「格」记位置，items[0] 离终点最近。

var id := ""
var from_slot := ""
var to_slot := ""
var length := 1.0
var connected := true
## 这个机位启用后这条带不再送货（ConnectionDef.until_active）
var until_active := ""
## 每件 {"item": String, "pos": float}
var items: Array[Dictionary] = []


static func create(conn: ConnectionDef) -> BeltSegmentState:
	var seg := BeltSegmentState.new()
	seg.id = conn.id
	seg.from_slot = conn.from_slot
	seg.to_slot = conn.to_slot
	seg.length = conn.length_cells
	seg.connected = conn.initially_connected
	seg.until_active = conn.until_active
	return seg


func item_counts() -> Dictionary:
	var out := {}
	for it in items:
		out[it.item] = int(out.get(it.item, 0)) + 1
	return out


func to_dict() -> Dictionary:
	var list := []
	for it in items:
		list.append({"item": it.item, "pos": it.pos})
	return {"id": id, "connected": connected, "items": list}


## 连接的端点和长度来自 ConnectionDef，存档里只放运行状态
func load_dict(d: Dictionary) -> void:
	connected = bool(d.connected)
	items.clear()
	for it in d.items:
		items.append({"item": String(it.item), "pos": float(it.pos)})
