extends Logger
## 记下运行期间的脚本错误和引擎错误，让 run_all 把「执行到一半报错」算作失败。

var errors: PackedStringArray = []
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	errors.append("%s（%s:%d %s）" % [rationale if rationale != "" else code, file.get_file(), line, function])
	_mutex.unlock()


func take() -> PackedStringArray:
	_mutex.lock()
	var out := errors
	errors = PackedStringArray()
	_mutex.unlock()
	return out
