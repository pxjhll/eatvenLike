extends Sprite2D
## Idle always displays cell zero. Set the work start to one for a separate empty surface.
@export var machine: String
@export var work_phase: String
@export_range(0, 1) var first_work_frame := 0
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
	var elapsed_frames := floori((clock - _started_at) * frames_per_second)
	frame = first_work_frame + elapsed_frames % (hframes - first_work_frame)
