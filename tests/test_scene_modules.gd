extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")

const MODULE := "res://presentation/shop/modules/shop_module.gd"
const SPACE := "res://presentation/shop/modules/module_space.gd"
const Contract := preload("res://presentation/shop/shop_scene_contract.gd")
const FIXTURE := "res://tests/fixtures/module_shop.gd"
var owned: Array[Node] = []

func cleanup() -> void:
	for node in owned:
		if is_instance_valid(node): node.free()
	owned.clear()

func _node(parent: Node, path: String, at := Vector2.ZERO, size := Vector2.ZERO) -> Node2D:
	var current := parent
	var parts := path.split("/")
	for i in parts.size():
		var child := current.get_node_or_null(NodePath(parts[i]))
		if child==null:
			child = AnchorRect.new() if i==parts.size()-1 and size!=Vector2.ZERO else Node2D.new()
			child.name = parts[i]
			current.add_child(child)
		current = child
	current.position = at
	if current is AnchorRect: current.size = size
	return current

func _module(parent: Node, kind: String, id: String, at: Vector2) -> Node2D:
	var node: Node2D = load(MODULE).new()
	node.name = id
	node.module_id = id
	node.module_kind = kind
	node.position = at
	parent.add_child(node)
	return node

func _art() -> Node2D:
	if not ResourceLoader.exists(MODULE) or not ResourceLoader.exists(SPACE):
		check(false,"editable module and spatial compiler must exist")
		return null
	var art := Node2D.new()
	owned.append(art)
	var anchors := _node(art,"Anchors")
	anchors.set_meta("module_version",1)
	anchors.set_meta("world_size",Vector2(720,1200))
	var nav := _node(anchors,"Nav")
	for pair in [["nav","grid"],["cell",40.0],["grid_size",Vector2i(18,30)],["motion_version",1],["motion_units",1.0],["spawn_point","counter"],["aliases",{}]]: nav.set_meta(pair[0],pair[1])
	_node(nav,"Areas/0",Vector2.ZERO,Vector2(720,1200))
	for profile in ["staff","customer"]: _node(nav,"Access/"+profile+"/0",Vector2.ZERO,Vector2(720,1200))
	_node(nav,"Points/home",Vector2(100,300))
	var sortables := _node(art,"Sortables")
	var station := _module(sortables,"counter","Front",Vector2(200,240))
	station.station_id = "counter"
	_node(station,"Visual")
	_node(station,"Anchors/Station/Tap",Vector2(-40,-80),Vector2(80,80))
	_node(station,"Anchors/Station/Frame",Vector2(-40,-80),Vector2(80,80))
	_node(station,"Anchors/Station/Post",Vector2(-30,10),Vector2(60,60))
	_node(station,"Anchors/Station/Buffer",Vector2(0,-20))
	_node(station,"Anchors/Drop",Vector2(-30,10),Vector2(60,60))
	_node(station,"Nav/Work",Vector2(0,40))
	_node(station,"Nav/Post",Vector2(0,40))
	_node(station,"Nav/Footprints/0",Vector2(-40,-80),Vector2(80,80))
	var table := _module(sortables,"table","TableA",Vector2(480,680))
	table.seat_group = "dine"
	_node(table,"Visual")
	_node(table,"Anchors/Table")
	_node(table,"Anchors/Seats/0",Vector2(-60,20))
	_node(table,"Nav/Seats/0",Vector2(-60,80))
	_node(table,"Nav/Footprints/0",Vector2(-40,-40),Vector2(80,40))
	var entrance := _module(sortables,"entrance","Door",Vector2(120,1000))
	_node(entrance,"Visual")
	_node(entrance,"Anchors/Entrance")
	_node(entrance,"Anchors/Exit",Vector2(40,0))
	_node(entrance,"Anchors/Queue/0",Vector2(0,-80))
	_node(entrance,"Nav/Customers/entrance")
	_node(entrance,"Nav/Customers/exit",Vector2(40,0))
	_node(entrance,"Nav/Customers/pickup",Vector2(120,-320))
	return art

