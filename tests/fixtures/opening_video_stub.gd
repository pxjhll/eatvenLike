extends Node

signal started
signal finished
signal failed
var plays := 0
var stops := 0

func play(_frame: Control) -> void:
	plays += 1
	started.emit()

func stop() -> void:
	stops += 1
