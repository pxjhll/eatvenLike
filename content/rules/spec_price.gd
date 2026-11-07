class_name SpecPrice
extends RefCounted
## 菜价（§3.8）：每部分价格 × 作用在这部分上的所有涨价倍率。
## price 效果 price_part 为空 = 乘整道菜（每一部分都乘）；非空 = 只乘这一部分。
## 规则层第 2 个 PR 会把这些倍率并进加成栈；这里先给数据校验和面板预览用。


## levels：{机器 id: 等级, "机器 id/物料 id": 等级}；没写的按 1 级。
static func dish_price(shop: SpecShop, dish: SpecDish, levels: Dictionary) -> float:
	var total := 0.0
	for part in dish.price_parts:
		var mult := 1.0
		for station in shop.stations:
			for track in station.tracks:
				var lv: int = levels.get(station.id, 1)
				mult *= track.fold("price", lv, 1.0, dish.id, station.price_dishes)
				mult *= track.fold("price", lv, 1.0, dish.id, station.price_dishes, part)
			for material in station.materials:
				var lv: int = levels.get(station.id + "/" + material.id, 1)
				mult *= material.track.fold("price", lv, 1.0, dish.id)
				mult *= material.track.fold("price", lv, 1.0, dish.id, [], part)
		total += dish.price_parts[part] * mult
	return total