func test_module_translation_moves_interaction_seats_queue_and_same_reader_without_stale_cache() -> void:
	var art := _art()
	if art==null: return
	var anchors := ShopAnchors.new(art.get_node("Anchors"))
	check_eq(anchors.rect("Stations/counter/Tap"),Rect2(160,160,80,80),"local interaction exports to world")
	check_eq(anchors.point("Stations/counter/Buffer"),Vector2(200,220),"buffer follows furniture")
	check_eq(anchors.meta("Drops/Front","post",""),"counter","drop defaults to stable station binding")
	check_eq(anchors.points("Seats/dine"),[Vector2(420,700)],"seat display has its own local offset")
	check_eq(anchors.points("Queue"),[Vector2(120,920)],"queue comes from entrance module")
	art.get_node("Sortables/Front").position += Vector2(80,40)
	art.get_node("Sortables/TableA").position += Vector2(40,80)
	art.get_node("Sortables/Door").position += Vector2(40,0)
	check_eq(anchors.rect("Stations/counter/Tap"),Rect2(240,200,80,80),"same reader follows moved station")
	check_eq(anchors.points("Seats/dine"),[Vector2(460,780)],"same reader follows moved table")
	check_eq(anchors.points("Queue"),[Vector2(160,920)],"same reader cannot retain cached queue coordinates")
	check_eq(anchors.children("Stations"),["counter"],"virtual groups enumerate module bindings")

func test_complete_module_space_exports_distinct_ports_permissions_obstacles_and_detached_data() -> void:
	var art := _art()
	if art==null: return
	var base := SpecLayout.new()
	var anchors := ShopAnchors.new(art.get_node("Anchors"))
	var result: Dictionary = anchors.export_layout(base)
	check_eq(result.errors,[],"valid module space compiles")
	if result.layout==null: return
	var data: SpecLayout = result.layout
	check_eq(data.points.counter,Vector2(200,280),"work approach is separate from visual center")
	check_eq(data.posts.counter,Vector2(200,280),"post follows module")
	check_eq(data.points["dine/0"],Vector2(420,760),"employee delivery port")
	check_eq(data.customer_points["seat:dine/0"],Vector2(420,760),"customer approach separate from seated sprite")
	check_eq(data.customer_queue,[Vector2(120,920)],"shared queue export")
	check_eq(data.obstacles,[Rect2(160,160,80,80),Rect2(440,640,80,40)],"all footprints share world coordinates")
	check_eq(data.obstacle_stations,["counter",""],"unlock gate and static furniture")
	check_eq(data.actor_areas,{"staff":[Rect2i(0,0,18,30)],"customer":[Rect2i(0,0,18,30)]},"pixel regions convert to grid")
	check_eq(data.motion_version,1,"rule motion protocol exported")
	data.points.counter = Vector2.ZERO
	data.actor_areas.staff.clear()
	check_eq(base.points,{},"original layout remains untouched")
	check_eq(anchors.export_layout(base).layout.points.counter,Vector2(200,280),"caller cannot mutate scene export")

func test_root_nav_exports_customer_seat_and_wait_approaches_without_reparenting_art() -> void:
	var art := _art()
	var nav := art.get_node("Anchors/Nav")
	_node(nav,"Customers/Seats/lounge/0",Vector2(500,800))
	_node(nav,"Customers/Waiting/cushion/0",Vector2(600,900))
	var result: Dictionary = ShopAnchors.new(art.get_node("Anchors")).export_layout(SpecLayout.new())
	check_eq(result.errors,[],"root seat approaches export with existing modules")
	if result.layout==null: return
	check_eq(result.layout.customer_points.get("seat:lounge/0"),Vector2(500,800),"dining approach")
	check_eq(result.layout.customer_points.get("wait:cushion/0"),Vector2(600,900),"waiting approach")

