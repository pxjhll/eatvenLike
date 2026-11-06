extends RefCounted
## 跨店存档 user://profile.json：现在开到第几家店、每家店的结店纪录。
## 和店内存档分开；店内存档换店时清空，这里一直保留。员工升级（凭结店评分）以后加在这里。

const DEFAULT_PATH := "user://profile.json"
const VERSION := 1
const SHOPS := ["pancake", "tea"]
const SHOP_NAMES := {"pancake": "煎饼果子摊", "tea": "手作奶茶店"}

var path := DEFAULT_PATH
var shop := "pancake"
var records: Array = []
## 刚从上一家店过来、新店还没开局（新店要从空店开始）。
var fresh_shop := false


func _init(path_ := DEFAULT_PATH) -> void:
	path = path_
	load_profile()


func next_shop(current: String) -> String:
	var i := SHOPS.find(current)
	return SHOPS[i + 1] if i >= 0 and i + 1 < SHOPS.size() else ""


## 结店：记一行纪录，切到下一家店。
func finish_shop(record: Dictionary) -> void:
	records.append(record)
	var nxt := next_shop(String(record.get("shop", shop)))
	if not nxt.is_empty():
		shop = nxt
		fresh_shop = true
	save()


func to_dict() -> Dictionary:
	return {"version": VERSION, "shop": shop, "records": records.duplicate(true), "fresh_shop": fresh_shop}


func save() -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return DirAccess.rename_absolute(tmp, path)


func load_profile() -> void:
	shop = "pancake"
	records = []
	fresh_shop = false
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return
	if String(data.get("shop", "pancake")) in SHOPS: shop = String(data.shop)
	var r: Variant = data.get("records", [])
	if r is Array: records = r
	fresh_shop = bool(data.get("fresh_shop", false))


## 从第一家店重新玩（调试 / 试玩用）。
func reset_all() -> void:
	shop = "pancake"
	records = []
	fresh_shop = false
	save()
