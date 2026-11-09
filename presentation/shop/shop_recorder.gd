extends RefCounted
## 试玩记录（通用）：每 60 秒店内时间一行 JSON（金币、杯数、走掉的客人、排队、人手、调参、等级），每次购买和调参也记一行，
## 追加到 user://playlog.txt，方便把一局复制出来分析。和店内存档分开。

const Numbers := preload("res://game/rules/rule_numbers.gd")
const FILE := "user://playlog.txt"
## Tests point this elsewhere so they never touch a real playtest log.
var file_path := FILE
const SAMPLE_SECONDS := 60.0

var view: ShopView
var enabled := true
var _clock := 0.0
var _acc := {}
var _last_revenue := 0.0
var _last_sold := 0
var _last_lost := 0
var _session := ""


func setup(source: RefCounted) -> void:
	view = source if source is ShopView else ShopView.new(source)
	_clock = 0.0
	var activity := view.activity_snapshot()
	_last_revenue = activity.revenue
	_last_sold = activity.sold
	_last_lost = activity.lost
	_session = Time.get_datetime_string_from_system()
	_reset_acc()
	write({"session": _session, "t": int(activity.clock), "stage": activity.stage_index, "gold": activity.gold, "tune": _tune()})


## Called every frame with the shop time that just passed.
func tick(shop_seconds: float) -> void:
	if not enabled or shop_seconds <= 0: return
	_clock += shop_seconds
	_acc.n += shop_seconds
	var activity := view.activity_snapshot()
	var waiting: int = activity.queue
	if waiting >= activity.queue_capacity: _acc.full += shop_seconds
	_acc.angry += shop_seconds * activity.angry_count / maxf(1.0, waiting)
	_acc.idle += shop_seconds * activity.idle_count / maxf(1.0, activity.staff_count)
	for id in activity.machine_working:
		if activity.machine_working[id]: _acc.busy[id] = float(_acc.busy.get(id, 0.0)) + shop_seconds
	var seat_count: int = activity.seat_count
	if seat_count > 0: _acc.seats += shop_seconds * activity.seats_used / float(seat_count)
	if _clock >= SAMPLE_SECONDS:
		_clock -= SAMPLE_SECONDS
		sample()


func sample() -> void:
	var activity := view.activity_snapshot()
	var progress := view.progress_snapshot()
	var n: float = maxf(0.001, _acc.n)
	write({"t": _t(), "stage": activity.stage_index, "gold": activity.gold, "income": activity.revenue - _last_revenue,
		"cups": activity.sold - _last_sold, "lost": activity.lost - _last_lost, "queue": activity.queue, "cap": activity.queue_capacity,
		"full": snappedf(_acc.full / n, 0.01), "angry": snappedf(_acc.angry / n, 0.01), "idle": snappedf(_acc.idle / n, 0.01),
		"busy": _busy(n), "seats_used": snappedf(_acc.seats / n, 0.01),
		"staff": activity.staff_count, "seats": activity.seat_count, "interval": snappedf(activity.customer_interval, 0.1),
		"levels": progress.levels, "tune": _tune()})
	_last_revenue = activity.revenue
	_last_sold = activity.sold
	_last_lost = activity.lost
	_reset_acc()


func log_buy(what: String, gold_before: float) -> void:
	var activity := view.activity_snapshot()
	write({"t": _t(), "buy": what, "cost": gold_before - activity.gold, "stage": activity.stage_index, "gold": activity.gold})


func log_tune(key: String, value: float) -> void:
	write({"t": _t(), "set": key, "to": value})


func write(entry: Dictionary) -> void:
	if not enabled: return
	var file := FileAccess.open(file_path, FileAccess.READ_WRITE if FileAccess.file_exists(file_path) else FileAccess.WRITE)
	if file == null: return
	file.seek_end()
	file.store_line(JSON.stringify(entry))


func text() -> String:
	if not enabled: return ""
	if not FileAccess.file_exists(file_path): return ""
	return FileAccess.get_file_as_string(file_path)


func line_count() -> int:
	var content := text()
	return 0 if content.is_empty() else content.count("\n")


func clear() -> void:
	if not enabled: return
	if FileAccess.file_exists(file_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	setup(view)


## Saves a copy the player can find and send: a download in the web build, the Downloads folder
## (opened afterwards) on desktop, otherwise the documents folder or the game's own data folder.
func export_file() -> String:
	if not enabled: return "还没有录制内容"
	var content := text()
	if content.is_empty(): return "还没有录制内容"
	var name := "eatvenlike-playlog-%s.txt" % Time.get_datetime_string_from_system().replace(":", "-")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(content.to_utf8_buffer(), name, "text/plain")
		return "已导出 " + name
	for dir in [OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP), OS.get_user_data_dir()]:
		if dir.is_empty() or not DirAccess.dir_exists_absolute(dir): continue
		var target: String = dir.path_join(name)
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null: continue
		file.store_string(content)
		file.close()
		if OS.has_feature("pc"): OS.shell_show_in_file_manager(target)
		return "已导出到 " + target
	return "导出失败，文件在 " + path()


func path() -> String:
	return ProjectSettings.globalize_path(file_path)


func _t() -> int:
	return int(view.activity_snapshot().clock)


## Only the knobs moved away from 1.0, so a line stays short.
func _tune() -> Dictionary:
	var result := {}
	var tune: Dictionary = view.progress_snapshot().tune
	for key in tune:
		var value := Numbers.tuned(tune, key)
		if not is_equal_approx(value, 1.0): result[key] = value
	return result


func _busy(n: float) -> Dictionary:
	var result := {}
	for id in _acc.busy: result[id] = snappedf(_acc.busy[id] / n, 0.01)
	return result


func _reset_acc() -> void:
	_acc = {"n": 0.0, "full": 0.0, "angry": 0.0, "idle": 0.0, "busy": {}, "seats": 0.0}
