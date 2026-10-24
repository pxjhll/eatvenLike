class_name OrderState
extends RefCounted
## 一位顾客的一张订单。

enum State { WAITING_STOCK, WAITING_SERVICE }

var id := -1
var dish_id := ""
var state: int = State.WAITING_STOCK
## 没人接待时累计的等待秒数
var wait := 0.0
var request_id := -1


func to_dict() -> Dictionary:
	return {"id": id, "dish": dish_id, "state": state, "wait": wait, "request": request_id}


static func from_dict(d: Dictionary) -> OrderState:
	var o := OrderState.new()
	o.id = int(d.id)
	o.dish_id = String(d.dish)
	o.state = int(d.state)
	o.wait = float(d.wait)
	o.request_id = int(d.request)
	return o
