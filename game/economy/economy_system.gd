class_name EconomySystem
extends RefCounted
## 当前金币、本店累计营业额、已结算 saleId。不负责通关判定。

var gold := 0
## 只有 settle() 能增加；spend() 不动它
var revenue := 0
var _settled := {}  # sale_id -> true


func setup(config: ShopConfig) -> void:
	gold = config.starting_gold


func can_spend(amount: int) -> bool:
	return amount >= 0 and gold >= amount


## 只在命令的 Commit 阶段调用；前提已在 Validate 里检查
func spend(amount: int) -> void:
	assert(can_spend(amount))
	gold -= amount


## 同一个 sale_id 第二次调用无效果，返回 false
func settle(sale_id: int, amount: int) -> bool:
	if _settled.has(sale_id):
		return false
	_settled[sale_id] = true
	gold += amount
	revenue += amount
	return true


func to_dict() -> Dictionary:
	var ids := _settled.keys()
	ids.sort()
	return {"gold": gold, "revenue": revenue, "settled": ids}


func from_dict(d: Dictionary) -> void:
	gold = int(d.gold)
	revenue = int(d.revenue)
	_settled.clear()
	for sale_id in d.settled:
		_settled[int(sale_id)] = true
