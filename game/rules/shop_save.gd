class_name ShopSave
extends RefCounted
## 通用店内存档（规格 §3.12）：文件名由 SpecShop.save_file 指定，留空时用 user://shop_<店铺 id>.json。
## 存 ShopRules 的整店状态；店铺流程不兼容时可以更换文件名，旧档保留原样。
## 跨店的东西（开到第几家、结店纪录、永久加成）在 Profile 里，不在这里。
## Version 2 adds content fingerprints; valid legacy version 1 refreshes current numeric definitions.

const FORMAT := "shop_rules"
const VERSION := 2
const ContentContract := preload("res://game/rules/shop_content_contract.gd")

var shop: SpecShop
var path: String
var loaded_speed := 1.0
## 看过的引导步骤 id（和店内状态并排存，不进规则层）
var loaded_guides: Array = []
var last_error := ""
var _write_blocked := false
var load_error: Error = OK
## 店铺内容指纹只算一次：每次自动存档都重算整份数据很慢
var _content_cache: Dictionary = {}


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
	last_error = ""
	# Finish cleanup runs after the profile commit. Retain unsafe replacements
	# without making that committed transition retryable.
	var existing := _assess_existing()
	if existing.get("missing", false): return
	if not existing.get("error", "").is_empty():
		last_error = "旧店存档保留未清：" + existing.error
		return
	var error := DirAccess.remove_absolute(path)
	if error != OK: last_error = "旧店存档清除失败：%s" % error_string(error)


## Callers must check load_error before adopting the returned candidate.
func load_game() -> ShopRules:
	last_error = ""
	load_error = OK
	# Only an explicit load/retry clears the failed-quarantine seal.
	_write_blocked = false
	loaded_speed = 1.0
	loaded_guides = []
	var result := _assess_existing()
	if result.get("missing", false): return ShopRules.new(shop)
	if not result.get("error", "").is_empty():
		last_error = result.error
		if result.get("protected", false): load_error = ERR_UNAVAILABLE
		else:
			load_error = _backup_corrupt()
			if load_error != OK: _write_blocked = true
		return ShopRules.new(shop)
	loaded_speed = result.speed
	loaded_guides = result.guides
	return result.rules


func save_game(rules: ShopRules, speed := 1.0, guides: Array = []) -> Error:
	last_error = ""
	if rules == null or rules.shop == null or rules.shop.id != shop.id or not is_finite(speed) or speed <= 0.0:
		last_error = "存档失败：店铺状态或播放速度无效"
		return ERR_INVALID_PARAMETER
	var content := _content()
	if rules.shop != shop and ContentContract.describe(rules.shop) != content:
		last_error = "存档失败：店铺内容和存档不是同一版本，请重新进店"
		return ERR_INVALID_PARAMETER
	var state := rules.to_dict()
	var state_error := ShopRules.new(shop).load_dict(state)
	if not state_error.is_empty():
		last_error = "存档失败：店铺状态无效：" + state_error
		return ERR_INVALID_DATA
	if _write_blocked:
		last_error = "坏存档留底失败，已停止写入；请检查空间或权限后重试"
		return ERR_UNAVAILABLE
	# Every write, including fresh intent, assesses the file currently on disk.
	var existing := _assess_existing()
	if not existing.get("error", "").is_empty():
		last_error = existing.error
		if existing.get("protected", false): return ERR_UNAVAILABLE
		var quarantine_error := _backup_corrupt()
		if quarantine_error != OK:
			_write_blocked = true
			return quarantine_error
	elif existing.get("refresh", false):
		var backup_error := _backup_before_content_update()
		if backup_error != OK:
			last_error = "旧版本存档备份失败：%s" % error_string(backup_error)
			return backup_error
	var bytes := var_to_bytes(state)
	var payload := {"format": FORMAT, "version": VERSION, "shop": shop.id, "content": content, "speed": speed,
		"state": Marshalls.raw_to_base64(bytes), "state_sha256": bytes.hex_encode().sha256_text()}
	if not guides.is_empty(): payload.guides = guides.map(func(id: Variant) -> String: return str(id))
	var error := SaveService.new(path).save(payload)
	if error != OK:
		last_error = "存档写入失败：%s" % error_string(error)
		return error
	last_error = ""
	return OK


