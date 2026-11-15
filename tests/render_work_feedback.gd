extends SceneTree
## Visual feedback follows explicit protocol facts, not task ownership.
var failures := 0
var checks := 0
var errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ",label)

func _run() -> void:
	var actor: Node2D = load("res://presentation/shop/shop_actor.gd").new()
	actor.work_progress = func(row: Dictionary) -> float: return row.display_progress
	actor.work_direction = func(_station: String) -> int: return 3
	actor.setup("rabbit",load("res://art/ui/graybox_font.ttf"))
	root.add_child(actor)
	var row := {"pos":Vector2(200,300),"walking":false,"phase":"pickup","presentation_version":1,"work_station":"supply","display_working":true,"display_progress":-1.0,"carry_item":"","carry_count":0}
	actor.display(row,1.0)
	_check(actor.frame_actor.action=="work","pickup uses actual work animation")
	_check(actor.frame_actor.direction==3,"pickup faces the declared work station")
	_check(not actor.progress_bar.visible,"brief logistics do not flash a progress bar")
	actor.display(row,1.1)
	var phase: float = actor.frame_actor.get_phase()
	row.phase = "dropoff"
	actor.display(row,1.2)
	_check(actor.frame_actor.action=="work" and actor.frame_actor.get_phase()>phase,"consecutive pickup/dropoff preserve the work animation cycle")
	row.display_progress = 0.35
	actor.display(row,1.3)
	_check(actor.progress_bar.visible and is_equal_approx(actor.progress_bar.value,0.35),"real long work progress stays visible")
	row.display_working = false
	row.display_progress = -1.0
	actor.display(row,1.4)
	_check(actor.frame_actor.action=="idle","blocked handoff does not pretend to perform work")
	_check(is_zero_approx(actor.body.rotation),"blocked handoff has no work wobble")
	actor.set_render_position(row.pos+Vector2(8,5))
	_check(actor.carried.get_parent()==actor.frame_actor.get_parent() and actor.task.get_parent()==actor.frame_actor.get_parent() and actor.progress_bar.get_parent()==actor.frame_actor.get_parent(),"hands and overhead feedback share the actor visual layer")
	actor.free()
	await process_frame
	for error in errors.take(): _check(false,error)
	OS.remove_logger(errors)
	print("WORK FEEDBACK: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
