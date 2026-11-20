extends Sprite2D
## Cell zero is the idle artwork. The remaining cells loop during the bound machine phase.
@export var machine: String
@export var work_phase: String
@export var frames_per_second := 8.0

var _started_at := -1.0


func show_machine_state(machines: Dictionary, clock: float) -> void:
	var phases: Array = machines.get(machine, {}).get("active_phases", [])
	if work_phase not in phases:
		_started_at = -1.0
		frame = 0
		return
	if _started_at < 0.0 or clock < _started_at:
		_started_at = clock
	frame = 1 + floori((clock - _started_at) * frames_per_second) % (hframes - 1)
