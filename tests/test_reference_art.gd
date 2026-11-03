extends "res://tests/test_case.gd"


func test_reference_textures_fit_256_pixels_per_cell_budget() -> void:
	var art: Node2D = load("res://presentation/reference/shop_art.tscn").instantiate()
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference_texture_budget.json"))
	var resized_uses: Array = audit.get("layout_revision", {}).get("density_exemptions", [])
	# One nominal display cell is 100 units. Keep enough pixels for the largest use.
	var largest_scale := {}
	for sprite in art.find_children("*", "Sprite2D", true, false):
		if sprite.texture == null: continue
		var path: String = sprite.texture.resource_path
		largest_scale[path] = maxf(largest_scale.get(path, 0.0), maxf(sprite.scale.x, sprite.scale.y))
	# The walking probe also uses the cat texture, at 104 x 140 display units.
	var cat_path := "res://art/reference/cat.png"
	var cat: Texture2D = load(cat_path)
	largest_scale[cat_path] = maxf(largest_scale[cat_path], maxf(104.0 / cat.get_width(), 140.0 / cat.get_height()))
	for path in largest_scale:
		if path in resized_uses: continue
		check(1.0 / largest_scale[path] <= 2.56 + 0.02, "no excessive texture density: " + path)
	art.free()


func test_texture_optimization_preserves_existing_sprite_geometry() -> void:
	var audit_path := "res://tests/fixtures/reference_texture_budget.json"
	check(FileAccess.file_exists(audit_path), "texture optimization keeps a geometry audit")
	if not FileAccess.file_exists(audit_path):
		return
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(audit_path))
	var art: Node2D = load("res://presentation/reference/shop_art.tscn").instantiate()
	var revised: Array = audit.get("perspective_revision", {}).get("nodes", [])
	revised.append_array(audit.get("layout_revision", {}).get("nodes", []))
	revised.append_array(audit.get("layout_revision", {}).get("removed_nodes", []))
	for row in audit.scene_geometry_before:
		if row.node in revised:
			continue
		var sprite: Sprite2D = art.get_node(row.node)
		var expected_position := Vector2(row.position[0], row.position[1])
		var expected_size := Vector2(row.size[0], row.size[1])
		check(sprite.position.distance_to(expected_position) < 0.001, "anchor unchanged: " + row.node)
		check((sprite.texture.get_size() * sprite.scale).distance_to(expected_size) < 0.001, "display size unchanged: " + row.node)
	art.free()


func test_round_props_share_one_camera_angle() -> void:
	# Stretching a pot or cup non-uniformly changes its rim ellipse, which reads as a different camera.
	var art: Node2D = load("res://presentation/reference/shop_art.tscn").instantiate()
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference_texture_budget.json"))
	var approved: Array = audit.get("layout_revision", {}).get("approved_nonuniform_nodes", [])
	for layer in ["equipment", "actors", "drinks"]:
		for node in art.find_children("*", "Node2D", true, false):
			if node.get_meta("art_layer", "") != layer:
				continue
			var sprite: Sprite2D = node.get_node("Sprite")
			if sprite.texture == null: continue # Fitted new props load their texture on entering the scene.
			if String(art.get_path_to(sprite)) in approved: continue # Exact author-approved dimensions have a separate FigCraft geometry check.
			check(absf(sprite.scale.x - sprite.scale.y) < 0.001, "uniform scale: " + str(node.name))
	var sorted: Node2D = art.get_node("Sortables")
	var sealer: Sprite2D = sorted.get_node("Sealer/Sprite")
	var sealer_bottom := sealer.position.y + sealer.texture.get_height() * sealer.scale.y
	check(absf(sealer_bottom) < 4.0, "sealer sorts at its front edge")
	check(sorted.get_node("Sealer").position.y > sorted.get_node("BeltHorizontal").position.y + 1.0, "cups entering the sealer pass behind its front")
	var machines: Node2D = sorted.get_node("MachineTable")
	check(machines.get_node("PearlPot").get_index() > machines.get_node("Brewer").get_index(), "the nearer pot draws over the brewer")
	art.free()


func test_art_scene_has_independent_occluders_and_clear_doorway() -> void:
	var path := "res://presentation/reference/shop_art.tscn"
	check(ResourceLoader.exists(path), "layered art scene exists")
	if not ResourceLoader.exists(path):
		return
	var art: Node2D = load(path).instantiate()
	var sorted: Node2D = art.get_node("Sortables")
	check(sorted.y_sort_enabled, "walls and actors share floor-contact sorting")
	for id in ["PrepBench", "Rack", "Checkout", "Cat", "Fox"]:
		check(sorted.has_node(id), "independent node " + id)
	var prep: Sprite2D = sorted.get_node("PrepBench/Sprite")
	check(absf(prep.scale.x - prep.scale.y) < 0.005, "the straight prep bench preserves its native aspect ratio")
	check(sorted.has_node("MachineTable"), "cooker and brewer have an independent support table")
	for removed in ["PartitionLeft", "PartitionRight", "DoorLintel"]:
		check(not sorted.has_node(removed), "front and kitchen share an open passage: " + removed)
	art.free()


func test_ui_p0_art_covers_every_dish_and_checkout_keeps_its_aspect() -> void:
	var sim_script: GDScript = load("res://game/tea_playtest/tea_shop_sim.gd")
	for dish in sim_script.DISHES:
		check(ResourceLoader.exists("res://art/ui/drink_%s.png" % dish), "order bubble icon for " + dish)
	for name in ["coin", "coin_small", "bubble"]:
		check(ResourceLoader.exists("res://art/ui/%s.png" % name), "UI art " + name)
	# The counter used to be a 620 px image stretched 2.3x sideways; it is now drawn at scene width.
	var art: Node2D = load("res://presentation/reference/shop_art.tscn").instantiate()
	var checkout: Sprite2D = art.get_node("Sortables/Checkout/Sprite")
	check(absf(checkout.scale.x - checkout.scale.y) < 0.001, "checkout is not stretched")
	art.free()


func test_front_wood_uses_existing_floor_texture_below_the_counter() -> void:
	var art: Node2D = load("res://presentation/reference/shop_art.tscn").instantiate()
	var wood: Sprite2D = art.get_node("FrontWoodFloor")
	var floor_sprite: Sprite2D = art.get_node("Floor/Sprite")
	check(wood.texture == floor_sprite.texture and wood.region_enabled, "wood is a region of the unchanged existing floor PNG")
	var pixel := wood.texture.get_image().get_pixelv(Vector2i(wood.region_rect.position) + Vector2i(20, 20))
	check(pixel.r > pixel.b, "the front crop contains warm wood instead of kitchen tiles")
	check(wood.position.y <= art.get_node("Sortables/Checkout").position.y, "wood starts behind the counter boundary")
	check(wood.position.y + wood.region_rect.size.y * wood.scale.y >= 1500, "wood covers the expanded dining floor")
	art.free()
