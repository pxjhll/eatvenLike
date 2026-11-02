extends RefCounted
## 试玩记录: one JSON line per minute of shop time (money, cups, queue, staff, tuning knobs, levels)
## plus a line for every purchase and knob change, appended to user://playlog.txt so a playtest can
## be copied out and analysed. Kept apart from the shop save.

const FILE := "user://playlog.txt"
## Tests point this elsewhere so they never touch a real playtest log.
var file_path := FILE
const SAMPLE_SECONDS := 60.0

var sim: RefCounted
var enabled := true
var _clock := 0.0
var _acc := {}
var _last_revenue := 0
var _last_sold := 0
var _session := ""


func setup(shop_sim: RefCounted) -> void:
	sim = shop_sim
	_last_revenue = sim.revenue
	_last_sold = sim.sold
	_session = Time.get_datetime_string_from_system()
	_reset_acc()
	write({"session": _session, "t": _t(), "stage": sim.stage_index, "gold": sim.gold, "tune": _tune()})


## Called every frame with the shop time that just passed.
func tick(shop_seconds: float) -> void:
	if not enabled or shop_seconds <= 0: return
	_clock += shop_seconds
	_acc.n += shop_seconds
	var capacity: int = sim._queue_capacity()
	if sim.orders.size() >= capacity: _acc.full += shop_seconds
	var angry := 0
	for order in sim.orders:
		if sim.order_mood(order) == 2: angry += 1
	_acc.angry += shop_seconds * angry / maxf(1.0, sim.orders.size())
	var idle := 0
	for worker in sim.workers:
		if worker.job.is_empty(): idle += 1
	_acc.idle += shop_seconds * idle / maxf(1.0, sim.workers.size())
	if sim.stations.has("boil") and sim.station_unlocked("boil") and sim.stations.boil.processing > 0: _acc.boil += shop_seconds
	if sim.stations.has("seal") and sim.station_unlocked("seal") and sim.stations.seal.processing > 0: _acc.seal += shop_seconds
	if sim.seats > 0: _acc.seats += shop_seconds * sim.diners.size() / float(sim.seats)
	if _clock >= SAMPLE_SECONDS:
		_clock -= SAMPLE_SECONDS
		sample()


func sample() -> void:
	var n: float = maxf(0.001, _acc.n)
	write({"t": _t(), "stage": sim.stage_index, "gold": sim.gold, "income": sim.revenue - _last_revenue,
		"cups": sim.sold - _last_sold, "queue": sim.orders.size(), "cap": sim._queue_capacity(),
		"full": snappedf(_acc.full / n, 0.01), "angry": snappedf(_acc.angry / n, 0.01), "idle": snappedf(_acc.idle / n, 0.01),
		"boil_busy": snappedf(_acc.boil / n, 0.01), "seal_busy": snappedf(_acc.seal / n, 0.01), "seats_used": snappedf(_acc.seats / n, 0.01),
		"staff": sim.workers.size(), "seats": sim.seats, "interval": snappedf(sim._order_interval(), 0.1),
		"levels": sim.station_levels.duplicate(), "tune": _tune()})
	_last_revenue = sim.revenue
	_last_sold = sim.sold
	_reset_acc()


func log_buy(what: String, gold_before: int) -> void:
	write({"t": _t(), "buy": what, "cost": gold_before - sim.gold, "stage": sim.stage_index, "gold": sim.gold})


func log_tune(key: String, value: float) -> void:
	write({"t": _t(), "set": key, "to": value})


func write(entry: Dictionary) -> void:
	if not enabled: return
	var file := FileAccess.open(file_path, FileAccess.READ_WRITE if FileAccess.file_exists(file_path) else FileAccess.WRITE)
	if file == null: return
	file.seek_end()
	file.store_line(JSON.stringify(entry))


func text() -> String:
	if not FileAccess.file_exists(file_path): return ""
	return FileAccess.get_file_as_string(file_path)


func line_count() -> int:
	var content := text()
	return 0 if content.is_empty() else content.count("\n")


func clear() -> void:
	if FileAccess.file_exists(file_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	setup(sim)


## Saves a copy the player can find and send: a download in the web build, the Downloads folder
## (opened afterwards) on desktop, otherwise the documents folder or the game's own data folder.
func export_file() -> String:
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
	return int(sim.elapsed)


## Only the knobs moved away from 1.0, so a line stays short.
func _tune() -> Dictionary:
	var result := {}
	for key in sim.TUNE_KEYS:
		if not is_equal_approx(sim.tuned(key), 1.0): result[key] = sim.tuned(key)
	return result


func _reset_acc() -> void:
	_acc = {"n": 0.0, "full": 0.0, "angry": 0.0, "idle": 0.0, "boil": 0.0, "seal": 0.0, "seats": 0.0}
