extends "res://tests/test_case.gd"
const Compiler := preload("res://game/rules/template/compiler.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Production := preload("res://tests/fixtures/template_shop.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")

func _template(joined := false) -> Resource:
	var template := Production.definition() if joined else Production.linear()
	template.places["prep"] = {"port":Vector2(160,100),"capacity":0}
	template.places["finish"] = {"port":Vector2(240,100),"capacity":0}
	template.machines.a.profile.load_seconds = 0.5
	template.machines.a.profile.unload_seconds = 0.4
	template.machines.a["stage_ports"] = {"load":"prep","operate":"a_out","unload":"finish"}
	template.dispatch = {"hold_machine":true,"affinity":"exclusive"}
	return template

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(Actors.owner(),template)
	check_eq(runtime.last_error,"","stage locations compile through the common runtime")
	return runtime if runtime.last_error.is_empty() else null

func test_one_reserved_device_moves_between_stage_ports_in_two_recipe_combinations() -> void:
	for joined in [false,true]:
		var runtime := _runtime(_template(joined))
		if runtime == null: return
		var request: Dictionary = runtime.request_production("meal" if joined else "drink")
		var seen := {}
		var operator := -1
		for tick in 800:
			check_eq(runtime.step(0.1),"","shared stage advancement")
			for run in runtime.runner.machines.snapshot().runs:
				if run.machine != "a" or run.phase not in ["load","operate","unload"]: continue
				seen[run.phase] = true
				if operator < 0: operator = run.operator
				check_eq(run.operator,operator,"same machine lease retains the real employee")
				var worker: Dictionary = runtime.runner.owner.worker_by_id(run.operator)
				check_eq(worker.pos,runtime.runner.ports[runtime.runner.machines.stage_port(run.id)],"employee really reaches each declared stage location")
			if runtime.ready(request.id): break
		check(runtime.ready(request.id),"all stages lead to real output")
		check_eq(seen.size(),3,"loading, processing and unloading all occurred")
		check_eq(runtime.runner.inventory.audit(),[],"locations cannot change quantities")

func test_stage_port_validation_rejects_unknown_inactive_and_private_bindings() -> void:
	for binding in [{"load":"missing"},{"teleport":"prep"},{"load":7},{"stir":"prep"}]:
		var template := _template()
		template.machines.a.stage_ports = binding
		check(not Compiler.compile(template).errors.is_empty(),"bad stage binding must fail before runtime: "+str(binding))
	var wrong := _template()
	wrong.machines.a.stage_ports = []
	check(not Compiler.compile(wrong).errors.is_empty(),"non-dictionary binding fails closed")

func test_stage_ports_resume_after_recall_without_reloading_or_losing_work() -> void:
	var template := _template()
	var runtime := _runtime(template)
	if runtime == null: return
	var request: Dictionary = runtime.request_production("drink")
	for tick in 500:
		check_eq(runtime.step(0.1),"","reach processing after loading at another port")
		var runs: Array = runtime.runner.machines.snapshot().runs
		if not runs.is_empty() and runs[0].phase == "operate": break
	var run: Dictionary = runtime.runner.machines.snapshot().runs[0]
	check_eq(run.phase,"operate","real processing checkpoint exists")
	check_eq(runtime.runner.cancel(run.operator),"","recall releases employee but keeps the reserved device")
	var saved: Dictionary = runtime.snapshot()
	var reopened := _runtime(template)
	if reopened == null: return
	check_eq(reopened.restore(saved),"","restore ports and original completed loading")
	for tick in 600:
		check_eq(runtime.step(0.1),"","continue recalled machine")
		check_eq(reopened.step(0.1),"","continue restored machine")
		if runtime.ready(request.id): break
	check(runtime.ready(request.id),"recalled machine finishes")
	check_eq(reopened.snapshot(),runtime.snapshot(),"stage port and remaining work replay identically")

func test_wrong_stage_port_is_rejected_by_direct_requests_and_restore() -> void:
	var runtime := _runtime(_template())
	if runtime == null: return
	runtime.request_production("drink")
	for tick in 500:
		check_eq(runtime.step(0.1),"","reach loading")
		var runs: Array = runtime.runner.machines.snapshot().runs
		if not runs.is_empty() and runs[0].phase == "load": break
	var run: Dictionary = runtime.runner.machines.snapshot().runs[0]
	check_eq(runtime.runner.cancel(run.operator),"","release operator for direct request")
	var worker: Dictionary = runtime.runner.owner.workers[0]
	check(not runtime.runner.operate(worker.id,run.id,"a_in").is_empty(),"input container cannot substitute the declared loading location")
	check_eq(runtime.runner.operate(worker.id,run.id,"prep"),"","correct stage location remains executable")
	var saved: Dictionary = runtime.snapshot()
	saved.runner.tasks[0].from = "a_in"
	saved.runner.tasks[0].to = "a_in"
	var fresh := _runtime(_template())
	if fresh == null: return
	var before: Dictionary = fresh.snapshot()
	check(not fresh.restore(saved).is_empty(),"forged port cannot be adopted")
	check_eq(fresh.snapshot(),before,"failed restore preserves live actors and stocks")

func test_empty_stage_ports_preserve_previous_compilation_and_snapshots() -> void:
	var template := Production.linear()
	var before: Dictionary = Compiler.compile(template)
	template.machines.a["stage_ports"] = {}
	check_eq(Compiler.compile(template),before,"optional empty binding must leave historical signatures unchanged")

func test_fixed_preparation_uses_target_tuning_and_employee_rate_but_skips_machine_upgrade() -> void:
	var template := _template()
	template.machines.a["stage_timing"] = {"load":{"target":"a","fixed":true}}
	var owner := Actors.owner()
	owner.tune.a = 2.0
	owner.apply_effect("event","duration",SpecEffect.make("duration","set",0.25,"a"))
	owner.apply_effect("event","work",SpecEffect.make("work","set",2.0))
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","explicit preparation timing compiles")
	if not runtime.last_error.is_empty(): return
	runtime.request_production("drink")
	for tick in 500:
		check_eq(runtime.step(0.05),"","reach tuned real loading")
		for run in runtime.runner.machines.snapshot().runs:
			if run.phase != "load": continue
			check_eq(run.stage_total,1.0,"0.5 seconds times target tuning 2, unaffected by machine duration 0.25")
			check_eq(run.operator_rate,2.0,"employee work rate applies once")
			return
	check(false,"actual timed loading happened")

func test_stage_timing_rejects_unknown_parameters_and_inactive_stages() -> void:
	for binding in [{"load":{"target":"","fixed":true}},{"operate":{"target":"a","fixed":true}},{"stir":{"target":"a","fixed":true}},{"load":{"target":"a","fixed":1}},{"load":{"target":"a","callback":"custom"}}]:
		var template := _template()
		template.machines.a["stage_timing"] = binding
		check(not Compiler.compile(template).errors.is_empty(),"bad preparation timing fails closed")

func test_two_orders_cannot_share_a_device_between_loading_and_processing() -> void:
	var runtime := _runtime(_template())
	if runtime == null: return
	var first: Dictionary = runtime.request_production("drink")
	var second: Dictionary = runtime.request_production("drink")
	for tick in 1000:
		check_eq(runtime.step(0.1),"","two employees compete for the continuous device")
		check(runtime.runner.machines.occupied_slots("a") <= 1,"loading and walking to another stage retain the same physical occupancy")
		if runtime.ready(first.id) and runtime.ready(second.id): break
	check(runtime.ready(first.id) and runtime.ready(second.id),"both orders eventually finish through one physical slot")

func test_recalled_timed_stage_restores_committed_time_after_tuning_changes() -> void:
	var template := _template()
	template.machines.a["stage_timing"] = {"load":{"target":"a","fixed":true}}
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.tune.a = 2.0
	var request: Dictionary = runtime.request_production("drink")
	var run: Dictionary = {}
	for tick in 500:
		check_eq(runtime.step(0.1),"","reach tuned manual stage")
		for current in runtime.runner.machines.snapshot().runs:
			if current.phase == "load": run = current; break
		if not run.is_empty(): break
	check(not run.is_empty(),"load acquired real committed clock")
	if run.is_empty(): return
	check_eq(runtime.runner.cancel(run.operator),"","recall timed loading")
	runtime.runner.owner.tune.a = 0.5
	var saved: Dictionary = runtime.snapshot()
	var reopened := _runtime(template)
	if reopened == null: return
	reopened.runner.owner.tune.a = 0.5
	check_eq(reopened.restore(saved),"","old committed stage duration remains legal under new tuning")
	check_eq(reopened.runner.machines.run(run.id).stage_total,1.0,"resume cannot reset the old 0.5 × 2 clock to the new 0.5 × 0.5")
	for tick in 600:
		check_eq(runtime.step(0.1),"","continue original stage")
		check_eq(reopened.step(0.1),"","continue restored stage")
		if runtime.ready(request.id): break
	check(runtime.ready(request.id),"timed recalled order completes")
	check_eq(reopened.snapshot(),runtime.snapshot(),"committed stage and output replay identically")
