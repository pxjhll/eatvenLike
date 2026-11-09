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
## 无效或未来版本的原件保留不动；调用方可以显示原因并重试读取。
var last_error := ""
var load_error: Error = OK
var _write_blocked := false


static func shops() -> Array[String]:
	## 关卡表里已经做好（有店铺数据）的店，按顺序
	var ids: Array[String] = []
	for c in CAMPAIGN.cities:
		for entry in c.shops:
			if not entry.shop_path.is_empty(): ids.append(entry.id)
	return ids


func _init(path_ := DEFAULT_PATH) -> void:
	path = path_
	_clear()
	load_profile()


func next_shop(current: String) -> String:
	return CAMPAIGN.next_shop(current)


## 结店：记一行纪录，切到下一家店。
func finish_shop(record: Dictionary) -> Error:
	if record.get("shop", shop) != shop or fresh_shop:
		last_error = "结店失败：当前店铺已经变更"
		return ERR_INVALID_PARAMETER
	var candidate := to_dict()
	candidate.records.append(record.duplicate(true))
	var nxt := next_shop(shop)
	if not nxt.is_empty():
		candidate.shop = nxt
		candidate.fresh_shop = true
	return _commit(candidate)


func select_shop(target: String) -> Error:
	if target not in shops():
		last_error = "切店失败：目标店铺不存在"
		return ERR_INVALID_PARAMETER
	var candidate := to_dict()
	candidate.shop = target
	candidate.fresh_shop = false
	return _commit(candidate)


func acknowledge_fresh_shop() -> Error:
	var candidate := to_dict()
	candidate.fresh_shop = false
	return _commit(candidate)


func to_dict() -> Dictionary:
	return {"version": VERSION, "shop": shop, "records": records.duplicate(true), "fresh_shop": fresh_shop,
		"city": city, "trophies": trophies, "perk_levels": perk_levels.duplicate(), "staff_kinds": staff_kinds.duplicate(),
		"events_seen": events_seen.duplicate()}


func save() -> Error:
	return _commit(to_dict())


func _commit(candidate: Dictionary) -> Error:
	var guard := check_writable()
	if guard != OK: return guard
	var message := _validate(candidate)
	if not message.is_empty():
		last_error = message
		return ERR_INVALID_DATA
	var error := _write_candidate(candidate)
	if error != OK:
		last_error = "跨店进度写入失败：%s。请检查空间或权限后重试。" % error_string(error)
		return error
	_apply(candidate)
	last_error = ""
	return OK


## 新店清空文件之前也必须确认 Profile 可写，避免覆盖未识别的永久进度。
func check_writable() -> Error:
	if _write_blocked: return load_error
	# 每次写前重读磁盘，保护程序启动后被替换的未来版本或坏文件。
	var existing := _read_existing()
	if existing.error != OK:
		_block(existing)
		return load_error
	return OK


## 单一写入边界；测试可覆写注入失败。只在替换成功后由 _commit 更新内存。
func _write_candidate(candidate: Dictionary) -> Error:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(candidate, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(tmp)
		return error
	return DirAccess.rename_absolute(tmp, path)


func load_profile() -> Error:
	var result := _read_existing()
	if result.error != OK:
		_block(result)
		return load_error
	_write_blocked = false
	load_error = OK
	last_error = ""
	if result.has("data"): _apply(result.data)
	return OK


func _read_existing() -> Dictionary:
	if not FileAccess.file_exists(path): return {"error": OK}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": FileAccess.get_open_error(), "message": "无法读取跨店进度，请检查文件权限后重试。"}
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error not in [OK, ERR_FILE_EOF]:
		return {"error": read_error, "message": "跨店进度读取失败，原文件已保留。"}
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"error": ERR_INVALID_DATA, "message": "跨店进度 JSON 无效，原文件已保留；请恢复有效备份后重试。"}
	var data: Dictionary = json.data
	var version: Variant = data.get("version", VERSION)
	if _integer(version) and version > VERSION:
		return {"error": ERR_UNAVAILABLE, "message": "跨店进度来自更高版本，已停止写入；请使用更新的程序打开。"}
	var message := _validate(data)
	if not message.is_empty(): return {"error": ERR_INVALID_DATA, "message": message + "；原文件已保留，请恢复有效备份后重试。"}
	return {"error": OK, "data": data}


func _block(result: Dictionary) -> void:
	_write_blocked = true
	load_error = result.error
	last_error = result.message


func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


func _validate(data: Dictionary) -> String:
	# 缺失 version 的历史文件兼容为 v1；字符串、布尔、非整数版本均拒绝。
	var version: Variant = data.get("version", VERSION)
	if not _integer(version) or version != VERSION: return "跨店进度版本无效或不受支持"
	# 店铺 id 不认识（改名或删店）不算坏档：读入时退回第一家店，见 _apply。
	if not data.get("shop", shop) is String: return "跨店进度店铺无效"
	if not data.get("records", []) is Array: return "跨店进度结店记录无效"
	for record in data.get("records", []):
		if not record is Dictionary: return "跨店进度结店记录无效"
	if not data.get("fresh_shop", false) is bool: return "跨店进度开店标记无效"
	if not data.get("city", city) is String: return "跨店进度city 无效"
	if not _integer(data.get("trophies", 0)) or data.get("trophies", 0) < 0: return "跨店进度奖杯无效"
	if not data.get("perk_levels", {}) is Dictionary: return "跨店进度加成无效"
	for key in data.get("perk_levels", {}):
		if not _integer(data.perk_levels[key]) or data.perk_levels[key] < 0: return "跨店进度加成无效"
	for field in ["staff_kinds", "events_seen"]:
		if not data.get(field, []) is Array: return "跨店进度列表无效"
		for value in data.get(field, []):
			if not value is String: return "跨店进度列表无效"
	return ""


## 结店纪录里排得最靠后的那家店的下一家（已经是最后一家就停在它）；没有纪录就是第一家。
func _furthest_shop() -> String:
	var ids := shops()
	var at := -1
	for record in records:
		at = maxi(at, ids.find(String(record.get("shop", ""))))
	if at < 0: return ids[0]
	var nxt := next_shop(ids[at])
	return nxt if nxt in ids else ids[at]


func _apply(data: Dictionary) -> void:
	shop = data.get("shop", shops()[0])
	fresh_shop = data.get("fresh_shop", false)
	records = data.get("records", []).duplicate(true)
	if shop not in shops():
		# 店改名或删掉了：退到结店纪录里打到的最远一家（它的下一家），不白玩；
		# 不带开店标记，那家店有存档就接着玩，没有就从空店开始。
		shop = _furthest_shop()
		fresh_shop = false
	city = data.get("city", CAMPAIGN.cities[0].id)
	trophies = int(data.get("trophies", 0))
	perk_levels = data.get("perk_levels", {}).duplicate(true)
	staff_kinds = data.get("staff_kinds", []).duplicate(true)
	events_seen = data.get("events_seen", []).duplicate(true)


## 从第一家店重新玩（调试 / 试玩用）。
func reset_all() -> Error:
	var candidate := {"version": VERSION, "shop": shops()[0], "records": [], "fresh_shop": false,
		"city": CAMPAIGN.cities[0].id, "trophies": 0, "perk_levels": {}, "staff_kinds": [], "events_seen": []}
	return _commit(candidate)


func _clear() -> void:
	shop = shops()[0]
	records = []
	fresh_shop = false
	city = CAMPAIGN.cities[0].id
	trophies = 0
	perk_levels = {}
	staff_kinds = []
	events_seen = []
