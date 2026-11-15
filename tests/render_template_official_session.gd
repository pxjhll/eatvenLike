extends SceneTree
## Ordinary sessions own the only runtime, including scene stepping and saves.
const TestSession := preload("res://tests/shop_test_session.gd")
var errors := preload("res://tests/error_counter.gd").new()
var failures := 0
var checks := 0
var paths: Array = []
var results: Array = []

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: "+message)

func _shop(id: String) -> void:
	var spec: SpecShop = load("res://content/shops/"+id+"/shop.tres").copy_for_editing()
	var owner := ShopRules.new(spec,42)
	check(owner.runtime!=null and owner.runtime_error.is_empty(),id+": normal constructor owns the template runtime")
	owner.gold = 1000000.0
	for stage in spec.stages.size(): check(owner.unlock(spec.sold_at(stage)).is_empty(),"normal purchase")
	for material in owner.boxes: check(owner.unlock_box(material).is_empty(),"normal material purchase")
	while owner.roster.size()<2: check(owner.hire().is_empty(),"normal hiring")
	for worker in owner.roster:
		if not worker.deployed: check(owner.deploy_worker(worker.id).is_empty(),"normal deployment")
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(spec,"user://u06-official-"+id+"-"+str(Time.get_ticks_usec()),owner)
	for path in [scene.session.profile.path,scene.session.store.path,scene.session.tuning_path,scene.session.recording_path]: paths.append(path)
	root.add_child(scene); scene.set_process(false)
	check(not scene._startup_blocked,id+": ordinary scene startup: "+scene.save_status)
	if scene._startup_blocked: scene.free(); return
	check(scene.view._runtime==owner.runtime and scene.view._follows_owner,"scene binds the session runtime without a test injection")
	var restored := false
	var observer := func(_receipt: Dictionary) -> void:
		check(scene.session.save()==OK,"synchronous sale callback writes a complete disk snapshot")
	owner.events.on("sale",observer)
	for tick in 1800:
		scene._process(0.1)
		check(owner.runtime_error.is_empty(),id+": official simulation step "+owner.runtime_error)
		check(is_equal_approx(owner.clock,owner.runtime._clock),"one authoritative business clock")
		if tick==300:
			check(scene.session.save()==OK,"ordinary session save")
			var saved := owner.to_dict()
			var disk: ShopRules = scene.store.load_game()
			check(scene.store.load_error==OK and disk.to_dict()==saved,"actual disk state roundtrip")
			check(owner.load_dict(saved).is_empty(),"ordinary live restore")
			check(scene.view._runtime==owner.runtime,"open view follows replacement runtime")
			restored = true
		if owner.sold>=4 and tick>500: break
	owner.events.off("sale",observer)
	check(owner.sold>0,id+": actual formal production and settlement")
	check(restored,"restore point was exercised")
	var before: Dictionary = owner.runtime.snapshot()
	owner.paused = true; scene._process(0.2)
	check(owner.runtime.snapshot()==before,"ordinary scene pause freezes all public clocks")
	owner.paused = false
	for speed in [1.0,2.0,4.0]:
		scene._speed_factor = speed
		var clock: float = owner.clock
		scene._process(0.2)
		check(is_equal_approx(owner.clock-clock,0.2*speed),"scene applies playback speed exactly once")
	check(scene.session.save()==OK,"ordinary final session save")
	check(owner.inventory_diagnostics().is_empty(),"formal inventory conservation")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		check(capture.save_png("res://_work/unified_shop_template_20261112/u06-captures/"+id+".png")==OK,"capture actual formal session")
	results.append({"shop":id,"clock":owner.clock,"sold":owner.sold,"restored":restored,"public_version":owner.to_dict().version})
	scene.free()

func _run() -> void:
	root.size = Vector2i(720,1280)
	root.get_node("ShopAudio")._can_play = false
	for id in ["tea","pancake","stirfry"]: await _shop(id)
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for message in errors.take(): failures += 1; print("RUNTIME: "+message)
	OS.remove_logger(errors)
	var destination := OS.get_environment("U06_SESSION_REPORT")
	if not destination.is_empty():
		var report := FileAccess.open(destination,FileAccess.WRITE)
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"  "))
	print("OFFICIAL TEMPLATE SESSIONS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
