extends "res://tests/test_case.gd"

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const NOODLE: SpecShop = preload("res://tests/fixtures/noodle/shop.tres")
const CONTRACT := "res://presentation/shop/shop_scene_contract.gd"

func test_scene_contract_accepts_shipped_scenes_and_keeps_optional_fallbacks() -> void:
	check(ResourceLoader.exists(CONTRACT), "scene preflight contract exists")
	if not ResourceLoader.exists(CONTRACT): return
	var contract: Script = load(CONTRACT)
	for shop in [TEA, PANCAKE, NOODLE]:
		var result: Dictionary = contract.prepare(shop)
		check_eq(result.errors, [], "shipped scene passes preflight: " + shop.id)
		if result.art == null: continue
		for path in (["Exit", "Waiting", "Counter/Pickup", "Counter/Sale"] if shop == TEA else ["Exit", "Entrance", "Waiting", "Aisle", "Counter/Pickup", "Counter/Sale"]):
			var optional: Node = result.art.get_node_or_null("Anchors/" + path)
			if optional != null: optional.free()
		check_eq(contract.validate(shop, result.art), [], "documented safe anchor fallbacks remain optional")
		result.art.free()

func test_scene_contract_rejects_inaccessible_interactions_and_bad_metadata() -> void:
	if not ResourceLoader.exists(CONTRACT):
		check(false, "scene preflight contract exists")
		return
	var contract: Script = load(CONTRACT)
	for path in ["Anchors", "Anchors/Stations/lemonade/Tap", "Anchors/Stations/lemonade/Frame", "Anchors/Queue"]:
		var art: Node = load(TEA.scene_path).instantiate()
		art.get_node(path).free()
		check(not contract.validate(TEA, art).is_empty(), "missing essential anchor rejected: " + path)
		art.free()
	for pair in [["world_size", Vector2(NAN, 100)], ["customer_height", -1.0], ["customer_speed", INF], ["sortables", "Missing"]]:
		var art: Node = load(TEA.scene_path).instantiate()
		art.get_node("Anchors").set_meta(pair[0], pair[1])
		var errors: Array = contract.validate(TEA, art)
		check(errors.any(func(e: Dictionary) -> bool: return String(e.path).contains(pair[0])), "metadata field path: " + pair[0])
		art.free()
	var transformed: Node = load(TEA.scene_path).instantiate()
	transformed.get_node("Anchors/Stations").rotation = 0.1
	check(not contract.validate(TEA, transformed).is_empty(), "translation-only anchor reader rejects rotation")
	transformed.free()
	for path in ["Anchors/Lanes", "Anchors/Connections/seal_to_shelf/Path", "Anchors/Seats/dine/7", "Anchors/Drops/2"]:
		var art: Node = load(TEA.scene_path).instantiate()
		art.get_node(path).free()
		check(not contract.validate(TEA, art).is_empty(), "declared routes, seating and posts stay reachable: " + path)
		art.free()
	var mismatch: Node = load(NOODLE.scene_path).instantiate()
	mismatch.get_node("Anchors/Nav/Points/board").position.x += 40
	check(not contract.validate(NOODLE, mismatch).is_empty(), "art navigation must match rule-space work points")
	mismatch.free()
	var bad_nav: Node = load(NOODLE.scene_path).instantiate()
	bad_nav.get_node("Anchors/Nav").set_meta("grid_size", "invalid")
	check(not contract.validate(NOODLE, bad_nav).is_empty(), "invalid Nav metadata is rejected before typed layout export")
	bad_nav.free()
	var no_front_drop: Node = load(TEA.scene_path).instantiate()
	for drop in no_front_drop.get_node("Anchors/Drops").get_children():
		if drop.get_meta("post", "") == "counter": drop.free()
	check(not contract.validate(TEA, no_front_drop).is_empty(), "draggable counter post remains accessible")
	no_front_drop.free()
	var fractional_table: Node = load(TEA.scene_path).instantiate()
	fractional_table.get_node("Anchors/Tables/dine").set_meta("per_table", 0.5)
	check(not contract.validate(TEA, fractional_table).is_empty(), "per_table cannot truncate to zero before seat division")
	fractional_table.free()

func test_prepare_rejects_missing_and_non_scene_resources_without_runtime_errors() -> void:
	if not ResourceLoader.exists(CONTRACT):
		check(false, "scene preflight contract exists")
		return
	var contract: Script = load(CONTRACT)
	for path in ["res://tests/fixtures/missing_scene.tscn", "res://tests/fixtures/noodle/shop.tres"]:
		var shop: SpecShop = TEA.duplicate(true)
		shop.scene_path = path
		var result: Dictionary = contract.prepare(shop)
		check(result.art == null and not result.errors.is_empty(), "bad resource yields structured error without candidate")
		check_eq(result.errors[0].path, "scene_path", "resource error identifies scene_path")

func test_preparation_frees_rejected_candidates() -> void:
	var contract: Script = load(CONTRACT)
	var path := "user://bad-art-%d.tscn" % OS.get_process_id()
	var spec: SpecShop = NOODLE.duplicate(true)
	spec.scene_path = path
	for node in [Node.new(), Node2D.new()]:
		var packed := PackedScene.new()
		check_eq(packed.pack(node), OK, "pack invalid candidate")
		node.free()
		check_eq(ResourceSaver.save(packed, path), OK, "write test art")
		# Drop the cache after replacing the same test path.
		ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
		var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		for unused in 3:
			var result: Dictionary = contract.prepare(spec)
			check(result.art == null and not result.errors.is_empty(), "rejected art is not returned")
		check_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), before, "no orphan candidates after failed preparation")
	DirAccess.remove_absolute(path)