func _assess_existing() -> Dictionary:
	var result := _read_existing()
	if result.get("missing", false) or not result.get("error", "").is_empty(): return result
	var candidate := ShopRules.new(shop)
	# 内容改版（数值或结构）后先按当前内容校验并迁移：已删掉的机器/升级轨丢掉，其余进度保留。
	# 校验不过才当坏档留底、这家店从空店开始；不能因为更新卡在重试界面。
	var error := _id_map_error(result.state) if result.refresh else ""
	if error.is_empty(): error = candidate.load_dict(result.state, result.refresh)
	if not error.is_empty():
		var reason := "店铺内容已更新，旧存档无法沿用" if result.refresh else "店铺存档状态无效"
		return {"error": "%s（%s），原档已留底，这家店从空店开始" % [reason, error]}
	result.rules = candidate
	return result


## 旧档的按 id 存的表必须是字典、键是字符串；已删掉的 id 允许（迁移时丢掉）。
func _id_map_error(state: Dictionary) -> String:
	for key in ShopRules.BY_DATA_ID:
		var recorded: Variant = state.get(key)
		if not recorded is Dictionary: return "%s 格式无效" % key
		for id in recorded:
			if not id is String and not id is StringName: return "%s 里有无效 id" % key
	return ""


func _backup_before_content_update() -> Error:
	# Copy, never move: an unsuccessful migration must leave the original live.
	var backup := "%s.pre-content-%d-%d" % [path, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var suffix := 0
	while FileAccess.file_exists(backup):
		suffix += 1
		backup += "-%d" % suffix
	var error := DirAccess.copy_absolute(path, backup)
	if error != OK: return error
	# Verify the durable copy before authorizing replacement.
	if FileAccess.get_file_as_bytes(path) != FileAccess.get_file_as_bytes(backup): return ERR_FILE_CORRUPT
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
	if wrapper.get("format") != FORMAT:
		return {"error": "店铺存档格式无效"}
	var saved_shop: Variant = wrapper.get("shop")
	if not saved_shop is String or saved_shop.is_empty(): return {"error": "店铺存档的店铺 id 无效"}
	if saved_shop != shop.id:
		return {"error": "这个存档属于另一家店，原档已留底，这家店从空店开始"}
	var version: Variant = wrapper.get("version")
	if (not version is int and not version is float) or not is_finite(float(version)) or float(version) != floor(float(version)):
		return {"error": "店铺存档版本无效"}
	if version > VERSION:
		return {"error": "存档版本高于当前程序，已停止写入以保留原文件", "protected": true}
	if version != 1 and version != VERSION: return {"error": "店铺存档版本不受支持"}
	var refresh: bool = version == 1
	if version == VERSION:
		var content: Variant = wrapper.get("content")
		if not content is Dictionary: return {"error": "店铺存档缺少内容版本"}
		var content_version: Variant = content.get("version")
		if not (content_version is int or content_version is float) or not is_finite(float(content_version)) or float(content_version) != floor(float(content_version)):
			return {"error": "店铺存档内容版本无效"}
		if content_version > 1: return {"error": "存档内容版本高于当前程序，已停止写入以保留原文件", "protected": true}
		if content_version != 1 or not _valid_hash(content.get("gameplay")) or not _valid_hash(content.get("structure")):
			return {"error": "店铺存档内容版本标记无效"}
		var current := _content()
		# 结构变了（布局、等级数、工序）和数值变了一样走迁移；迁移前会先复制原档留底。
		refresh = content.gameplay != current.gameplay or content.structure != current.structure
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
	return {"state": state, "speed": speed, "guides": guides, "refresh": refresh}


func _content() -> Dictionary:
	if _content_cache.is_empty(): _content_cache = ContentContract.describe(shop)
	return _content_cache


func _valid_hash(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true


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
		_write_blocked = true
		last_error += "；原文件备份失败：%s" % error_string(error)
	return error
