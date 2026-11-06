extends "res://tests/test_case.gd"
## Catches preview leaks, layout drift, duplicate sprites and incorrect opening/unlock visibility.

const SCENE := "res://presentation/pancake/pancake_art.tscn"

func _art() -> Node2D:
	check(ResourceLoader.exists(SCENE), "approved pancake artwork has a runnable engine scene")
	if not ResourceLoader.exists(SCENE): return null
	var art: Node2D = load(SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(art)
	return art

func test_preview_actors_and_actor_shadows_are_excluded() -> void:
	var art := _art()
	if art == null: return
	for id in [29, 30, 38, 39, 44, 45, 58, 59, 60, 61, 78, 79, 80, 81, 82, 150, 151, 85, 87]:
		check(art.source_node(id) == null, "excluded preview/reference node %d" % id)
	for id in [140, 144, 145, 146, 147, 148, 133, 168]:
		var layer: Node2D = art.source_node(id)
		check(layer != null and not layer is Sprite2D, "text/shadow %d is code drawn" % id)
	art.free()

func test_shared_art_and_mirror_preserve_approved_geometry() -> void:
	var art := _art()
	if art == null: return
	for ids in [[14, 16, 41], [18, 20], [50, 51, 52], [53, 54, 55, 57], [66, 69, 73], [71, 72]]:
		for id in ids:
			check(art.source_node(id).texture == art.source_node(ids[0]).texture, "one resource for identical art %d" % id)
	var fryer: Sprite2D = art.source_node(32)
	check(fryer.global_position.distance_to(Vector2(88.5, 411)) < 0.001, "approved fryer anchor")
	check((fryer.texture.get_size() * fryer.scale).distance_to(Vector2(162, 151)) < 0.001, "approved fryer dimensions")
	var pipe: Sprite2D = art.source_node(22)
	check(pipe.global_transform.x.x < 0 and pipe.global_position.distance_to(Vector2(610, 215)) < 0.001, "pipe retains the author's mirror and anchor")
	art.free()

func test_opening_retains_fixed_decor_but_hides_function_groups() -> void:
	var art := _art()
	if art == null: return
	art.show_complete_layout()
	art.reset_layout()
	for id in [162, 62, 75, 83]:
		check(art.source_node(id).is_visible_in_tree(), "opening fixed group %d" % id)
	for id in [21, 26, 31, 34, 40, 46, 161, 166, 163, 164, 165]:
		check(not art.source_node(id).is_visible_in_tree(), "functional group %d requires state" % id)
	check(art.source_node(137).visible, "fixed table shadow is present at opening")
	check(not art.source_node(140).visible, "flour label is hidden with ingredient group")
	check(not art.source_node(143).visible, "counter shadow is hidden with the counter")
	art.free()

func test_function_labels_and_shadows_follow_owners() -> void:
	var art := _art()
	if art == null: return
	art.reset_layout()
	check(art.set_station_unlocked("raw_ingredients", true), "known group can be opened")
	check(art.source_node(26).visible and art.source_node(140).visible, "flour label follows raw ingredients")
	art.set_station_unlocked("raw_ingredients", false)
	check(not art.source_node(140).visible, "flour label vanishes when its owner closes")
	art.set_station_unlocked("front_counter", true)
	check(art.source_node(143).visible and not art.source_node(145).visible, "counter shadow opens independently of rack labels")
	art.set_station_unlocked("rack", true)
	check(art.source_node(145).visible, "rack label opens with rack")
	art.set_station_unlocked("front_counter", false)
	check(not art.source_node(145).visible and not art.source_node(143).visible, "nested labels and shadows obey ancestor state")
	check(not art.set_station_unlocked("not_a_station", true), "unknown keys do not open other groups")
	art.free()

func test_cushions_unlock_in_three_stages_with_matching_shadows() -> void:
	var art := _art()
	if art == null: return
	art.reset_layout()
	for row in [[0, 0], [1, 2], [2, 5], [3, 9], [-1, 0], [99, 9]]:
		art.set_cushion_stage(row[0])
		var cushions := 0
		var shadows := 0
		for id in range(66, 75):
			if art.source_node(id).is_visible_in_tree(): cushions += 1
		for id in range(152, 161):
			if art.source_node(id).visible: shadows += 1
		check_eq(cushions, row[1], "cumulative cushions at stage %d" % row[0])
		check_eq(shadows, row[1], "shadows follow available cushions at stage %d" % row[0])
	art.free()
