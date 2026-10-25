class_name Profile
extends RefCounted
## 跨店的玩家档案：当前店、已完成店、员工名册、个人纪录。店内系统不能写它。

var current_shop := 0
var completed_shops: Array[String] = []
## 员工名册（staff id）
var roster: Array[String] = []
## shop_id -> {"revenue": int, "seconds": float}
var records := {}


static func create(catalog: GameCatalog) -> Profile:
	var p := Profile.new()
	p.roster = catalog.starting_roster.duplicate()
	for i in catalog.shops.size():
		if catalog.shops[i].id == catalog.starting_shop_id:
			p.current_shop = i
			break
	return p


func record_shop(shop_id: String, revenue: int, seconds: float) -> void:
	if not shop_id in completed_shops:
		completed_shops.append(shop_id)
	var best: Dictionary = records.get(shop_id, {})
	if best.is_empty() or seconds < float(best.seconds):
		records[shop_id] = {"revenue": revenue, "seconds": seconds}


func to_dict() -> Dictionary:
	return {
		"current_shop": current_shop,
		"completed_shops": completed_shops.duplicate(),
		"roster": roster.duplicate(),
		"records": records.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	p.current_shop = int(d.current_shop)
	p.completed_shops = SaveUtil.string_array(d.completed_shops)
	p.roster = SaveUtil.string_array(d.roster)
	for shop_id in d.records:
		p.records[String(shop_id)] = {"revenue": int(d.records[shop_id].revenue), "seconds": float(d.records[shop_id].seconds)}
	return p
