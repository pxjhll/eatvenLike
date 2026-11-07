class_name SpecCampaign
extends Resource
## 关卡表（§3.14）：城市列表 → 每座城的店铺顺序。

@export var cities: Array[SpecCity] = []


func shop_ids() -> Array[String]:
	var ids: Array[String] = []
	for city in cities:
		for shop in city.shops: ids.append(shop.id)
	return ids


## 关卡表里 shop_id 的下一家（已做好的）店；没有就返回空
func next_shop(shop_id: String) -> String:
	var ids := shop_ids()
	var index := ids.find(shop_id)
	for city in cities:
		for shop in city.shops:
			if ids.find(shop.id) > index and index >= 0 and not shop.shop_path.is_empty(): return shop.id
	return ""
