extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
## Real scene factories, with the same rabbit rendered in every shop.

const Session := preload("res://tests/shop_test_session.gd")
const Presentation := preload("res://content/characters/actor_presentation.tres")
const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/current/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://tests/fixtures/legacy_shops/current/pancake/shop.tres")
const STIRFRY: SpecShop = preload("res://tests/fixtures/legacy_shops/current/stirfry/shop.tres")
var errors := preload("res://tests/error_counter.gd").new()
var failures := 0
var checks := 0
var samples := {}
var paths: Array[String] = []

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _run() -> void:
	root.get_node("ShopAudio")._can_play = false
	DirAccess.make_dir_recursive_absolute("res://_work/shop_modularity/phase-b")
	for size in [Vector2i(720,1280),Vector2i(1280,720)]:
		root.size = size
		await process_frame
		var baseline := {}
		for spec: SpecShop in [TEA,PANCAKE,STIRFRY]:
			var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
			scene.session = Session.make(spec,"actor-scale-%s-%d"%[spec.id,OS.get_process_id()],LegacyRules.new(spec))
			for path: String in [scene.session.profile.path,scene.session.store.path,scene.session.tuning_path,scene.session.recording_path]:
				if not path in paths: paths.append(path)
			scene.set_process(false)
			root.add_child(scene)
			scene.set_process(false)
			await process_frame
			_check(scene.rules != null,spec.id+" starts with shared presentation")
			if scene.rules == null:
				scene.free()
				continue
			scene._fit()
			var unit_scale: float = scene._actor_unit_scale
			_check(is_equal_approx(unit_scale,Presentation.scene_units(scene._world_size)),spec.id+" uses shared scene units")
			_check(is_equal_approx(scene._customer_speed/unit_scale,170.0),spec.id+" customer speed uses logical tea units")
			var row := {"unit_scale":unit_scale,"roles":{}}
			for role in ["staff","customer"]:
				var height: float = scene._staff_height if role == "staff" else scene._customer_height
				_check(is_equal_approx(height,128.0 if role == "staff" else 110.0),spec.id+" canonical "+role+" height")
				var actor: Node2D = scene._actor("rabbit",height)
				scene._sortables.add_child(actor)
				var probe_position := Vector2(scene._world_size.x/2.0+(-70 if role == "staff" else 80)*unit_scale,600*unit_scale)
				actor.display({"id":-100,"pos":probe_position,"walking":false,"phase":"idle","task_label":""},0.0)
				_check(actor.scale.is_equal_approx(Vector2.ONE*unit_scale),spec.id+" scales entire "+role)
				await process_frame
				var bounds := _body_bounds(actor,scene,size)
				_check(bounds.has_area(),spec.id+" visible "+role+" sprite measured")
				row.roles[role] = {"logical_height":actor._height,"screen_width":bounds.size.x,"screen_height":bounds.size.y}
				if spec == TEA:
					baseline[role] = bounds.size
				else:
					_check((bounds.size-Vector2(baseline[role])).abs().x<=0.5 and (bounds.size-Vector2(baseline[role])).abs().y<=0.5,spec.id+" "+role+" screen size matches tea")
			if scene._dining != null:
				var diner: Node2D = scene._dining._actor("rabbit",scene._font)
				_check(diner.scale.is_equal_approx(Vector2.ONE*unit_scale),"Dining customer shares actor scale")
				diner.free()
			var drag: Node2D = scene._drag
			var worker: Dictionary = scene.rules.workers[0]
			var point: Vector2 = scene.get_node("Canvas").get_global_transform_with_canvas()*Vector2(worker.pos)
			drag._candidate(int(worker.id),point,true)
			_check(drag._grab_offset.is_equal_approx(Vector2(0,60)*unit_scale),spec.id+" drag grab offset matches actor scale")
			drag._start_drag()
			_check(drag._ghost.scale.is_equal_approx(Vector2.ONE*unit_scale),spec.id+" drag ghost uses shared factory")
			drag.cancel()
			samples["%s-%dx%d"%[spec.id,size.x,size.y]] = row
			if "--capture" in OS.get_cmdline_user_args():
				await process_frame
				await RenderingServer.frame_post_draw
				_check(root.get_texture().get_image().save_png("res://_work/shop_modularity/phase-b/%s-%dx%d.png"%[spec.id,size.x,size.y]) == OK,"Capture real shop "+spec.id)
			scene.free()
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var output := FileAccess.open("res://_work/shop_modularity/phase-b/actor-measurements.json",FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(samples,"  "))
	for error in errors.take():
		failures += 1
		print("RUNTIME: "+error)
	OS.remove_logger(errors)
	print("ACTOR PRESENTATION GUI: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _body_bounds(actor: Node2D, scene: Node2D, size: Vector2i) -> Rect2:
	var sprites: Array = actor.frame_actor.find_children("*","Sprite2D",true,false) if actor.frame_actor != null else [actor.body]
	if actor.frame_actor != null: sprites.append_array(actor.frame_actor.find_children("*","AnimatedSprite2D",true,false))
	var bounds := Rect2()
	var stretch := Vector2(size)/scene.get_viewport_rect().size
	for sprite: Node2D in sprites:
		if not sprite.is_visible_in_tree(): continue
		var local: Rect2
		if sprite is Sprite2D:
			if sprite.texture == null: continue
			local = sprite.get_rect()
		else:
			var animation := sprite as AnimatedSprite2D
			var texture := animation.sprite_frames.get_frame_texture(animation.animation,animation.frame)
			if texture == null: continue
			local = Rect2(animation.offset,texture.get_size())
			if animation.centered: local.position -= local.size/2.0
		var rect: Rect2 = sprite.get_global_transform_with_canvas()*local
		rect = Rect2(rect.position*stretch,rect.size*stretch)
		bounds = rect if not bounds.has_area() else bounds.merge(rect)
	return bounds

func _check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+label)
