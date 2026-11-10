extends RefCounted
const OrderState := preload("res://game/rules/rule_orders.gd")
## Owns sales counters and settlement arithmetic. Rules sequences external effects.

var gold := 0.0
var revenue := 0.0
var sold := 0
var sold_by_dish: Dictionary = {}
var sale_carry := 0.0

func count_handoff(dish: String, count: int) -> void:
	sold += count
	sold_by_dish[dish] += count

func credit_handoff(job: Dictionary, unit_price: float) -> Dictionary:
	var earned: float = unit_price * job.count + sale_carry
	var income: int = floori(earned + 0.0001)
	sale_carry = maxf(0.0, earned - income)
	gold += income
	revenue += income
	return {"dish": job.item, "count": job.count, "income": income}

func accept_single(customer: Dictionary, quoted_price: int, pay_on_take: bool) -> void:
	if pay_on_take:
		gold += quoted_price
		revenue += quoted_price
	OrderState.accept_single(customer, quoted_price)

func complete_single(customer: Dictionary, addon_dish: String, pay_on_take: bool) -> Dictionary:
	if not pay_on_take:
		gold += customer.paid
		revenue += customer.paid
	OrderState.leave_single(customer)
	sold_by_dish[customer.kind] = int(sold_by_dish[customer.kind]) + 1
	sold += 1
	if customer.addon and customer.kind != addon_dish:
		sold_by_dish[addon_dish] = int(sold_by_dish[addon_dish]) + 1
		sold += 1
	return {"dish": customer.kind, "income": customer.paid}

## 整单一次结账（送桌店：明细全部送达时）。每道菜价已保留 1 位小数，金币取整、零头累计到下一笔。
func credit_order(total: float) -> Dictionary:
	var earned: float = total + sale_carry
	var income: int = floori(earned + 0.0001)
	sale_carry = maxf(0.0, earned - income)
	gold += income
	revenue += income
	return {"income": income}
