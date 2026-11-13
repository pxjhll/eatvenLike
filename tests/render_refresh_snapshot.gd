extends SceneTree
## A scene refresh shares its detached frame with the staff HUD.
class MeasuredView extends ShopView:
	var frames := 0
	func render_snapshot() -> Dictionary:
		frames += 1
		return super.render_snapshot()

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
		var scene: Node = load("res://presentation/shop/shop_play.tscn").instantiate()
		scene.session = session
		root.add_child(scene)
		scene.set_process(false)
		var measured := MeasuredView.new(owner)
		measured._displays = scene.view._displays
		measured._presentation = scene.view._presentation
		scene.view = measured
		for frame in 10: scene._refresh(0.0)
		if measured.frames!=10:
			failures += 1
			print("FAIL ",id," refresh builds ",measured.frames," frames for 10 refreshes")
		owner.workers[0].pos += Vector2(1,0)
		if scene.all_staff()[0].pos!=owner.workers[0].pos:
			failures += 1
			print("FAIL roster outside refresh must observe commands immediately")
		scene.free()
	for error in errors.take(): failures += 1; print("FAIL ",error)
	OS.remove_logger(errors)
	print("REFRESH SNAPSHOT: 3 shops, %d failures"%failures)
	quit(1 if failures else 0)
