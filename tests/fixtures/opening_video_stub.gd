extends Node

signal started
signal finished
signal failed
var plays := 0
var stops := 0
var audio_enabled := false

func play(_frame: Control, audio_enabled_: bool) -> void:
	plays += 1
	audio_enabled = audio_enabled_
	started.emit()

func stop() -> void:
	stops += 1
