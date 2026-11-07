extends Node
## Owns playback and preferences across shop scene changes. Shop simulations stay audio-agnostic.

const SETTINGS_PATH := "user://shop_audio.cfg"
const EVENT_CUES := preload("res://content/audio/shop_cues.tres")
const CUES := {
	&"tap": ["res://art/audio/tap.wav", -23.0],
	&"sale": ["res://art/audio/sale.wav", -19.0],
	&"upgrade": ["res://art/audio/upgrade.wav", -14.0],
	&"unlock": ["res://art/audio/unlock.wav", -13.0],
	&"hire": ["res://art/audio/hire.wav", -15.0],
	&"flyers": ["res://art/audio/flyers.wav", -17.0],
	&"complete": ["res://art/audio/complete.wav", -10.0],
}
const SALE_INTERVAL_MS := 240

var music_enabled := true
var effects_enabled := true
var _music := AudioStreamPlayer.new()
var _players: Dictionary[StringName, AudioStreamPlayer] = {}
var _events: RuleEvents
var _last_sale_ms := -SALE_INTERVAL_MS
# Headless simulations have no audio output and can exit before the mixer drains.
var _can_play := not OS.has_feature("web") and DisplayServer.get_name() != "headless"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		music_enabled = settings.get_value("audio", "music", true) != false
		effects_enabled = settings.get_value("audio", "effects", true) != false
	_music.name = "Music"
	_music.volume_db = -11.0
	add_child(_music)
	for cue in CUES:
		var player := AudioStreamPlayer.new()
		player.name = cue
		player.stream = load(CUES[cue][0])
		player.volume_db = CUES[cue][1]
		add_child(player)
		_players[cue] = player
	set_process_input(OS.has_feature("web"))


func _input(event: InputEvent) -> void:
	unlock_from_input(event)


## Popup releases may be handled before this autoload receives _input.
func unlock_from_input(event: InputEvent) -> void:
	if _can_play or not is_processing_input():
		return
	# WebAudio unlocks on a real gesture. Use release so touch and mouse both qualify.
	var pointer_release: bool = event is InputEventScreenTouch and not event.pressed and not event.canceled
	pointer_release = pointer_release or (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if pointer_release or (event is InputEventKey and event.pressed and not event.echo):
		_can_play = true
		set_process_input(false)
		_apply_music()


func enter_shop(events: RuleEvents, track: AudioStream) -> void:
	if _events != events:
		if _events != null:
			_events.off("*", _on_rule_event)
		_events = events
		if _events != null:
			_events.on("*", _on_rule_event)
		_stop_effects()
		_last_sale_ms = -SALE_INTERVAL_MS
	if _music.stream != track:
		_music.stop()
		_music.stream = track
	_apply_music()


func leave_shop(events: RuleEvents) -> void:
	if _events == events:
		enter_shop(null, null)


func _on_rule_event(event: Dictionary) -> void:
	var cue: StringName = EVENT_CUES.cues.get(event.name, &"")
	if not cue.is_empty():
		play_cue(cue)


func play_cue(cue: StringName) -> void:
	if not _can_play or not effects_enabled or not _players.has(cue):
		return
	if cue == &"sale":
		var now := Time.get_ticks_msec()
		if now - _last_sale_ms < SALE_INTERVAL_MS:
			return
		_last_sale_ms = now
	_players[cue].play()


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	_apply_music()
	_save_settings()


func set_effects_enabled(enabled: bool) -> void:
	effects_enabled = enabled
	if not enabled:
		_stop_effects()
	_save_settings()


func _apply_music() -> void:
	if not music_enabled:
		if _music.playing:
			_music.stream_paused = true
		return
	if _can_play and _music.stream != null:
		if not _music.playing:
			_music.play()
		_music.stream_paused = false


func _stop_effects() -> void:
	for player in _players.values():
		player.stop()


func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("audio", "music", music_enabled)
	settings.set_value("audio", "effects", effects_enabled)
	var error := settings.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save shop audio preferences: %s" % error_string(error))
