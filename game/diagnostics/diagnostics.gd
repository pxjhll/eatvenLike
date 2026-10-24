class_name Diagnostics
extends RefCounted
## 只读统计：物料流水、销售、流失顾客、清理数量。不驱动任何规则，任务计数不放这里。

var elapsed := 0.0
## item_id -> {"produced", "consumed", "taken", "cleared"}
var item_flow := {}
## slot_id -> 产出份数（看分流和利用率用）
var produced_by_slot := {}
var sold := 0
var customers_lost := 0
var items_cleared := 0


func record(dt: float, events: Array) -> void:
	elapsed += dt
	for e in events:
		match e.type:
			"produced", "consumed", "taken", "cleared":
				var flow: Dictionary = item_flow.get(e.item, {"produced": 0, "consumed": 0, "taken": 0, "cleared": 0})
				flow[e.type] += int(e.count)
				item_flow[e.item] = flow
				if e.type == "cleared":
					items_cleared += int(e.count)
				elif e.type == "produced":
					produced_by_slot[e.slot] = int(produced_by_slot.get(e.slot, 0)) + int(e.count)
			"sold":
				sold += 1
			"customer_lost":
				customers_lost += 1


## 按流水推算场上应有的数量（用于物料守恒回归）
func expected_on_field(item: String) -> int:
	var f: Dictionary = item_flow.get(item, {"produced": 0, "consumed": 0, "taken": 0, "cleared": 0})
	return int(f.produced) - int(f.consumed) - int(f.taken) - int(f.cleared)


func to_dict() -> Dictionary:
	return {
		"elapsed": elapsed,
		"item_flow": item_flow.duplicate(true),
		"produced_by_slot": produced_by_slot.duplicate(),
		"sold": sold,
		"customers_lost": customers_lost,
		"items_cleared": items_cleared,
	}


func from_dict(d: Dictionary) -> void:
	elapsed = float(d.elapsed)
	item_flow.clear()
	for item in d.item_flow:
		item_flow[String(item)] = SaveUtil.int_dict(d.item_flow[item])
	produced_by_slot = SaveUtil.int_dict(d.produced_by_slot)
	sold = int(d.sold)
	customers_lost = int(d.customers_lost)
	items_cleared = int(d.items_cleared)
