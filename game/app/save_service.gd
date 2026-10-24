class_name SaveService
extends RefCounted
## JSON 存档：先写临时文件再替换。文件带 schema_version，读取时逐级迁移。

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://save.json"

var path := DEFAULT_PATH


func _init(path_: String = DEFAULT_PATH) -> void:
	path = path_


func save(data: Dictionary) -> Error:
	var payload: Dictionary = SaveUtil.encode_floats(data)
	payload.schema_version = SCHEMA_VERSION
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	# 不排序键：字典的插入顺序也是状态的一部分（决定先推哪件物料）
	file.store_string(JSON.stringify(payload, "\t", false))
	file.close()
	return DirAccess.rename_absolute(tmp, path)


## 没有存档或读不了时返回空字典
func load_data() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("存档无法解析：%s" % path)
		return {}
	return migrate(SaveUtil.decode_floats(parsed))


func delete() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 逐级迁移到当前版本。以后改存档结构时在这里加一级。
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 1))
	# while version < SCHEMA_VERSION:
	# 	match version:
	# 		1: data = _migrate_1_to_2(data)
	# 	version += 1
	data.schema_version = version
	return data