func test_module_errors_reject_ambiguous_bindings_transforms_and_unsupported_versions() -> void:
	for defect in ["duplicate_id","duplicate_port","scale","rotation","version","missing_work","bad_binding"]:
		var art := _art()
		if art==null: return
		var station: Node2D = art.get_node("Sortables/Front")
		match defect:
			"duplicate_id": art.get_node("Sortables/TableA").module_id = "Front"
			"duplicate_port": _node(art,"Anchors/Stations/counter/Tap",Vector2.ZERO,Vector2(20,20))
			"scale": station.scale = Vector2(2,1)
			"rotation": station.rotation = 0.2
			"version": art.get_node("Anchors").set_meta("module_version",2)
			"missing_work": station.get_node("Nav/Work").free()
			"bad_binding": station.station_id = "bad/path"
		var result: Dictionary = ShopAnchors.new(art.get_node("Anchors")).export_layout(SpecLayout.new())
		check(not result.errors.is_empty() and result.layout==null,"invalid authoring fails cleanly: "+defect)

func test_non_grid_regions_occupied_ports_and_disconnected_access_do_not_silently_export() -> void:
	for defect in ["fractional_grid","blocked_port","outside","disconnected","missing_customer","density","missing_grid","bad_cell","bad_aliases"]:
		var art := _art()
		if art==null: return
		match defect:
			"fractional_grid": art.get_node("Anchors/Nav/Areas/0").position.x = 1
			"blocked_port": art.get_node("Sortables/Front/Nav/Work").position = Vector2(0,-40)
			"outside": art.get_node("Sortables/TableA/Nav/Seats/0").position = Vector2(1000,0)
			"disconnected":
				art.get_node("Anchors/Nav/Access/customer/0").size = Vector2(320,1200)
				_node(art,"Anchors/Nav/Access/customer/1",Vector2(400,0),Vector2(320,1200))
			"missing_customer": art.get_node("Sortables/Door/Nav/Customers/exit").free()
			"density": art.get_node("Anchors/Nav").set_meta("motion_units",2.0)
			"missing_grid": art.get_node("Anchors/Nav").remove_meta("grid_size")
			"bad_cell": art.get_node("Anchors/Nav").set_meta("cell",0.0)
			"bad_aliases": art.get_node("Anchors/Nav").set_meta("aliases",{"counter":42})
		var result: Dictionary = ShopAnchors.new(art.get_node("Anchors")).export_layout(SpecLayout.new())
		check(not result.errors.is_empty() and result.layout==null,"unsafe space rejected: "+defect)

func _spec(art: Node) -> SpecShop:
	var shop := SpecShop.new()
	shop.layout = ShopAnchors.new(art.get_node("Anchors")).export_layout(SpecLayout.new()).layout
	var station := SpecStation.new()
	station.id = "counter"
	station.block = "counter"
	shop.stations.assign([station])
	var seats := SpecSeatGroup.new()
	seats.id = "dine"
	seats.start = 1
	shop.seat_groups.assign([seats])
	return shop

func test_preflight_compares_customer_permissions_queue_aliases_and_rejects_unknown_module_bindings() -> void:
	var art := _art()
	if art==null: return
	var shop := _spec(art)
	check_eq(Contract.validate(shop,art),[],"complete graybox anchor contract")
	for field in ["actor_areas","customer_points","customer_queue","motion_units","aliases","spawn_point"]:
		var changed: SpecShop = shop.duplicate(true)
		match field:
			"actor_areas": changed.layout.actor_areas.customer = [Rect2i(0,0,16,30)]
			"customer_points": changed.layout.customer_points.exit += Vector2(40,0)
			"customer_queue": changed.layout.customer_queue[0] += Vector2(40,0)
			"motion_units": changed.layout.motion_units = 2.0
			"aliases": changed.layout.aliases["counter"] = "home"
			"spawn_point": changed.layout.spawn_point = "home"
		check(not Contract.validate(changed,art).is_empty(),"same compiled fields compared at startup: "+field)
	art.get_node("Sortables/TableA").seat_group = "missing_group"
	check(Contract.validate(shop,art).any(func(e: Dictionary) -> bool: return e.code=="module_reference"),"unknown seat binding rejected before startup")

func test_reusable_prefabs_and_template_have_editable_local_ports() -> void:
	for name in ["station","counter","table","entrance_queue","space","ShopTemplate"]:
		var path := "res://presentation/shop/modules/%s.tscn"%name
		check(ResourceLoader.exists(path),"editable packed template exists: "+name)
		if not ResourceLoader.exists(path): continue
		var node: Node = load(path).instantiate()
		owned.append(node)
		check(node.has_node("Visual") if name!="ShopTemplate" else node.has_node("Sortables"),"replaceable visual or actor parent")
		check(node.has_node("Nav") if name!="ShopTemplate" else node.has_node("Anchors/Nav"),"editable spatial hierarchy")

