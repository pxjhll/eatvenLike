extends "res://tests/test_case.gd"
const SHOP := "res://tests/fixtures/onboarding/shop.tres"
const CAMPAIGN := "res://tests/fixtures/onboarding/campaign.tres"
const STAFF := "res://content/characters/staff/hamster.tres"
var paths: Array[String] = []

func cleanup() -> void:
	for path in paths:
		for name in DirAccess.get_files_at("user://"):
			if name.begins_with(path.get_file()): DirAccess.remove_absolute("user://"+name)

func _available() -> bool:
	for path in [SHOP,CAMPAIGN,STAFF]:
		check(ResourceLoader.exists(path),"onboarding resource exists: "+path)
	return ResourceLoader.exists(SHOP) and ResourceLoader.exists(CAMPAIGN) and ResourceLoader.exists(STAFF)

func test_persisted_demo_is_valid_data_and_reuses_global_staff_and_module_prefabs() -> void:
	if not _available(): return
	var shop: SpecShop = load(SHOP)
	var campaign: SpecCampaign = load(CAMPAIGN)
	check_eq(preload("res://game/rules/shop_spec_validator.gd").validate(shop,campaign),[],"independent demo validates")
	check_eq(campaign.shop_ids(),["module_demo"],"demo stays outside production campaign")
	var prepared := preload("res://presentation/shop/shop_scene_contract.gd").prepare(shop)
	check_eq(prepared.errors,[],"saved scene and complete layout agree")
	if prepared.art!=null:
		var exported := ShopAnchors.new(prepared.art.get_node("Anchors")).export_layout(shop.layout)
		check_eq(exported.errors,[],"persisted module space exports")
		prepared.art.free()
	check(shop.dispatch.action_version==1 and shop.layout.motion_version==1 and shop.fulfillment.flow_version==1,"demo selects existing shared protocols")
	check_eq(shop.fulfillment.delivery_batch,"order","existing composite delivery capability")
	for kind in shop.staff.kinds: check(is_same(kind,load("res://content/characters/staff/%s.tres"%kind.id)),"global employee reference: "+kind.id)
	var hamster: SpecStaffKind = load(STAFF)
	check_eq(hamster.stats,{"walk":104.0,"work":1.0,"carry":2.0},"new staff uses a tea baseline profile")
	var characters := preload("res://presentation/characters/character_library.gd")
	check(characters.portrait(hamster.id)!=null and characters.FRAME_SCENES.has(hamster.id),"existing visual mapping resolves new employee without controller edits")

func _opened() -> ShopRules:
	var shop: SpecShop = load(SHOP)
	return preload("res://tests/fixtures/flow_shop.gd").opened(shop)

func test_new_employee_completes_real_composite_orders_and_exact_save_continuation() -> void:
	if not _available(): return
	var rules := _opened()
	var carried_two := false
	var worked := false
	var sold := false
	for tick in 3600:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if worker.kind=="hamster" and worker.phase=="work": worked = true
			carried_two = carried_two or worker.carry_count==2
		if rules.serve.orders_done>0 and worked and carried_two: sold = true; break
	check(sold and worked and carried_two,"new staff produces and delivers a real main-plus-side order")
	var path := "user://onboarding-%d.json"%Time.get_ticks_usec()
	paths.append(path)
	var store := ShopSave.new(rules.shop,path)
	check_eq(store.save_game(rules),OK,"new shop saves through existing path")
	var resumed := store.load_game()
	check_eq(store.load_error,OK,"new shop reopens")
	check_eq(resumed.to_dict(),rules.to_dict(),"exact complete state")
	for tick in 50:
		rules.step(0.1)
		resumed.step(0.1)
	check_eq(resumed.to_dict(),rules.to_dict(),"new employee and shop continue deterministically")

func test_demo_cancel_compensates_existing_bundle_and_retains_real_goods() -> void:
	if not _available(): return
	var rules := _opened()
	var flow := preload("res://game/rules/serve_flow.gd")
	var cancelled := false
	for tick in 3600:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job: Dictionary = flow.job_of(rules,worker)
			if job.get("kind","")!="bundle" or worker.carry_count!=1: continue
			var entries: Array = job.goods.duplicate(true)
			var post: String = worker.post
			check_eq(rules.recall_worker(worker.id),"","recall during multi-port collection")
			for entry: Dictionary in entries:
				var good: Dictionary = flow._good(rules,int(entry.id))
				check(not good.is_empty() and good.res==-1 and good.at==entry.from,"each original good is returned and unreserved")
			check_eq(rules.deploy_worker(worker.id,post),"","employee returns to the same delivery role")
			cancelled = true
			break
		if cancelled: break
	check(cancelled,"real demo reaches partially collected bundle")
	rules.run(90.0)
	check(rules.serve.orders_done>0,"demo keeps selling after compensation")
	check_eq(ShopRules.new(rules.shop,42).load_dict(rules.to_dict()),"","cancelled demo remains independently valid")
