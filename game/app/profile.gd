extends RefCounted
## 跨店存档 user://profile.json：现在开到第几家店、每家店的结店纪录。
## 和店内存档分开；店内存档换店时清空，这里一直保留。员工升级（凭结店评分）以后加在这里。

const DEFAULT_PATH := "user://profile.json"
const VERSION := 1
## 店铺顺序来自关卡表（规格 §3.14），这里不再写死店名。
const CAMPAIGN: SpecCampaign = preload("res://content/campaign/campaign.tres")

var path := DEFAULT_PATH
var shop := ""
var records: Array = []
## 刚从上一家店过来、新店还没开局（新店要从空店开始）。
var fresh_shop := false
## 以下是规格 §3.13 / §3.14 预留的跨店字段，现在只存不用：
## 当前城市、奖杯余额、永久加成等级 {perk id: 等级}、已开放的员工种类（店长回访带来）、已触发过的一次性奇遇。
var city := "north"
var trophies := 0
var perk_levels: Dictionary = {}
var staff_kinds: Array = []
var events_seen: Array = []


static func shops() -> Array[String]:
	## 关卡表里已经做好（有店铺数据）的店，按顺序
	var ids: Array[String] = []
	for c in CAMPAIGN.cities:
		for entry in c.shops:
			if not entry.shop_path.is_empty(): ids.append(entry.id)
	return ids


func _init(path_ := DEFAULT_PATH) -> void:
	path = path_
	load_profile()


func next_shop(current: String) -> String:
	return CAMPAIGN.next_shop(current)


## 结店：记一行纪录，切到下一家店。
func finish_shop(record: Dictionary) -> void:
	records.append(record)
	var nxt := next_shop(String(record.get("shop", shop)))
	if not nxt.is_empty():
		shop = nxt
		fresh_shop = true
	save()


func to_dict() -> Dictionary:
	return {"version": VERSION, "shop": shop, "records": records.duplicate(true), "fresh_shop": fresh_shop,
		"city": city, "trophies": trophies, "perk_levels": perk_levels.duplicate(), "staff_kinds": staff_kinds.duplicate(),
		"events_seen": events_seen.duplicate()}


func save() -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return DirAccess.rename_absolute(tmp, path)


func load_profile() -> void:
	_clear()
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return
	if String(data.get("shop", "")) in shops(): shop = String(data.shop)
	var r: Variant = data.get("records", [])
	if r is Array: records = r
	fresh_shop = bool(data.get("fresh_shop", false))
	city = String(data.get("city", city))
	trophies = int(data.get("trophies", 0))
	if data.get("perk_levels") is Dictionary: perk_levels = data.perk_levels
	if data.get("staff_kinds") is Array: staff_kinds = data.staff_kinds
	if data.get("events_seen") is Array: events_seen = data.events_seen


## 从第一家店重新玩（调试 / 试玩用）。
func reset_all() -> void:
	_clear()
	save()


func _clear() -> void:
	shop = shops()[0]
	records = []
	fresh_shop = false
	city = CAMPAIGN.cities[0].id
	trophies = 0
	perk_levels = {}
	staff_kinds = []
	events_seen = []
