class_name ShopSave
extends RefCounted
## 通用店内存档（规格 §3.12）：文件名由 SpecShop.save_file 指定，留空时用 user://shop_<店铺 id>.json。
## 存 ShopRules 的整店状态；店铺流程不兼容时可以更换文件名，旧档保留原样。
## 跨店的东西（开到第几家、结店纪录、永久加成）在 Profile 里，不在这里。旧格式存档作废，读到当没有。
## 文件：{format, version, shop, speed, guides, state(base64 二进制), state_sha256}；读写都先校验，坏档改名留底。

const FORMAT := "shop_rules"
const VERSION := 1

var shop: SpecShop
var path: String
var loaded_speed := 1.0
## 看过的引导步骤 id（和店内状态并排存，不进规则层）
var loaded_guides: Array = []
var last_error := ""
var _write_blocked := false


static func path_for(shop_id: String) -> String:
	return "user://shop_%s.json" % shop_id


func _init(shop_: SpecShop, path_ := "") -> void:
	shop = shop_
	path = path_
	if path.is_empty():
		path = "user://".path_join(shop.save_file) if not shop.save_file.is_empty() else path_for(shop.id)


func exists() -> bool:
	return FileAccess.file_exists(path)


func delete() -> void:
	if exists(): DirAccess.remove_absolute(path)


## 读档；没有或读不了就给一家新开的店（last_error 说明原因）。
func load_game() -> ShopRules:
	last_error = ""
	loaded_speed = 1.0
	loaded_guides = []
	var rules := ShopRules.new(shop)
	var result := _read_existing()
	if result.get("missing", false): return rules
	if not result.get("error", "").is_empty():
		last_error = result.error
		if result.get("future", false): _write_blocked = true
		else: _backup_corrupt()
		return rules
	var error := rules.load_dict(result.state)
	if not error.is_empty():
		last_error = "店铺存档状态无效：" + error
		_backup_corrupt()
		return ShopRules.new(shop)
	loaded_speed = result.speed
	loaded_guides = result.guides
	return rules


func save_game(rules: ShopRules, speed := 1.0, guides: Array = []) -> Error:
	last_error = ""
	if rules == null or rules.shop.id != shop.id or not is_finite(speed) or speed <= 0.0:
		last_error = "存档失败：店铺状态或播放速度无效"
		return ERR_INVALID_PARAMETER
	if _write_blocked:
		last_error = "存档版本高于当前程序，已停止写入以保留原文件"
		return ERR_UNAVAILABLE
	var state := rules.to_dict()
	var existing := _read_existing()
	if existing.get("future", false):
		_write_blocked = true
		last_error = existing.error
		return ERR_UNAVAILABLE
	if not existing.get("missing", false) and not existing.get("error", "").is_empty():
		# 旧格式或坏档：先改名留底再写新的
		last_error = existing.error
		var backup_error := _backup_corrupt()
		if backup_error != OK: return backup_error
	var bytes := var_to_bytes(state)
	var payload := {"format": FORMAT, "version": VERSION, "shop": shop.id, "speed": speed,
		"state": Marshalls.raw_to_base64(bytes), "state_sha256": bytes.hex_encode().sha256_text()}
	if not guides.is_empty(): payload.guides = guides.map(func(id: Variant) -> String: return str(id))
	var error := SaveService.new(path).save(payload)
	if error != OK:
		last_error = "存档写入失败：%s" % error_string(error)
		return error
	last_error = ""
	return OK


func _read_existing() -> Dictionary:
	if not FileAccess.file_exists(path): return {"missing": true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "无法打开店铺存档：%s" % error_string(FileAccess.get_open_error())}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"error": "店铺存档 JSON 无法解析"}
	var wrapper: Dictionary = json.data
	if wrapper.get("format") != FORMAT or wrapper.get("shop") != shop.id:
		return {"error": "店铺存档格式无效"}
	var version: Variant = wrapper.get("version")
	if (not version is int and not version is float) or not is_finite(float(version)) or float(version) != floor(float(version)):
		return {"error": "店铺存档版本无效"}
	if version > VERSION:
		return {"error": "存档版本高于当前程序，已停止写入以保留原文件", "future": true}
	if version != VERSION: return {"error": "店铺存档版本不受支持"}
	var speed := _read_speed(wrapper.get("speed"))
	if not is_finite(speed) or speed <= 0.0: return {"error": "店铺存档播放速度无效"}
	var encoded: Variant = wrapper.get("state")
	if not encoded is String or encoded.is_empty() or encoded.length() % 4 != 0:
		return {"error": "店铺存档状态编码无效"}
	# Strict canonical base64 rejects ignored characters, bad padding and truncation.
	for character in encoded:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=":
			return {"error": "店铺存档状态编码无效"}
	var bytes := Marshalls.base64_to_raw(encoded)
	if Marshalls.raw_to_base64(bytes) != encoded:
		return {"error": "店铺存档状态编码无效"}
	if wrapper.get("state_sha256") != bytes.hex_encode().sha256_text():
		return {"error": "店铺存档状态校验失败"}
	# Godot's own has_encoded_var still logs errors for truncated nested values.
	# Check the shop's data-only types before entering the engine decoder.
	if bytes.size() < 8 or bytes.decode_u32(0) != TYPE_DICTIONARY or _variant_end(bytes, 0) != bytes.size():
		return {"error": "店铺存档二进制状态无效"}
	# bytes_to_var deliberately excludes objects; never use bytes_to_var_with_objects.
	var state: Variant = bytes_to_var(bytes)
	if not state is Dictionary: return {"error": "店铺存档状态必须是字典"}
	var guides: Array = []
	var raw_guides: Variant = wrapper.get("guides", [])
	if raw_guides is Array:
		for id in raw_guides:
			if id is String: guides.append(id)
	return {"state": state, "speed": speed, "guides": guides}


