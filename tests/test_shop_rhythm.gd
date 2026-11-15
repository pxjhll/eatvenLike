extends "res://tests/test_case.gd"
const TOOL := "res://tools/shop_rhythm.gd"
const SHOP: SpecShop = preload("res://content/shops/pancake/shop.tres")

func _tool() -> Script:
	check(ResourceLoader.exists(TOOL),"reproducible rhythm tool exists")
	return load(TOOL) if ResourceLoader.exists(TOOL) else null

func test_sampling_is_repeatable_uses_exact_staff_target_and_does_not_mutate_definition() -> void:
	var tool := _tool()
	if tool==null: return
	var content := preload("res://game/rules/shop_content_contract.gd")
	var before := content.describe(SHOP)
	var a: Dictionary = tool.sample(SHOP,15.0,42)
	var b: Dictionary = tool.sample(SHOP,15.0,42)
	check_eq(a,b,"same seed, setup and ticks reproduce all metrics")
	check_eq(a.staff,2,"exact dual-employee setup")
	check_eq(a.ticks,150,"exact bounded simulation")
	check_eq(a.illegal_footprints,0,"real routes remain legal")
	check_eq(a.overspeed_samples,0,"no speed workaround")
	check_eq(a.restore_error,"","final state independently restores")
	check_eq(content.describe(SHOP),before,"sampling cannot edit formal data")
	var total := 0
	for count in a.worker_ticks.values(): total += int(count)
	check_eq(total,300,"every employee tick has one activity category")

func test_current_baseline_comparison_rejects_missing_shop_changed_content_and_metric_drift() -> void:
	var tool := _tool()
	if tool==null: return
	var report := {"version":1,"setup":{"seed":42,"seconds":15.0,"staff_target":2,"scenario":"all_unlocked"},"shops":{"pancake":tool.sample(SHOP,15.0,42)}}
	check_eq(tool.compare(report,report.duplicate(true)),[],"exact same evidence matches")
	check_eq(tool.compare(report,JSON.parse_string(JSON.stringify(report))),[],"saved JSON numbers match live integer metrics")
	for key in ["missing","content","metric","setup"]:
		var changed := report.duplicate(true)
		match key:
			"missing": changed.shops.clear()
			"content": changed.shops.pancake.content.gameplay = "different"
			"metric": changed.shops.pancake.sold += 1
			"setup": changed.setup.staff_target = 3
		check(not tool.compare(changed,report).is_empty(),"baseline flags "+key)

func test_rhythm_cli_rejects_invalid_parameters_before_overwriting_any_report() -> void:
	if _tool()==null: return
	var path := "user://rhythm-protected-%d.json"%Time.get_ticks_usec()
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string("sentinel")
	file.close()
	for args in [["--seconds=0"],["--seconds=nan"],["--seed=-1"],["--unknown"],["--output=res://content/shops/pancake/shop.tres"],["--seconds=0","--output="+path]]:
		var command := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"-s",TOOL,"--"])
		command.append_array(args)
		var output: Array = []
		check_eq(OS.execute(OS.get_executable_path(),command,output,true),1,"invalid CLI request fails")
		check_eq(FileAccess.get_file_as_string(path),"sentinel","invalid request cannot write")
	DirAccess.remove_absolute(path)
func test_public_diagnostics_count_completed_orders_from_the_actual_shared_service() -> void:
	var report: Dictionary = _tool().sample(SHOP,60.0,42)
	check(report.sale_events>0,"actual public sales occurred")
	check_eq(report.orders_done,report.sale_events,"diagnostic counts actual delivered public orders")

func test_recorded_rhythm_baseline_matches_formal_content_and_diagnostic_setup() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/baselines/shared_shop_rhythm.json"))
	check_eq(baseline.version,1,"rhythm baseline version remains explicit")
	check_eq(baseline.setup,{"seed":42.0,"seconds":600.0,"staff_target":2.0,"scenario":"all_unlocked"},"baseline retains the full diagnostic scenario")
	var ids: Array = baseline.shops.keys()
	ids.sort()
	check_eq(ids,["pancake","stirfry","tea"],"baseline must cover all formal shops")
	for id: String in ids:
		var row: Dictionary = baseline.shops[id]
		var shop: SpecShop = load("res://content/shops/%s/shop.tres"%id)
		var current_content: Dictionary = preload("res://game/rules/shop_content_contract.gd").describe(shop)
		check_eq(row.content,JSON.parse_string(JSON.stringify(current_content)),"baseline content is current: "+id)
		check_eq(row.ticks,6000.0,"full ten-minute sample: "+id)
		check_eq(row.staff,2.0,"two actual deployed staff: "+id)
		check_eq(row.illegal_footprints,0.0,"legal routes: "+id)
		check_eq(row.overspeed_samples,0.0,"no speed workaround: "+id)
		check_eq(row.restore_error,"","restorable final state: "+id)
		check_eq(row.orders_done,row.sale_events,"sales reflect shared service deliveries: "+id)