func test_template_assembly_moves_all_ports_and_runs_real_parallel_delivery_with_exact_restore() -> void:
	check(ResourceLoader.exists(FIXTURE),"full module shop fixture exists")
	if not ResourceLoader.exists(FIXTURE): return
	var fixture: Script = load(FIXTURE)
	var assembled: Dictionary = fixture.assemble()
	var art: Node2D = assembled.art
	owned.append(art)
	var shop: SpecShop = assembled.shop
	check_eq(preload("res://game/rules/shop_spec_validator.gd").validate(shop),[],"composed shop is valid rule data")
	check_eq(Contract.validate(shop,art),[],"same modules pass real startup contract")
	art.get_node("Sortables/wok_a").position += Vector2(-40,0)
	art.get_node("Sortables/Table0").position += Vector2(40,0)
	art.get_node("Sortables/Entrance").position += Vector2(40,0)
	check(not Contract.validate(shop,art).is_empty(),"moving modules requires explicit data export")
	var exported: Dictionary = ShopAnchors.new(art.get_node("Anchors")).export_layout(shop.layout)
	check_eq(exported.errors,[],"moved fixture remains navigable")
	if exported.layout==null: return
	shop.layout = exported.layout
	check_eq(shop.layout.points.wok_a,Vector2(540,260),"moved production approach")
	check_eq(shop.layout.points["table/0"],Vector2(120,760),"moved table delivery port")
	check_eq(shop.layout.customer_points["seat:table/0"],Vector2(120,760),"moved customer approach")
	check_eq(shop.layout.customer_points.entrance,Vector2(160,1080),"moved entrance")
	check_eq(ShopAnchors.new(art.get_node("Anchors")).point("Seats/table/0"),Vector2(120,700),"seated sprite stays distinct from arrival")
	check_eq(Contract.validate(shop,art),[],"export repairs source/data mismatch")
	var rules: ShopRules = fixture.opened(shop)
	var routed := false
	for tick in 1400:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if worker.walking and worker.path.size()>2: routed = true
	check(rules.sold>=2,"module-composed shop completes real multi-item sales")
	check(routed,"employees use grid routes around footprints")
	var restored := LegacyRules.new(shop,42)
	check_eq(restored.load_dict(rules.to_dict()),"","module geometry supports active save restore")
	for tick in 100:
		rules.step(0.1)
		restored.step(0.1)
	check_eq(restored.to_dict(),rules.to_dict(),"module shop resumes with exact rule state")

