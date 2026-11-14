extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _view(runtime: RefCounted, displays: Array = []) -> ShopView:
	var view := ShopView.new(runtime.runner.owner)
	check(view.has_method("bind_runtime"),"formal ShopView needs one shared runtime presentation input")
	if not view.has_method("bind_runtime"): return null
	check_eq(view.call("bind_runtime",runtime,displays),"","bind the same owner without starting another simulation")
	return view

func test_reservation_pickup_and_drop_project_actual_stock_and_hands_into_scene_frame() -> void:
	var runtime := Fixture.runtime()
	var view := _view(runtime)
	if view==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	check_eq(runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",2,0.6,-1,1),"","ordinary shared reservation")
	var reserved: Dictionary = view.render_snapshot()
	check_eq(reserved.presentation_version,1,"new display protocol is explicit")
	check_eq(reserved.workers[0].carry_count,0,"planning cannot show hands")
	check_eq(reserved.draws,[],"no loose stock implied by container coordinates")
	for tick in 100:
		check_eq(runtime.runner.step(0.1),"","reach real pickup")
		if worker.carry_count==2: break
	var held: Dictionary = view.render_snapshot()
	check_eq(held.workers[0].held_items,[{"item":"raw_a","count":2}],"hands come from actual inventory lots")
	check_eq(held.workers[0].carry_count,2,"same physical held quantity")
	for tick in 100:
		check_eq(runtime.runner.step(0.1),"","reach actual drop")
		if runtime.runner.idle(worker.id): break
	var dropped: Dictionary = view.render_snapshot()
	check_eq(dropped.stock.a_in.items.raw_a.count,2,"UI reflects delivered inputs")
	check_eq(dropped.workers[0].held_items,[],"drop clears all carried items")
	check_eq(dropped.draws,[],"delivered inputs remain only UI stock")

func test_scene_snapshot_ignores_old_business_ledgers_and_keeps_outer_wallet_and_purchases() -> void:
	var runtime := Fixture.runtime()
	var view := _view(runtime)
	if view==null: return
	var owner: ShopRules = runtime.runner.owner
	owner.clock = 900.0
	owner.shelf_stock = {"lemonade":99}
	owner.stations["a"] = {"phase":"working","progress":0.8,"input":{"wrong":10},"output":{"wrong":20}}
	owner.gold = 123.0
	runtime.runner.inventory.seed("a_out","drink",2)
	check_eq(runtime.step(0.1),"","advance only public runtime")
	var frame: Dictionary = view.render_snapshot()
	check_eq(frame.clock,0.1,"public runtime is the only display clock")
	check_eq(frame.gold,123.0,"wallet retains outer ownership")
	check_eq(frame.stock.a_out.items.drink.count,2,"actual shared stock")
	check(not frame.has("serve") and not frame.has("shelf_stock"),"no repackaging of obsolete business ledgers")
	check_eq(view.machine_status("a").output,2,"machine badge reads common inventory")
	check_eq(view.machine_status("a").working,false,"old machine phase cannot animate public machine")

func test_scene_frame_and_bound_machine_queries_cannot_mutate_state_or_consume_rng() -> void:
	var runtime := Fixture.runtime()
	var view := _view(runtime)
	if view==null: return
	runtime.runner.inventory.seed("a_out","drink",1)
	var before: Dictionary = runtime.snapshot()
	var rng_state: int = runtime.runner.owner.rng.state
	var frame: Dictionary = view.render_snapshot()
	frame.stock.a_out.items.drink.count = 100
	frame.workers[0].pos = Vector2(-100,-100)
	var status := view.machine_status("a")
	status.output = 100
	check_eq(runtime.snapshot(),before,"returned state is detached")
	check_eq(runtime.runner.owner.rng.state,rng_state,"display never chooses menus or moves actors")

func test_explicit_showcase_reaches_scene_draws_and_invalid_rebinding_keeps_previous_view() -> void:
	var runtime := Fixture.runtime()
	runtime.runner.inventory.seed("a_out","drink",1)
	var view := _view(runtime,[{"capability":"stock_showcase","place":"a_out","points":[Vector2(400,200)],"host":"Shelf"}])
	if view==null: return
	check_eq(view.render_snapshot().draws,[{"item":"drink","pos":Vector2(400,200),"host":"Shelf"}],"only an explicit showcase authorizes scene sprites")
	var before: Dictionary = view.render_snapshot()
	check(not String(view.call("bind_runtime",runtime,[{"capability":"stock_showcase","place":"a_out","points":[]}])).is_empty(),"missing display port is rejected")
	check_eq(view.render_snapshot(),before,"invalid presentation configuration cannot partially replace live view")
	check(not String(view.call("bind_runtime",Fixture.runtime())).is_empty(),"another owner's runtime cannot be bound")
	check_eq(view.render_snapshot(),before,"wrong owner cannot change existing view")

func test_customer_poses_come_from_shared_movement_and_preserve_true_carry_counts_and_seating() -> void:
	var runtime := Fixture.runtime("self_pickup")
	var view := _view(runtime)
	if view==null: return
	runtime.arrive(Fixture.request())
	var saw_carry := false
	var saw_seated := false
	for tick in 1500:
		check_eq(runtime.step(0.1),"","shared customer lifecycle")
		var frame: Dictionary = view.render_snapshot()
		var key := "guest:1"
		if not frame.movement.customers.has(key): break
		var row: Dictionary = frame.movement.customers[key]
		check_eq(row.pos,runtime.service.customers.record(1).pos,"no GUI movement integration")
		if row.carry_count>0:
			saw_carry = true
			check_eq(row.carry_count,2,"main plus addon retains actual whole bundle count")
		if row.seated:
			saw_seated = true
			check(runtime.service.customers.ready(1,"seat:dine/0"),"display sits only after true arrival")
			check_eq(row.seat,0,"authored seat suffix, not queue rank")
	check(saw_carry and saw_seated,"both customer carrying and seated dining were actually exercised")
	check_eq(view.render_snapshot().movement.customers,{},"customer disappears only after real exit")

func test_pause_and_renderer_reads_preserve_motion_and_public_clock() -> void:
	var runtime := Fixture.runtime()
	var view := _view(runtime)
	if view==null: return
	runtime.arrive(Fixture.request())
	runtime.step(0.1)
	var before: Dictionary = view.render_snapshot()
	runtime.runner.owner.paused = true
	check_eq(runtime.step(5.0,true),"","pause freezes public simulation")
	var after: Dictionary = view.render_snapshot()
	check_eq(after.clock,before.clock,"no extra view clock")
	check_eq(after.movement,before.movement,"no local customer movement during pause")
	check(after.paused,"display retains explicit outer pause flag")

func test_actual_manual_progress_and_target_station_are_available_without_legacy_jobs() -> void:
	var runtime := Fixture.runtime()
	var view := _view(runtime)
	if view==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	worker.pos = Vector2(200,100)
	var run: Dictionary = runtime.runner.machines.start("a",{}, {"drink":1},2.0)
	runtime.runner.operate(worker.id,run.id,"a_in")
	for tick in 20:
		runtime.runner.step(0.1)
		if runtime.runner.machines.run(run.id).phase=="operate": break
	runtime.runner.step(0.5)
	var pose: Dictionary = view.render_snapshot().workers[0]
	check_eq(pose.work_station,"a","facing uses actual operation machine")
	check(view.work_progress(pose)>0.0 and view.work_progress(pose)<1.0,"public remaining clock drives employee progress")
	check(not view.task_text(pose).is_empty(),"generic public action has a label")

func test_default_shop_view_remains_on_existing_protocol_until_formal_migration() -> void:
	var owner := Fixture.owner()
	var frame := ShopView.new(owner).render_snapshot()
	check(not frame.has("presentation_version"),"U05 does not silently activate a second business loop")
	check(frame.has("stations") and frame.has("serve"),"existing formal sessions retain the old protocol until U06")

func test_bound_view_tracks_replaced_inventory_and_actor_cursor_after_restore() -> void:
	var runtime := Fixture.runtime()
	var view := _view(runtime)
	if view==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",2,0.6)
	for tick in 100:
		runtime.runner.step(0.1)
		if worker.carry_count==2: break
	var saved: Dictionary = runtime.snapshot()
	var saved_frame: Dictionary = view.render_snapshot()
	runtime.runner.cancel(worker.id)
	check_eq(view.render_snapshot().workers[0].held_items,[],"recall clears live presentation")
	check_eq(runtime.restore(saved),"","adopt previous physical carry and cursor")
	check_eq(view.render_snapshot(),saved_frame,"view follows the new adopted inventory without cached old objects")

func test_public_worker_pose_omits_legacy_job_fields_even_when_outer_record_contains_them() -> void:
	var runtime := Fixture.runtime()
	var view := _view(runtime)
	if view==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	worker.steps = [{"put_down":true}]
	worker.job = {"item":"wrong","dst":"missing"}
	worker.timer = 999.0
	var pose: Dictionary = view.render_snapshot().workers[0]
	check(not pose.has("steps") and not pose.has("job") and not pose.has("timer"),"legacy action metadata cannot leak into public presentation")
	check_eq(pose.held_items,[],"old job metadata cannot imply new goods")

func test_seat_card_uses_public_reservations_and_ignores_old_diners() -> void:
	var runtime := Fixture.runtime("self_pickup")
	var view := _view(runtime)
	if view==null: return
	runtime.runner.owner.diners = [{"seat":0}]
	check_eq(view.seats().used,0,"obsolete dining records cannot occupy public seats")
	runtime.arrive(Fixture.request())
	for tick in 150:
		runtime.step(0.1)
		if not runtime.service.orders.guest(1).seat.is_empty(): break
	check_eq(view.seats().used,1,"a real accepted guest owns one public seat")

func test_employee_card_reads_use_the_same_public_pose_as_scene_actors() -> void:
	var runtime := Fixture.runtime()
	var view := _view(runtime)
	if view==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",1,0.6)
	for tick in 100:
		runtime.runner.step(0.1)
		if worker.carry_count==1: break
	var pose: Dictionary = view.render_snapshot().workers[0]
	check_eq(view.worker_snapshot(worker.id),pose,"employee lookup is the same detached actor protocol")
	check_eq(view.deployed_snapshot()[0],pose,"deployed list does not expose legacy job state")
	check_eq(view.roster_snapshot()[0],pose,"roster uses the live deployed pose")

func test_activity_counts_and_clock_follow_public_service_while_wallet_stays_outer_owned() -> void:
	var runtime := Fixture.runtime()
	var view := _view(runtime)
	if view==null: return
	runtime.runner.owner.clock = 900.0
	runtime.runner.owner.lost = 99
	runtime.arrive(Fixture.request())
	var activity: Dictionary = view.activity_snapshot()
	check_eq(activity.clock,0.0,"activity uses the public clock")
	check_eq(activity.lost,0,"old lost-customer ledger is ignored")
	check_eq(activity.queue,1,"one actual public queued visitor")
	check_eq(activity.queue_capacity,2,"declared physical service capacity")
