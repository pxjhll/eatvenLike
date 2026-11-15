extends SceneTree
## A scene refresh shares its detached frame with the staff HUD.
class MeasuredView extends ShopView:
	var frames := 0
	var show_test_gold := false
	var station_reads: Array[String] = []
	func render_snapshot() -> Dictionary:
		frames += 1
		var frame := super.render_snapshot()
		if show_test_gold: frame.gold = 123456.0
		return frame

	func station(id: String) -> Dictionary:
		station_reads.append(id)
		return super.station(id)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures := 0
	var errors := preload("res://tests/error_counter.gd").new()
	OS.add_logger(errors)
	for id in ["tea","pancake","stirfry"]:
		var shop: SpecShop = load("res://content/shops/"+id+"/shop.tres")
		var owner := ShopRules.new(shop,42)
		var profile := preload("res://game/app/profile.gd").new("user://refresh-profile-"+id+".json")
		profile.select_shop(id)
		var session := preload("res://game/app/shop_session.gd").new(profile,ShopSave.new(shop,"user://refresh-"+id+".json"),owner)
		session.guide_enabled = false
		session.recording_enabled = true
		session.recording_path = "user://refresh-recording-" + id + ".txt"
		var scene: Node = load("res://presentation/shop/shop_play.tscn").instantiate()
		scene.session = session
		root.add_child(scene)
		scene.set_process(false)
		var original_view: ShopView = scene.view
		var measured := MeasuredView.new(owner)
		measured._displays = original_view._displays
		measured._presentation = original_view._presentation
		scene.view = measured
		for frame in 10: scene._refresh(0.0)
		if measured.frames!=10:
			failures += 1
			print("FAIL ",id," refresh builds ",measured.frames," frames for 10 refreshes")
		for station_id in measured.station_reads:
			if owner.station_unlocked(station_id) or shop.stage_of(station_id) != measured.next_stage():
				failures += 1
				print("FAIL ", id, " built a full station panel for a hidden unlock sign: ", station_id)
				break
		owner.workers[0].pos += Vector2(1,0)
		if scene.all_staff()[0].pos!=owner.workers[0].pos:
			failures += 1
			print("FAIL roster outside refresh must observe commands immediately")
		scene.recorder.view = measured
		scene.recorder._clock = 59.9
		measured.show_test_gold = true
		measured.frames = 0
		scene._process(0.2)
		var recorded: Dictionary = JSON.parse_string(scene.recorder.text().split("\n", false)[-1])
		if measured.frames != 1 or recorded.get("gold") != 123456.0 or owner.gold == 123456.0:
			failures += 1
			print("FAIL ", id, " recorder must sample the same detached frame as the scene")
		scene.free()
	for error in errors.take(): failures += 1; print("FAIL ",error)
	OS.remove_logger(errors)
	print("REFRESH SNAPSHOT: 3 shops, %d failures"%failures)
	quit(1 if failures else 0)
