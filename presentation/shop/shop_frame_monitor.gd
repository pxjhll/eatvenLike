extends Label
## Wall-clock intervals between frames include work outside ShopPlay._process.
## The three CPU timings cover rules, the view snapshot, and scene updates.

const USEC_PER_SECOND := 1_000_000
const SLOW_FRAME_USEC := 33_000

var _last_frame_us := -1
var _second_frames := 0
var _second_us := 0
var _second_peak_us := 0
var _frames := 0
var _total_us := 0
var _peak_us := 0
var _slow_frames := 0
var _cpu_total := Vector3.ZERO
var _cpu_peak := Vector3i.ZERO
var _staff_peak := 0
var _customers_peak := 0
var _save_count := 0
var _save_peak_us := 0


func record_frame(start_us: int, cpu_us: Vector3i, staff: int, customers: int) -> void:
	var previous := _last_frame_us
	_last_frame_us = start_us
	if previous < 0 or start_us <= previous: return
	var elapsed := start_us - previous
	_frames += 1
	_total_us += elapsed
	_peak_us = maxi(_peak_us, elapsed)
	if elapsed > SLOW_FRAME_USEC: _slow_frames += 1
	_cpu_total += Vector3(cpu_us)
	_cpu_peak = _cpu_peak.max(cpu_us)
	_staff_peak = maxi(_staff_peak, staff)
	_customers_peak = maxi(_customers_peak, customers)
	_second_frames += 1
	_second_us += elapsed
	_second_peak_us = maxi(_second_peak_us, elapsed)
	if _second_us >= USEC_PER_SECOND:
		var fps := roundi(float(_second_frames) * USEC_PER_SECOND / _second_us)
		text = "%d FPS · %.1f ms max" % [fps, _second_peak_us / 1000.0]
		_reset_display_interval()


func record_save(elapsed_us: int) -> void:
	_save_count += 1
	_save_peak_us = maxi(_save_peak_us, elapsed_us)


## A manual marker reads this window. Only a periodic sample consumes it.
func snapshot(consume := false) -> Dictionary:
	if _frames == 0: return {}
	var result := {
		"frames": _frames, "fps_avg": snappedf(float(_frames) * USEC_PER_SECOND / _total_us, 0.01),
		"frame_max_ms": _ms(_peak_us), "frames_over_33ms": _slow_frames,
		"logic_avg_ms": _ms(float(_cpu_total.x) / _frames), "logic_max_ms": _ms(_cpu_peak.x),
		"snapshot_avg_ms": _ms(float(_cpu_total.y) / _frames), "snapshot_max_ms": _ms(_cpu_peak.y),
		"scene_avg_ms": _ms(float(_cpu_total.z) / _frames), "scene_max_ms": _ms(_cpu_peak.z),
		"staff_peak": _staff_peak, "customers_peak": _customers_peak,
		"canvas_draw_calls": get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"save_count": _save_count, "save_max_ms": _ms(_save_peak_us),
	}
	if consume: _reset_sample()
	return result


func break_frame_chain() -> void:
	_last_frame_us = -1
	_reset_display_interval()


func reset() -> void:
	break_frame_chain()
	_reset_sample()
	text = "FPS …"


func _reset_display_interval() -> void:
	_second_frames = 0
	_second_us = 0
	_second_peak_us = 0


func _reset_sample() -> void:
	_frames = 0
	_total_us = 0
	_peak_us = 0
	_slow_frames = 0
	_cpu_total = Vector3.ZERO
	_cpu_peak = Vector3i.ZERO
	_staff_peak = 0
	_customers_peak = 0
	_save_count = 0
	_save_peak_us = 0


static func _ms(usec: float) -> float:
	return snappedf(usec / 1000.0, 0.01)
