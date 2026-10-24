class_name WorkRequest
extends RefCounted
## 一项人工工作。存在与取消归请求方（Production / FrontHall），id 由 GameSim 发号；
## 认领关系与人工进度归 Workforce。

enum Kind { LOAD, UNLOAD, WORK, SERVE }

var id := -1
var kind: int = Kind.WORK
var zone := ""
var seconds := 0.0
## 后厨请求对应的机位
var slot_id := ""
## 前厅请求对应的订单
var order_id := -1


static func create(new_id: int, kind_: int, zone_: String, seconds_: float) -> WorkRequest:
	var r := WorkRequest.new()
	r.id = new_id
	r.kind = kind_
	r.zone = zone_
	r.seconds = seconds_
	return r


## 交给 Workforce 的只读副本
func as_open() -> Dictionary:
	return {"id": id, "zone": zone, "seconds": seconds}


func to_dict() -> Dictionary:
	return {"id": id, "kind": kind, "zone": zone, "seconds": seconds, "slot": slot_id, "order": order_id}


static func from_dict(d: Dictionary) -> WorkRequest:
	var r := WorkRequest.create(int(d.id), int(d.kind), String(d.zone), float(d.seconds))
	r.slot_id = String(d.slot)
	r.order_id = int(d.order)
	return r
