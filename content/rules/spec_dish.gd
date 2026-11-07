class_name SpecDish
extends Resource
## 菜品（§3.1）：价格 + 自己的工序链。

@export var id: String = ""
@export var display_name: String = ""
@export var item: String = ""
## 价格分成几部分：{"base": 22, "topping": 6}。price 效果可以只乘某一部分（煎饼摊加料台只给“料钱”涨价）
@export var price_parts: Dictionary[String, float] = {}
@export var steps: Array[SpecStep] = []
## 外带时要不要经过出餐口的加工环节（封口）
@export var takeaway_process: bool = true
## 前厅现做（不进后厨）
@export var front: bool = false
## 加料口味：属于哪个加料台的哪个物料
@export var flavor_station: String = ""
@export var flavor_material: String = ""
## 加几份料（全家福 3）
@export var topping_count: int = 0


func base_price() -> float:
	var total := 0.0
	for part in price_parts: total += price_parts[part]
	return total
