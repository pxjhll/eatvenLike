extends RefCounted
## 煎饼摊店内存档 user://pancake_shop.json：店铺进度 + 看过的引导。读不了就从头开始，不覆盖坏文件之外的东西。

const Sim := preload("res://game/pancake/pancake_sim.gd")
const DEFAULT_PATH := "user://pancake_shop.json"
const VERSION := 1

var path := DEFAULT_PATH
var guides: Array = []
var last_error := ""


func _init(path_ := DEFAULT_PATH) -> void:
	path = path_


## 读档到给定的 sim 上；没有存档返回 false。
func load_into(sim: Sim) -> bool:
	last_error = ""
	guides = []
	if not FileAccess.file_exists(path): return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.get("state") is Dictionary:
		last_error = "煎饼摊存档读不了，已从头开始"
		_backup()
		return false
	if int(data.get("version", 0)) > VERSION:
		last_error = "煎饼摊存档版本太新，已从头开始"
		return false
	var error := sim.load_dict(data.state)
	if not error.is_empty():
		last_error = "煎饼摊存档无效：" + error
		_backup()
		sim.reset()
		return false
	var g: Variant = data.get("guides", [])
	if g is Array: guides = g
	return true


func save(sim: Sim, seen_guides: Array) -> Error:
	var payload := {"version": VERSION, "state": sim.to_dict(), "guides": seen_guides}
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return DirAccess.rename_absolute(tmp, path)


func clear() -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)


func _backup() -> void:
	DirAccess.rename_absolute(path, "%s.corrupt-%d" % [path, int(Time.get_unix_time_from_system())])
