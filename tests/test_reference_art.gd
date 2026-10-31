extends "res://tests/test_case.gd"


func test_reference_textures_fit_256_pixels_per_cell_budget() -> void:
	var art: Node2D = load("res://presentation/reference/shop_art.tscn").instantiate()
	# One nominal display cell is 100 units. Keep enough pixels for the largest use.
	var largest_scale := {}
	for sprite in art.find_children("*", "Sprite2D", true, false):
		var path: String = sprite.texture.resource_path
		largest_scale[path] = maxf(largest_scale.get(path, 0.0), maxf(sprite.scale.x, sprite.scale.y))
	# The walking probe also uses the cat texture, at 104 x 140 display units.
	var cat_path := "res://art/reference/cat.png"
	var cat: Texture2D = load(cat_path)
	largest_scale[cat_path] = maxf(largest_scale[cat_path], maxf(104.0 / cat.get_width(), 140.0 / cat.get_height()))
	for path in largest_scale:
		check(1.0 / largest_scale[path] <= 2.56 + 0.02, "no excessive texture density: " + path)
	art.free()


func test_texture_optimization_preserves_existing_sprite_geometry() -> void:
	var audit_path := "res://art_src/reference/texture_budget.json"
	check(FileAccess.file_exists(audit_path), "texture optimization keeps a geometry audit")
	if not FileAccess.file_exists(audit_path):
		return
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(audit_path))
	var art: Node2D = load("res://presentation/reference/shop_art.tscn").instantiate()
	var revised: Array = audit.get("perspective_revision", {}).get("nodes", [])
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
	for layer in ["equipment", "actors", "drinks"]:
		for node in art.find_children("*", "Node2D", true, false):
			if node.get_meta("art_layer", "") != layer:
				continue
			var sprite: Sprite2D = node.get_node("Sprite")
			check(absf(sprite.scale.x - sprite.scale.y) < 0.001, "uniform scale: " + str(node.name))
	var sorted: Node2D = art.get_node("Sortables")
	var sealer: Sprite2D = sorted.get_node("Sealer/Sprite")
	var sealer_bottom := sealer.position.y + sealer.texture.get_height() * sealer.scale.y
	check(sealer_bottom >= 0.0 and sealer_bottom < 4.0, "sealer sorts at its front edge")
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
	for id in ["PartitionLeft", "PartitionRight", "DoorLintel", "PrepBench", "Rack", "Checkout", "Cat", "Fox"]:
		check(sorted.has_node(id), "independent node " + id)
	var left: Sprite2D = sorted.get_node("PartitionLeft/Sprite")
	var right: Sprite2D = sorted.get_node("PartitionRight/Sprite")
	var prep: Sprite2D = sorted.get_node("PrepBench/Sprite")
	check(absf(prep.scale.x - prep.scale.y) < 0.005, "the straight prep bench preserves its native aspect ratio")
	check(sorted.has_node("MachineTable"), "cooker and brewer have an independent support table")
	var left_edge: float = left.global_position.x + left.texture.get_width() * left.scale.x
	check(left_edge < right.global_position.x, "partition leaves an actual open doorway")
	var walls := Image.load_from_file("res://art_src/reference/walls.png")
	check(walls.get_pixel(450, 1020).a < 0.05, "door aperture is alpha, not painted floor")
	art.free()


func test_layers_hide_independently_without_moving_other_pieces() -> void:
	var preview: Node2D = load("res://presentation/reference/art_preview.tscn").instantiate()
	# The synchronous suite runs before SceneTree readiness. Lifecycle/input is tested by renderer QA.
	preview.art = preview.get_node("Canvas/ShopArt")
	var partition: Node2D = preview.art.get_node("Sortables/PartitionLeft")
	var original_position := partition.position
	preview.set_layer_visible(false, "furniture")
	check(not preview.art.get_node("Sortables/PrepBench").visible, "prep bench is independently hidden")
	check(partition.visible, "hiding furniture cannot remove the wall")
	check(preview.art.get_node("Floor").visible, "floor stays present")
	preview.set_layer_visible(false, "walls")
	check(not partition.visible, "partition is independently hidden")
	preview.set_layer_visible(true, "walls")
	check_eq(partition.position, original_position, "layer toggles preserve layout")
	preview.free()


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
