class_name BeltSegmentState
extends RefCounted
## 一条自动铺出的传送带：从一台设备送一种物料到一台设备（或货架）。
## 物料按「格」记位置，items[0] 离终点最近。端点和长度来自 Layout 的寻路结果。

var id := ""
var from_slot := ""
var to_slot := ""
var item := ""
var length := 1.0
## 每件 {"item": String, "pos": float}
var items: Array[Dictionary] = []


static func create(id_: String, from: String, to: String, item_: String, length_: float) -> BeltSegmentState:
	var seg := BeltSegmentState.new()
	seg.id = id_
	seg.from_slot = from
	seg.to_slot = to
	seg.item = item_
	seg.length = length_
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
	return {"id": id, "from": from_slot, "to": to_slot, "item": item, "length": length, "items": list}


static func from_dict(d: Dictionary) -> BeltSegmentState:
	var seg := BeltSegmentState.create(String(d.id), String(d.from), String(d.to), String(d.item), float(d.length))
	for it in d.items:
		seg.items.append({"item": String(it.item), "pos": float(it.pos)})
	return seg
