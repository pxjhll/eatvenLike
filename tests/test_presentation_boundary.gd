extends "res://tests/test_case.gd"
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")

func test_scene_staff_rows_are_fresh_and_deeply_detached() -> void:
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.rules = ShopRules.new(TEA)
	scene.view = ShopView.new(scene.rules)
	var before := var_to_bytes(scene.rules.to_dict())
	var roster: Array = scene.all_staff()
	check(not roster.is_empty(), "fixture has a real employee")
	roster[0].stats.walk = 999.0
	roster[0].job["boundary_probe"] = true
	check(var_to_bytes(scene.rules.to_dict()) == before, "editing nested scene roster must not mutate Rules")
	check(scene.all_staff()[0].stats.walk != 999.0, "later helper reads a fresh row")
	scene.free()


# Supplementary syntax guard: only known runtime owners/aliases are inspected.
# Public scalar methods, shared shop definitions and events remain allowed.
func _boundary_violations(source: String) -> Array[String]:
	var aliases: Array[String] = ["rules", "sim"]
	var clean := "\n".join(Array(source.split("\n")).map(func(line: String) -> String: return line.get_slice("#", 0)))
	var declaration := RegEx.new()
	declaration.compile("\\b([A-Za-z_][A-Za-z_0-9]*)\\s*:\\s*ShopRules\\b")
	for match_ in declaration.search_all(clean):
		if not aliases.has(match_.get_string(1)): aliases.append(match_.get_string(1))
	var assignment := RegEx.new()
	assignment.compile("\\b([A-Za-z_][A-Za-z_0-9]*)\\s*(?::[^=\\n]+)?[:]?=\\s*([^\\n;]+)")
	for unused in 4:
		for match_ in assignment.search_all(clean):
			var rhs: String = match_.get_string(2).strip_edges()
			if rhs in aliases or rhs.ends_with(".rules") or rhs.ends_with(".sim") or rhs == "_rules()":
				if not aliases.has(match_.get_string(1)): aliases.append(match_.get_string(1))
	var owner := "(?:" + "|".join(aliases) + "|_rules\\(\\))"
	var fields := "workers|roster|stations|shelf_stock|orders|customers|queue|diners|belts|belt_items|seats|tune|levels|boxes|chains|unlocked|sold_by_dish|hire_pool|event_defs|event_ready_at|events_seen|pending_events|belt_clock|order_ramp|pots|autos|seatables|dish_ids|front_dishes|kitchen_dishes|station_output|station_input|nav|rng|event_rng|mods|pot_busy|side_idle"
	var access := RegEx.new()
	access.compile("\\b" + owner + "\\s*\\.\\s*(?:(?:" + fields + ")\\b|_[A-Za-z_0-9]+\\s*\\(|(?:worker_by_id|customer|waiting_customers|execute_command)\\s*\\()")
	var writes := RegEx.new()
	writes.compile("\\b" + owner + "\\s*\\.\\s*[A-Za-z_][A-Za-z_0-9]*\\s*(?:\\[[^\\n]+?\\]\\s*)?(?:[+*/-]=|=(?!=))")
	var result: Array[String] = []
	for match_ in access.search_all(clean): result.append(match_.get_string())
	for match_ in writes.search_all(clean): result.append(match_.get_string())
	return result

func test_source_guard_recognizes_runtime_aliases_and_keeps_public_queries() -> void:
	for source in ["rules.roster[0].stats.work = 99", "var current: ShopRules = owner.rules\ncurrent.nav.post(id)", "var current = owner.rules\nvar copy = current\ncopy.orders.clear()", "sim.workers.size()", "_rules().customer(2)", "game.rules.paused = true", "rules._kind(id)", "rules.execute_command(\"hire\")"]:
		check(not _boundary_violations(source).is_empty(), "guard rejects runtime access: " + source)
	check(_boundary_violations("rules.queue_size()\nrules.customer_interval()\nrules.shop.stations\nrules.events.on(event, callback)\nrules.command_status(command)\nrules.paused == true\nview.roster_snapshot()").is_empty(), "public values, definitions, events and read models remain allowed")

func _audit_directory(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		if file.ends_with(".gd"):
			var violations := _boundary_violations(FileAccess.get_file_as_string(path.path_join(file)))
			check(violations.is_empty(), path.path_join(file) + " crosses presentation boundary: " + str(violations))
	for directory in DirAccess.get_directories_at(path): _audit_directory(path.path_join(directory))

func test_presentation_sources_use_only_detached_or_public_reads_and_owned_writes() -> void:
	_audit_directory("res://presentation")

func test_art_groups_follow_current_model_without_live_runtime_access() -> void:
	var rules := ShopRules.new(TEA)
	var view := ShopView.new(rules)
	var art := Node2D.new()
	Engine.get_main_loop().root.add_child(art)
	var station := Node2D.new()
	station.set_meta("layout_group", "opening")
	station.set_meta("unlock_rule", "lemonade")
	art.add_child(station)
	var shadow := Node2D.new()
	shadow.set_meta("follows", station)
	art.add_child(shadow)
	var groups := load("res://presentation/shop/art_groups.gd")
	groups.refresh(art, view)
	check(not station.visible and not shadow.visible, "closed opening hides art and follower")
	rules.execute_command("unlock", {"id": "lemonade"})
	groups.refresh(art, view)
	check(station.visible, "new unlock is visible through fresh projection")
	check_eq(shadow.visible, station.is_visible_in_tree(), "follower tracks owner visibility in current tree")
	art.free()

