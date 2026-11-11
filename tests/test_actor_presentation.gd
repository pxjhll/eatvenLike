extends "res://tests/test_case.gd"

const PROFILE := "res://content/characters/actor_presentation.tres"
const CONTRACT := preload("res://presentation/shop/shop_scene_contract.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")

func _profile() -> Resource:
	if not ResourceLoader.exists(PROFILE):
		check(false,"Missing shared actor presentation profile")
		return null
	return load(PROFILE)

func test_global_tea_presentation_baseline() -> void:
	var data := _profile()
	if data == null: return
	check_eq(data.get("staff_height"),128.0,"Tea employee height")
	check_eq(data.get("customer_height"),110.0,"Tea customer height")
	check_eq(data.get("customer_speed"),170.0,"Tea customer speed")
	check_eq(data.get("reference_width"),720.0,"Logical reference width")
	check_eq(data.get("minimum_visible_height"),1100.0,"Original camera baseline")
	check_eq(data.call("validate"),PackedStringArray(),"Shared profile is valid")

func test_native_canvas_density_cancels_out_of_actor_screen_size() -> void:
	var data := _profile()
	if data == null: return
	for view_size in [Vector2(720,1280),Vector2(1280,720),Vector2(480,800)]:
		var expected_zoom := minf(view_size.x/720.0,view_size.y/1100.0)
		for world in [Vector2(720,1500),Vector2(937,1678),Vector2(887,1774)]:
			var fitted: Dictionary = data.call("fit",view_size,world)
			check(not fitted.is_empty(),"A valid canvas can fit")
			if fitted.is_empty(): continue
			check(is_equal_approx(float(fitted.unit_scale),world.x/720.0),"Native coordinate density")
			check(is_equal_approx(128.0*float(fitted.unit_scale)*float(fitted.world_factor),128.0*expected_zoom),"Same employee size across canvas densities")
			check(is_equal_approx(110.0*float(fitted.unit_scale)*float(fitted.world_factor),110.0*expected_zoom),"Same customer size across canvas densities")
			check(is_equal_approx(float(fitted.ui_factor),expected_zoom),"Existing UI zoom preserved")

func test_invalid_profile_and_window_values_are_rejected() -> void:
	var data := _profile()
	if data == null: return
	for key in ["staff_height","customer_height","customer_speed","reference_width","minimum_visible_height"]:
		for value in [0.0,-1.0,INF,NAN]:
			var invalid: Resource = data.duplicate(true)
			invalid.set(key,value)
			check(not invalid.call("validate").is_empty(),"Reject invalid global "+key)
			check(invalid.call("fit",Vector2(720,1280),Vector2(720,1500)).is_empty(),"Invalid profile cannot produce transforms")
	for size in [Vector2.ZERO,Vector2(-1,100),Vector2(INF,100),Vector2(100,NAN)]:
		check(data.call("fit",size,Vector2(720,1500)).is_empty(),"Invalid view is safely ignored")
		check(data.call("fit",Vector2(720,1280),size).is_empty(),"Invalid world is rejected")

func test_shop_cannot_override_global_actor_values() -> void:
	for pair in [["staff_height",128.0],["customer_height",110.0],["customer_speed",170.0]]:
		var art: Node2D = load(TEA.scene_path).instantiate()
		art.get_node("Anchors").set_meta(pair[0],pair[1])
		var errors := CONTRACT.validate(TEA,art)
		check(errors.any(func(e: Dictionary) -> bool: return e.code == "shared_actor_profile" and String(e.path).ends_with(pair[0])),"Reject even a valid per-shop actor override: "+pair[0])
		art.free()