func test_sync_cli_checks_without_writing_then_exports_only_explicit_shop() -> void:
	if not ResourceLoader.exists(FIXTURE): check(false,"module fixture exists"); return
	var fixture: Script = load(FIXTURE)
	var assembled: Dictionary = fixture.assemble()
	owned.append(assembled.art)
	var prefix := "user://module-cli-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	assembled.art.get_node("Sortables/wok_a").position += Vector2(-40,0)
	var saved: Dictionary = fixture.persist(assembled.shop,assembled.art,prefix)
	check_eq(saved.error,OK,"save explicit authoring fixture")
	var original := FileAccess.get_file_as_bytes(saved.shop_path)
	var output: Array = []
	var args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"-s","tools/sync_shop_layouts.gd","--","--shop="+saved.shop_path])
	var code := OS.execute(OS.get_executable_path(),args+PackedStringArray(["--check"]),output,true)
	check_eq(code,1,"check detects stale module export")
	check_eq(FileAccess.get_file_as_bytes(saved.shop_path),original,"check leaves exact original bytes")
	if code!=1:
		for path in [saved.scene_path,saved.shop_path]: DirAccess.remove_absolute(path)
		return
	output.clear()
	code = OS.execute(OS.get_executable_path(),args,output,true)
	check_eq(code,0,"explicit fixture can be synced: "+str(output))
	var synced: SpecShop = ResourceLoader.load(saved.shop_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check_eq(synced.layout.points.wok_a,Vector2(540,260),"CLI wrote translated operation port")
	output.clear()
	check_eq(OS.execute(OS.get_executable_path(),args+PackedStringArray(["--check"]),output,true),0,"fresh file passes read-only check")
	assembled.art.get_node("Sortables/wok_a").scale = Vector2(2,1)
	var bad: Dictionary = fixture.persist(synced,assembled.art,prefix+"-bad")
	var bad_bytes := FileAccess.get_file_as_bytes(bad.shop_path)
	args[args.size()-1] = "--shop="+bad.shop_path
	output.clear()
	check_eq(OS.execute(OS.get_executable_path(),args,output,true),1,"unsafe export fails explicitly")
	check_eq(FileAccess.get_file_as_bytes(bad.shop_path),bad_bytes,"unsafe export cannot rewrite source")
	for path in [saved.scene_path,saved.shop_path,bad.scene_path,bad.shop_path]: DirAccess.remove_absolute(path)

func test_module_visuals_follow_existing_unlocks_and_chair_count_without_changing_rules() -> void:
	if not ResourceLoader.exists(FIXTURE): check(false,"module fixture exists"); return
	var assembled: Dictionary = load(FIXTURE).assemble()
	owned.append(assembled.art)
	assembled.shop.seat_groups[0].steps.assign([1,1,1,1,1])
	var rules := LegacyRules.new(assembled.shop,42)
	var view := ShopView.new(rules)
	var before := var_to_bytes(rules.to_dict())
	check(not rules.nav.can_stand(Vector2(80,700),"staff"),"table assembly reserves chair footprint as well as tabletop")
	preload("res://presentation/shop/art_groups.gd").refresh(assembled.art,view)
	check_eq(var_to_bytes(rules.to_dict()),before,"module display cannot commit rule state")
	check(not assembled.art.get_node("Sortables/wok_a/Visual").visible,"locked equipment hides its replaceable visual")
	check(assembled.art.get_node("Sortables/Table3/Visual/Table").visible,"fixed tables reserve physical space")
	check(not assembled.art.get_node("Sortables/Table3/Visual/Seats/0").visible,"unbought chairs remain hidden")
	rules.gold = 100000.0
	rules.unlock("wok_a")
	rules.buy_seat()
	preload("res://presentation/shop/art_groups.gd").refresh(assembled.art,view)
	check(assembled.art.get_node("Sortables/wok_a/Visual").visible,"equipment follows station unlock")
	check(assembled.art.get_node("Sortables/Table3/Visual/Seats/0").visible,"seventh purchased seat enables one chair")
	check(not assembled.art.get_node("Sortables/Table3/Visual/Seats/1").visible,"eighth chair waits for its own seat")

func test_persisted_module_instances_reopen_without_orphaning_inherited_prefab_children() -> void:
	if not ResourceLoader.exists(FIXTURE): check(false,"module fixture exists"); return
	var baseline := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var fixture: Script = load(FIXTURE)
	var assembled: Dictionary = fixture.assemble()
	var prefix := "user://module-owners-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var saved: Dictionary = fixture.persist(assembled.shop,assembled.art,prefix)
	assembled.art.free()
	var reloaded: Node = load(saved.scene_path).instantiate()
	reloaded.free()
	check_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),baseline,"serialized instances must not duplicate and detach inherited children")
	for path in [saved.scene_path,saved.shop_path]: DirAccess.remove_absolute(path)

func test_table_mapping_rejects_wrong_slot_ranges_and_supports_explicit_three_seat_variant() -> void:
	for defect in ["start","table_index"]:
		var art := _art()
		if art==null: return
		var table: Node = art.get_node("Sortables/TableA")
		if defect=="start": table.first_seat = 1
		else: table.table_index = 1
		check(not ShopAnchors.new(art.get_node("Anchors")).export_layout(SpecLayout.new()).errors.is_empty(),"cup/table index must agree with seat range: "+defect)
	var art := _art()
	if art==null: return
	var table: Node = art.get_node("Sortables/TableA")
	check(table.get("seats_per_table")!=null,"module declares table capacity for shared cup mapping")
	if table.get("seats_per_table")==null: return
	table.set("seats_per_table",3)
	_node(table,"Anchors/Seats/1",Vector2(0,20))
	_node(table,"Anchors/Seats/2",Vector2(60,20))
	_node(table,"Nav/Seats/1",Vector2(0,80))
	_node(table,"Nav/Seats/2",Vector2(60,80))
	var anchors := ShopAnchors.new(art.get_node("Anchors"))
	check_eq(anchors.meta("Tables/dine","per_table",0),3,"table mapping publishes capacity to existing renderer")
	check_eq(anchors.export_layout(SpecLayout.new()).errors,[],"three-seat module exports without custom gameplay code")

