extends Node
## Play the platform's intro video and its embedded soundtrack together.

signal started
signal finished
signal failed

const NATIVE_VIDEO := "res://art/opening/intro.ogv"
var _player: VideoStreamPlayer
var _bridge: JavaScriptObject
var _callback: JavaScriptObject
var _playing := false
var _announced := false
var _last_position := -1.0
var _waiting := 0.0


func play(frame: Control, audio_enabled: bool) -> void:
	stop()
	_playing = true
	_announced = false
	_waiting = 0.0
	_last_position = -1.0
	if OS.has_feature("web"):
		_bridge = JavaScriptBridge.get_interface("EatventureOpening")
		if _bridge == null:
			failed.emit()
			return
		_callback = JavaScriptBridge.create_callback(_web_event)
		_bridge.start(_callback, audio_enabled)
		return
	if not ResourceLoader.exists(NATIVE_VIDEO):
		failed.emit()
		return
	_player = VideoStreamPlayer.new()
	_player.name = "IntroVideo"
	_player.expand = true
	_player.size = frame.size
	_player.stream = load(NATIVE_VIDEO)
	_player.volume = 1.0 if audio_enabled else 0.0
	_player.loop = false
	_player.hide()
	_player.finished.connect(func() -> void: finished.emit())
	frame.add_child(_player)
	_player.play()
	set_process(true)


func _process(delta: float) -> void:
	if not _playing or _player == null: return
	var position := _player.stream_position
	if position > _last_position:
		_waiting = 0.0
		_last_position = position
	else:
		_waiting += delta
	if not _announced and position > 0.0:
		_announced = true
		_player.show()
		started.emit()
	if _waiting > 12.0:
		set_process(false)
		failed.emit()


func _web_event(arguments: Array) -> void:
	if not _playing or arguments.is_empty(): return
	match str(arguments[0]):
		"started": started.emit()
		"finished": finished.emit()
		"failed": failed.emit()


func stop() -> void:
	_playing = false
	set_process(false)
	if _bridge != null:
		_bridge.stop()
	_bridge = null
	_callback = null
	if is_instance_valid(_player):
		_player.stop()
		_player.queue_free()
	_player = null


func _exit_tree() -> void:
	stop()
