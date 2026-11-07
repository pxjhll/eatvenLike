class_name SaveService
extends RefCounted
## JSON 文件写入：先写临时文件再替换，写到一半断电也不会留下半个存档。浮点数按位编码（SaveUtil），读回来一模一样。
## 存档格式和版本由调用者（ShopSave、Profile）自己管，这里不做迁移：格式变了旧档就作废（规格 §3.12）。

var path := ""


func _init(path_: String) -> void:
	path = path_


func save(data: Dictionary) -> Error:
	var payload: Dictionary = SaveUtil.encode_floats(data)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	# 不排序键：字典的插入顺序也是状态的一部分
	file.store_string(JSON.stringify(payload, "\t", false))
	file.close()
	return DirAccess.rename_absolute(tmp, path)