func test_queue_order_and_missing_module_opt_in_are_explicit_authoring_errors() -> void:
	for defect in ["name","gap","opt_in"]:
		var art := _art()
		if art==null: return
		if defect=="opt_in": art.get_node("Anchors").remove_meta("module_version")
		else: art.get_node("Sortables/Door/Anchors/Queue/0").name = "invalid" if defect=="name" else "2"
		check(not ShopAnchors.new(art.get_node("Anchors")).export_layout(SpecLayout.new()).errors.is_empty(),"queue must have stable contiguous numeric order and modules must opt in: "+defect)

func test_empty_cli_target_is_rejected_instead_of_falling_back_to_production_campaign() -> void:
	for option in ["--shop=","--campaign="]:
		var args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"-s","tools/sync_shop_layouts.gd","--","--check",option])
		var output: Array = []
		check_eq(OS.execute(OS.get_executable_path(),args,output,true),1,"empty explicit target cannot select production: "+option)

func test_sync_does_not_silently_skip_invalid_scene_density_when_no_export_nav_exists() -> void:
	# Independent of whichever production scene is next migrated to modules.
	var art := Node2D.new()
	owned.append(art)
	_node(art,"Sortables")
	_node(art,"Anchors").set_meta("world_size",Vector2(720,1200))
	_node(art,"Anchors/Queue/0",Vector2(100,100))
	var shop := SpecShop.new()
	shop.layout = SpecLayout.new()
	shop.layout.motion_version = 1
	shop.layout.motion_units = 999.0
	var saved: Dictionary = load(FIXTURE).persist(shop,art,"user://no-nav-density-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	shop.scene_path = saved.scene_path
	var result: Dictionary = load("res://tools/sync_shop_layouts.gd").inspect(shop)
	check(not result.errors.is_empty(),"a non-exportable scene cannot discard its density error")
	for path in [saved.scene_path,saved.shop_path]: DirAccess.remove_absolute(path)

func test_campaign_sync_validates_every_candidate_before_writing_any_shop() -> void:
	var fixture: Script = load(FIXTURE)
	var good: Dictionary = fixture.assemble()
	var bad: Dictionary = fixture.assemble()
	owned.append_array([good.art,bad.art])
	var prefix := "user://module-batch-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	good.art.get_node("Sortables/wok_a").position += Vector2(-40,0)
	bad.art.get_node("Sortables/wok_a").scale = Vector2(2,1)
	var a: Dictionary = fixture.persist(good.shop,good.art,prefix+"-good")
	var b: Dictionary = fixture.persist(bad.shop,bad.art,prefix+"-bad")
	var campaign := SpecCampaign.new()
	var city := SpecCity.new()
	campaign.cities.assign([city])
	for path in [a.shop_path,b.shop_path]:
		var entry := SpecCampaignShop.new()
		entry.shop_path = path
		city.shops.append(entry)
	var campaign_path := prefix+"-campaign.tres"
	check_eq(ResourceSaver.save(campaign,campaign_path),OK,"save isolated campaign")
	var before := FileAccess.get_file_as_bytes(a.shop_path)
	var output: Array = []
	var args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"-s","tools/sync_shop_layouts.gd","--","--campaign="+campaign_path])
	check_eq(OS.execute(OS.get_executable_path(),args,output,true),1,"one invalid module stops campaign sync")
	check_eq(FileAccess.get_file_as_bytes(a.shop_path),before,"earlier valid candidate is not written before later validation")
	for path in [a.shop_path,a.scene_path,b.shop_path,b.scene_path,campaign_path]: DirAccess.remove_absolute(path)
