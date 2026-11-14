class_name RuleEvents
extends RefCounted
## 事件总线（规格 §3.13）：规则层把发生的事广播出来；任务、引导、瓶颈提示、存档、奇遇触发器都只听广播。
## 事件名：sale、arrived、lost、unlocked、upgraded、hired、stage、flyer、tick_second、bought、event_started、event_ended …

const LOG_SIZE := 40

var _listeners: Dictionary = {}
## 最近的事件（界面滚动提示用）：{"name", "time", "data"}
var log: Array = []
var clock := 0.0
var _batch_depth := 0
var _pending: Array = []

func begin_batch() -> void:
	_batch_depth += 1

func end_batch() -> void:
	_batch_depth -= 1
	if _batch_depth>0: return
	while not _pending.is_empty():
		var message: Dictionary = _pending.pop_front()
		emit(message.name,message.data)


func on(name: String, listener: Callable) -> void:
	if not _listeners.has(name): _listeners[name] = []
	if not _listeners[name].has(listener): _listeners[name].append(listener)


func clear_history() -> void:
	log.clear()
	clock = 0.0


func off(name: String, listener: Callable) -> void:
	if _listeners.has(name): _listeners[name].erase(listener)


func emit(name: String, data: Dictionary = {}) -> void:
	if _batch_depth>0:
		_pending.append({"name":name,"data":data.duplicate(true)})
		return
	# 计时广播（tick_*）不进日志，免得把真正发生的事挤掉
	if not name.begins_with("tick_"):
		log.append({"name": name, "time": clock, "data": data})
		if log.size() > LOG_SIZE: log.pop_front()
	for listener in _listeners.get(name, []).duplicate():
		if listener.is_valid(): listener.call(data)
	for listener in _listeners.get("*", []).duplicate():
		if listener.is_valid(): listener.call({"name": name, "data": data})