func _read_speed(value: Variant) -> float:
	if value is float or value is int: return float(value)
	# 浮点数按 SaveUtil 的 "f64:十六进制" 编码；先查格式再解码
	if not value is String or not value.begins_with("f64:") or value.length() != 20: return NAN
	var hex: String = value.substr(4)
	for character in hex:
		if not character in "0123456789abcdefABCDEF": return NAN
	return hex.hex_decode().decode_double(0)


## Bounds-check Godot's Variant encoding for the value types used in shop state.
## Object, Callable, RID, typed-object containers and unknown encodings are rejected.
func _variant_end(bytes: PackedByteArray, offset: int, depth: int = 0) -> int:
	if depth > 64 or offset < 0 or offset > bytes.size() - 4: return -1
	var header := bytes.decode_u32(offset)
	var type := header & 0xffff
	var flags := header >> 16
	offset += 4
	var length := 0
	match type:
		TYPE_NIL:
			if flags != 0: return -1
			return offset
		TYPE_BOOL:
			if flags != 0 or offset > bytes.size() - 4 or bytes.decode_u32(offset) > 1: return -1
			return offset + 4
		TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2:
			if flags > 1: return -1
			length = (8 if flags == 1 else 4) * (2 if type == TYPE_VECTOR2 else 1)
		TYPE_VECTOR2I:
			if flags != 0: return -1
			length = 8
		TYPE_STRING, TYPE_STRING_NAME:
			if flags != 0 or offset > bytes.size() - 4: return -1
			length = bytes.decode_u32(offset)
			offset += 4
			if length > bytes.size() - offset or not _valid_utf8(bytes, offset, length): return -1
			length = (length + 3) & ~3
		TYPE_ARRAY, TYPE_DICTIONARY:
			if flags != 0 or offset > bytes.size() - 4: return -1
			var count := (bytes.decode_u32(offset) & 0x7fffffff) * (2 if type == TYPE_DICTIONARY else 1)
			offset += 4
			if count > (bytes.size() - offset) / 4: return -1
			for index in count:
				offset = _variant_end(bytes, offset, depth + 1)
				if offset < 0: return -1
			return offset
		TYPE_PACKED_VECTOR2_ARRAY:
			if flags > 1 or offset > bytes.size() - 4: return -1
			length = bytes.decode_u32(offset) * (16 if flags == 1 else 8)
			offset += 4
		_:
			return -1
	return offset + length if length <= bytes.size() - offset else -1


func _valid_utf8(bytes: PackedByteArray, offset: int, length: int) -> bool:
	var end := offset + length
	while offset < end:
		var first := bytes[offset]
		offset += 1
		if first <= 0x7f: continue
		var remaining := 1 if first >= 0xc2 and first <= 0xdf else (2 if first >= 0xe0 and first <= 0xef else (3 if first >= 0xf0 and first <= 0xf4 else -1))
		if remaining < 0 or remaining > end - offset: return false
		var second := bytes[offset]
		if (first == 0xe0 and second < 0xa0) or (first == 0xed and second >= 0xa0) or (first == 0xf0 and second < 0x90) or (first == 0xf4 and second >= 0x90): return false
		for index in remaining:
			if bytes[offset] < 0x80 or bytes[offset] > 0xbf: return false
			offset += 1
	return true


func _backup_corrupt() -> Error:
	if not FileAccess.file_exists(path): return OK
	var backup := "%s.corrupt-%d-%d" % [path, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var suffix := 0
	while FileAccess.file_exists(backup):
		suffix += 1
		backup = "%s.corrupt-%d-%d-%d" % [path, int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), suffix]
	var error := DirAccess.rename_absolute(path, backup)
	if error != OK:
		last_error += "；原文件备份失败：%s" % error_string(error)
	return error
