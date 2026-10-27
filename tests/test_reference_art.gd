extends "res://tests/test_case.gd"


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
